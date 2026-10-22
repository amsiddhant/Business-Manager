import 'dart:async';
import 'dart:math';

import '../core/app_exception.dart';
import '../core/enums.dart';
import '../core/permissions.dart';
import '../core/utils/id_generator.dart';
import '../models/access_request.dart';
import '../models/app_settings.dart';
import '../models/app_user.dart';
import '../models/audit_fields.dart';
import '../models/audit_log.dart';
import '../models/business.dart';
import '../models/campaign.dart';
import '../models/customer.dart';
import '../models/dealer.dart';
import '../models/expense.dart';
import '../models/goal.dart';
import '../models/order.dart';
import '../models/product.dart';
import 'backend.dart';
import 'backend_capabilities.dart';
import 'repo_change.dart';

/// Typed data-access layer over a [Backend].
///
/// Responsibilities:
///  * converts between domain models and raw maps,
///  * enforces role/permission and per-business authorization in the *service
///    layer* (not just the UI),
///  * stamps audit fields (createdAt/updatedAt/createdBy/updatedBy),
///  * writes audit-log entries for sensitive operations,
///  * keeps dealer costs mirrored into Business Expenses,
///  * announces every successful write on [changes], so the in-memory working
///    set updates in place instead of re-reading every collection.
///
/// The [currentUser] is injected so authorization can be enforced consistently.
class Repository {
  Repository({required Backend backend, AppUser? currentUser})
    : _backend = backend,
      _currentUser = currentUser;

  Backend _backend;
  AppUser? _currentUser;

  // Synchronous, so a listener has applied the change before the awaiting
  // save/delete call returns (a screen can open the new record straight away).
  final StreamController<RepoChange> _changes =
      StreamController<RepoChange>.broadcast(sync: true);

  /// Every successful entity write, in order.
  Stream<RepoChange> get changes => _changes.stream;

  /// The highest id number already known in memory for a prefix (e.g. 42 for
  /// `PROD-00042`). Set by the `DataController`; used as a floor when minting
  /// so a lagging counter can never hand out an id that is already loaded.
  int Function(String prefix)? idHint;

  /// Non-fatal notes for the Diagnostics panel, e.g. an audit entry the
  /// deployed security rules don't allow yet. Newest last, capped at 50.
  final List<String> diagnostics = [];

  // Ids reserved ahead of a bulk create (CSV import), by prefix.
  final Map<String, List<String>> _reservedIds = {};

  // The highest number minted this session, by prefix, and the chain that
  // runs mints one at a time. Together they stop two creates in flight (a
  // double-clicked Save) from both scanning before either write lands and
  // being handed the same id.
  final Map<String, int> _mintedUpTo = {};
  Future<void> _mintChain = Future.value();

  final Random _random = Random();

  Backend get backend => _backend;
  AppUser? get currentUser => _currentUser;

  /// Rebinds the repository to a new backend (e.g. after the Owner enables
  /// Firebase) and/or a freshly signed-in user.
  void rebind({Backend? backend, AppUser? currentUser}) {
    if (backend != null) _backend = backend;
    _currentUser = currentUser;
    _reservedIds.clear();
    _mintedUpTo.clear();
    _usersCache = null;
  }

  void setCurrentUser(AppUser? user) {
    if (user?.uid != _currentUser?.uid) {
      _usersCache = null;
      _mintedUpTo.clear();
    }
    _currentUser = user;
  }

  DateTime get _now => DateTime.now();

  // ---- Authorization helpers ------------------------------------------------

  void _require(Permission permission) {
    final user = _currentUser;
    if (user == null || !user.can(permission)) {
      throw const PermissionDeniedException();
    }
  }

  void _requireBusinessAccess(String businessId) {
    final user = _currentUser;
    if (user == null || !user.canAccessBusiness(businessId)) {
      throw const PermissionDeniedException(
        "You don't have access to this business.",
      );
    }
  }

  /// Grants access when the caller can reach *any* of [businessIds] (they share
  /// at least one assigned business with the record). Used for records that may
  /// be tagged to several businesses at once (e.g. customers).
  void _requireAnyBusinessAccess(Iterable<String> businessIds) {
    final user = _currentUser;
    if (user == null || !businessIds.any((id) => user.canAccessBusiness(id))) {
      throw const PermissionDeniedException(
        "You don't have access to this business.",
      );
    }
  }

  AuditFields _stampCreate() => AuditFields(
    createdAt: _now,
    updatedAt: _now,
    createdBy: _currentUser?.uid,
    updatedBy: _currentUser?.uid,
  );

  AuditFields _stampUpdate(AuditFields existing) =>
      existing.copyWith(updatedAt: _now, updatedBy: _currentUser?.uid);

  // ---- Writes ---------------------------------------------------------------

  /// The audit-log entry for an operation, or null when nobody is signed in.
  SetOp? _logOp(
    AuditAction action,
    String entityType,
    String entityId, {
    String? businessId,
    String summary = '',
  }) {
    final user = _currentUser;
    if (user == null) return null;
    final now = _now;
    // A random suffix keeps ids unique when two writes share a microsecond.
    final suffix = _random
        .nextInt(36 * 36 * 36 * 36)
        .toRadixString(36)
        .padLeft(4, '0');
    final id = 'LOG-${now.microsecondsSinceEpoch}-$suffix';
    final entry = AuditLog(
      id: id,
      userId: user.uid,
      userName: user.name,
      action: action,
      entityType: entityType,
      entityId: entityId,
      businessId: businessId,
      timestamp: now,
      summary: summary,
    );
    return SetOp(Collections.auditLogs, id, entry.toMap());
  }

  /// Writes [ops] together with the [optional] ones (audit entry, sign-in
  /// index): in one atomic batch where the backend supports it, otherwise one
  /// by one with the optional writes best-effort, as before.
  ///
  /// If the rules refuse the batch it is retried without the optional writes
  /// (their rules may not be deployed yet): the record itself matters more
  /// than its audit entry. The refusal is noted in [diagnostics].
  Future<void> _write(
    List<WriteOp> ops, {
    List<WriteOp?> optional = const [],
  }) async {
    final extra = optional.whereType<WriteOp>().toList();
    if (ops.any((op) => op.collection == Collections.users)) {
      _usersCache = null;
    }
    if (_backend case final BatchCapable batch) {
      if (extra.isEmpty) {
        await batch.commit(ops);
        return;
      }
      try {
        await batch.commit([...ops, ...extra]);
      } on AppException catch (e) {
        if (e.code != 'permission-denied') rethrow;
        await batch.commit(ops);
        final skipped = extra.map((o) => o.collection).toSet().join(', ');
        _note(
          'Saved without its $skipped entry: the deployed security rules '
          'refused it. Deploy the latest firestore.rules.',
        );
      }
      return;
    }
    for (final op in ops) {
      await _apply(op);
    }
    for (final op in extra) {
      try {
        await _apply(op);
      } catch (_) {
        // Audit logging must never block the primary operation.
      }
    }
  }

  Future<void> _apply(WriteOp op) => switch (op) {
    SetOp(:final collection, :final id, :final data) => _backend.setDoc(
      collection,
      id,
      data,
    ),
    DeleteOp(:final collection, :final id) => _backend.deleteDoc(
      collection,
      id,
    ),
  };

  void _note(String message) {
    diagnostics.add(message);
    if (diagnostics.length > 50) diagnostics.removeAt(0);
  }

  void _emit(RepoChange change) {
    if (!_changes.isClosed) _changes.add(change);
  }

  // ---- Businesses -----------------------------------------------------------

  Future<List<Business>> fetchBusinesses() async {
    final user = _currentUser;
    if (user == null) return const [];
    List<Business> all;
    if (user.isOwner) {
      // Owner may list the whole collection.
      final docs = await _backend.fetchCollection(Collections.businesses);
      all = docs.map(Business.fromMap).toList();
    } else {
      // Non-owners must NOT issue an unfiltered `list` (Firestore rejects the
      // whole query when not every doc is provably readable — "rules are not
      // filters"). Instead fetch each assigned business by id, which the rules
      // permit via `get`.
      final docs = await Future.wait(
        user.assignedBusinessIds.map(
          (id) => _backend.fetchDoc(Collections.businesses, id),
        ),
      );
      all = docs
          .whereType<Map<String, dynamic>>()
          .map(Business.fromMap)
          .toList();
    }
    return all..sort((a, b) => a.name.compareTo(b.name));
  }

  Future<Business> saveBusiness(
    Business business, {
    required bool isNew,
  }) async {
    _require(isNew ? Permission.createBusiness : Permission.editBusiness);
    var toSave = business;
    if (isNew) {
      final id = business.id.isEmpty
          ? await _nextScopedId(
              IdGenerator.businessPrefix,
              Collections.businesses,
            )
          : business.id;
      toSave = business.copyWith(id: id, audit: _stampCreate());
    } else {
      _requireBusinessAccess(business.id);
      toSave = business.copyWith(audit: _stampUpdate(business.audit));
    }
    await _write(
      [SetOp(Collections.businesses, toSave.id, toSave.toMap())],
      optional: [
        _logOp(
          isNew ? AuditAction.create : AuditAction.update,
          'Business',
          toSave.id,
          businessId: toSave.id,
          summary: toSave.name,
        ),
      ],
    );
    _emit(Upserted(Collections.businesses, toSave.id, toSave));
    return toSave;
  }

  /// Soft-deletes (archives) a business — financial data is never hard-deleted.
  ///
  /// Pass the in-memory [known] business to skip re-reading it.
  Future<void> archiveBusiness(String id, {Business? known}) async {
    _require(Permission.deleteBusiness);
    _requireBusinessAccess(id);
    var business = known;
    if (business == null) {
      final doc = await _backend.fetchDoc(Collections.businesses, id);
      if (doc == null) throw const NotFoundException();
      business = Business.fromMap(doc);
    }
    final archived = business.copyWith(
      status: EntityStatus.archived,
      audit: _stampUpdate(business.audit),
    );
    await _write(
      [SetOp(Collections.businesses, id, archived.toMap())],
      optional: [
        _logOp(
          AuditAction.archive,
          'Business',
          id,
          businessId: id,
          summary: business.name,
        ),
      ],
    );
    _emit(Upserted(Collections.businesses, id, archived));
  }

  // ---- Ids ------------------------------------------------------------------

  /// Mints the next sequential id for [prefix] in [collection].
  ///
  /// Uses the backend's `counters/{prefix}` document when it can (one read and
  /// one write, in a transaction). The counter is created lazily: the Owner
  /// seeds it from one scan of the collection the first time; until it exists
  /// — or while the rules for it aren't deployed — everyone falls back to the
  /// scan below, exactly as before.
  ///
  /// Ids reserved by [reserveIdsFor] (a CSV import) are handed out first.
  Future<String> _nextScopedId(
    String prefix,
    String collection, {
    int width = 5,
    bool arrayScoped = false,
  }) async {
    final reserved = _reservedIds[prefix];
    if (reserved != null && reserved.isNotEmpty) return reserved.removeAt(0);
    final ids = await _mintIds(
      prefix,
      collection,
      1,
      width: width,
      arrayScoped: arrayScoped,
    );
    return ids.single;
  }

  Future<List<String>> _mintIds(
    String prefix,
    String collection,
    int count, {
    int width = 5,
    bool arrayScoped = false,
  }) {
    final result = _mintChain.then(
      (_) => _mintIdsNow(
        prefix,
        collection,
        count,
        width: width,
        arrayScoped: arrayScoped,
      ),
    );
    _mintChain = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  Future<List<String>> _mintIdsNow(
    String prefix,
    String collection,
    int count, {
    required int width,
    required bool arrayScoped,
  }) async {
    final hint = max(idHint?.call(prefix) ?? 0, _mintedUpTo[prefix] ?? 0);
    List<String> block(int first) {
      _mintedUpTo[prefix] = max(_mintedUpTo[prefix] ?? 0, first + count - 1);
      return [
        for (var i = 0; i < count; i++)
          IdGenerator.format(prefix, first + i, width: width),
      ];
    }

    if (_backend case final CounterCapable counters) {
      try {
        var first = await counters.reserveNumbers(prefix, count, floor: hint);
        if (first == null && (_currentUser?.isOwner ?? false)) {
          final scanned = await _scanMaxNumber(
            prefix,
            collection,
            arrayScoped: arrayScoped,
          );
          first = await counters.reserveNumbers(
            prefix,
            count,
            floor: max(hint, scanned),
            create: true,
          );
        }
        if (first != null) return block(first);
      } on AppException catch (e) {
        // Most likely the counter rules aren't deployed yet; the scan still
        // works. Anything else will surface from the scan itself.
        _note(
          'Id counter for $prefix unavailable (${e.code ?? e.message}); '
          'used a scan instead.',
        );
      }
    }
    final scanned = await _scanMaxNumber(
      prefix,
      collection,
      arrayScoped: arrayScoped,
    );
    return block(max(scanned, hint) + 1);
  }

  /// The highest id number in [collection] the caller can see, *without* an
  /// unfiltered `list`. Owners scan the whole collection; non-owners scan only
  /// their assigned businesses — an unfiltered list would be rejected wholesale
  /// by the security rules ("rules are not filters"), which is exactly what
  /// broke record creation for Admin/User accounts.
  ///
  /// A non-owner's scan can't see other businesses, which is why the counter
  /// above is preferred: it is global, so ids never collide across businesses.
  ///
  /// [arrayScoped] marks collections scoped by an array membership field (e.g.
  /// customers' `businessIds`) rather than a scalar `businessId`. Non-owners
  /// must scan via the matching query type, otherwise a scalar `businessId`
  /// filter matches nothing and every id collides at `<prefix>-00001`, silently
  /// overwriting prior records.
  Future<int> _scanMaxNumber(
    String prefix,
    String collection, {
    bool arrayScoped = false,
  }) async {
    final user = _currentUser;
    List<Map<String, dynamic>> docs;
    if (user == null || user.isOwner) {
      docs = await _backend.fetchCollection(collection);
    } else if (arrayScoped) {
      final perBusiness = await Future.wait(
        user.assignedBusinessIds.map(_fetchCustomerDocsForBusiness),
      );
      docs = perBusiness.expand((d) => d).toList();
    } else {
      final perBusiness = await Future.wait(
        user.assignedBusinessIds.map(
          (id) => _backend.fetchCollection(collection, businessId: id),
        ),
      );
      docs = perBusiness.expand((d) => d).toList();
    }
    return IdGenerator.maxNumber(
      prefix,
      docs.map((e) => e['id'] as String? ?? ''),
    );
  }

  /// Reserves ids for [count] upcoming creates in [collection] (one counter
  /// transaction, or one scan) so a bulk import doesn't mint them one by one.
  /// Unused ids are simply skipped; call [releaseReservedIds] afterwards.
  Future<void> reserveIdsFor(String collection, int count) async {
    if (count <= 1) return;
    final spec = _idSpecs[collection];
    if (spec == null) return;
    final (prefix, width, arrayScoped) = spec;
    _reservedIds[prefix] = await _mintIds(
      prefix,
      collection,
      count,
      width: width,
      arrayScoped: arrayScoped,
    );
  }

  void releaseReservedIds() => _reservedIds.clear();

  /// Owner only, best-effort: makes sure every id counter exists and is at
  /// least the highest id already loaded (the Owner's working set holds every
  /// record), so everyone else mints from the global counter instead of a scan
  /// of just their own businesses. Costs one read per prefix; writes only a
  /// counter that is missing or behind.
  Future<void> healIdCounters(Map<String, int> highestByPrefix) async {
    final user = _currentUser;
    if (user == null || !user.isOwner) return;
    if (_backend case final CounterCapable counters) {
      await Future.wait(
        highestByPrefix.entries.map((e) async {
          try {
            await counters.ensureAtLeast(e.key, e.value);
          } on AppException catch (err) {
            _note(
              'Id counter for ${e.key} not updated '
              '(${err.code ?? err.message}).',
            );
          }
        }),
      );
    }
  }

  static const Map<String, (String, int, bool)> _idSpecs = {
    Collections.products: (IdGenerator.productPrefix, 5, false),
    Collections.campaigns: (IdGenerator.campaignPrefix, 5, false),
    Collections.orders: (IdGenerator.orderPrefix, 6, false),
    Collections.expenses: (IdGenerator.expensePrefix, 5, false),
    Collections.dealers: (IdGenerator.dealerPrefix, 5, false),
    Collections.customers: (IdGenerator.customerPrefix, 5, true),
  };

  // ---- Generic business-scoped helpers -------------------------------------

  Future<List<T>> _fetchScoped<T>(
    String collection,
    T Function(Map<String, dynamic>) fromMap, {
    String? businessId,
  }) async {
    final user = _currentUser;
    if (user == null) return const [];

    // Explicit single-business scope.
    if (businessId != null) {
      _requireBusinessAccess(businessId);
      final docs = await _backend.fetchCollection(
        collection,
        businessId: businessId,
      );
      return docs.map(fromMap).toList();
    }

    // Owner may list the whole collection unfiltered.
    if (user.isOwner) {
      final docs = await _backend.fetchCollection(collection);
      return docs.map(fromMap).toList();
    }

    // Non-owners must query per assigned business. An unfiltered `list` would
    // be rejected wholesale by Firestore ("rules are not filters"), whereas a
    // query filtered by `businessId` for an assigned business is permitted.
    final perBusiness = await Future.wait(
      user.assignedBusinessIds.map(
        (id) => _backend.fetchCollection(collection, businessId: id),
      ),
    );
    return perBusiness.expand((docs) => docs).map(fromMap).toList();
  }

  // ---- Products -------------------------------------------------------------

  Future<List<Product>> fetchProducts({String? businessId}) => _fetchScoped(
    Collections.products,
    Product.fromMap,
    businessId: businessId,
  );

  Future<Product?> fetchProduct(String id) async {
    final doc = await _backend.fetchDoc(Collections.products, id);
    if (doc == null) return null;
    final product = Product.fromMap(doc);
    _requireBusinessAccess(product.businessId);
    return product;
  }

  Future<Product> saveProduct(Product product, {required bool isNew}) async {
    _require(isNew ? Permission.createProduct : Permission.editProduct);
    _requireBusinessAccess(product.businessId);
    var toSave = product;
    if (isNew) {
      final id = await _nextScopedId(
        IdGenerator.productPrefix,
        Collections.products,
      );
      toSave = product.copyWith(id: id, audit: _stampCreate());
    } else {
      toSave = product.copyWith(audit: _stampUpdate(product.audit));
    }
    await _write(
      [SetOp(Collections.products, toSave.id, toSave.toMap())],
      optional: [
        _logOp(
          isNew ? AuditAction.create : AuditAction.update,
          'Product',
          toSave.id,
          businessId: toSave.businessId,
          summary: toSave.name,
        ),
      ],
    );
    _emit(Upserted(Collections.products, toSave.id, toSave));
    return toSave;
  }

  /// Pass the in-memory [known] product to skip re-reading it.
  Future<void> deleteProduct(String id, {Product? known}) async {
    _require(Permission.deleteProduct);
    final product =
        known ?? Product.fromMap(await _fetchOrThrow(Collections.products, id));
    _requireBusinessAccess(product.businessId);
    await _write(
      [DeleteOp(Collections.products, id)],
      optional: [
        _logOp(
          AuditAction.delete,
          'Product',
          id,
          businessId: product.businessId,
          summary: product.name,
        ),
      ],
    );
    _emit(Removed(Collections.products, id));
  }

  Future<Map<String, dynamic>> _fetchOrThrow(
    String collection,
    String id,
  ) async {
    final doc = await _backend.fetchDoc(collection, id);
    if (doc == null) throw const NotFoundException();
    return doc;
  }

  // ---- Campaigns ------------------------------------------------------------

  Future<List<Campaign>> fetchCampaigns({String? businessId}) => _fetchScoped(
    Collections.campaigns,
    Campaign.fromMap,
    businessId: businessId,
  );

  Future<Campaign> saveCampaign(
    Campaign campaign, {
    required bool isNew,
  }) async {
    _require(isNew ? Permission.createCampaign : Permission.editCampaign);
    _requireBusinessAccess(campaign.businessId);
    var toSave = campaign;
    if (isNew) {
      final id = await _nextScopedId(
        IdGenerator.campaignPrefix,
        Collections.campaigns,
      );
      toSave = campaign.copyWith(id: id, audit: _stampCreate());
    } else {
      toSave = campaign.copyWith(audit: _stampUpdate(campaign.audit));
    }
    await _write(
      [SetOp(Collections.campaigns, toSave.id, toSave.toMap())],
      optional: [
        _logOp(
          isNew ? AuditAction.create : AuditAction.update,
          'Campaign',
          toSave.id,
          businessId: toSave.businessId,
          summary: toSave.name,
        ),
      ],
    );
    _emit(Upserted(Collections.campaigns, toSave.id, toSave));
    return toSave;
  }

  /// Pass the in-memory [known] campaign to skip re-reading it.
  Future<void> deleteCampaign(String id, {Campaign? known}) async {
    _require(Permission.deleteCampaign);
    final campaign =
        known ??
        Campaign.fromMap(await _fetchOrThrow(Collections.campaigns, id));
    _requireBusinessAccess(campaign.businessId);
    await _write(
      [DeleteOp(Collections.campaigns, id)],
      optional: [
        _logOp(
          AuditAction.delete,
          'Campaign',
          id,
          businessId: campaign.businessId,
          summary: campaign.name,
        ),
      ],
    );
    _emit(Removed(Collections.campaigns, id));
  }

  // ---- Orders ---------------------------------------------------------------

  Future<List<Order>> fetchOrders({String? businessId}) =>
      _fetchScoped(Collections.orders, Order.fromMap, businessId: businessId);

  Future<Order> saveOrder(Order order, {required bool isNew}) async {
    _require(isNew ? Permission.createOrder : Permission.editOrder);
    _requireBusinessAccess(order.businessId);
    var toSave = order;
    if (isNew) {
      final id = await _nextScopedId(
        IdGenerator.orderPrefix,
        Collections.orders,
        width: 6,
      );
      toSave = order.copyWith(id: id, audit: _stampCreate());
    } else {
      toSave = order.copyWith(audit: _stampUpdate(order.audit));
    }
    await _write(
      [SetOp(Collections.orders, toSave.id, toSave.toMap())],
      optional: [
        _logOp(
          isNew ? AuditAction.create : AuditAction.update,
          'Order',
          toSave.id,
          businessId: toSave.businessId,
          summary: toSave.productName,
        ),
      ],
    );
    _emit(Upserted(Collections.orders, toSave.id, toSave));
    return toSave;
  }

  /// Pass the in-memory [known] order to skip re-reading it.
  Future<void> deleteOrder(String id, {Order? known}) async {
    _require(Permission.deleteOrder);
    final order =
        known ?? Order.fromMap(await _fetchOrThrow(Collections.orders, id));
    _requireBusinessAccess(order.businessId);
    await _write(
      [DeleteOp(Collections.orders, id)],
      optional: [
        _logOp(
          AuditAction.delete,
          'Order',
          id,
          businessId: order.businessId,
          summary: order.id,
        ),
      ],
    );
    _emit(Removed(Collections.orders, id));
  }

  // ---- Expenses -------------------------------------------------------------

  Future<List<Expense>> fetchExpenses({String? businessId}) => _fetchScoped(
    Collections.expenses,
    Expense.fromMap,
    businessId: businessId,
  );

  Future<Expense> saveExpense(Expense expense, {required bool isNew}) async {
    _require(isNew ? Permission.createExpense : Permission.editExpense);
    _requireBusinessAccess(expense.businessId);
    var toSave = expense;
    if (isNew) {
      final id = await _nextScopedId(
        IdGenerator.expensePrefix,
        Collections.expenses,
      );
      toSave = expense.copyWith(id: id, audit: _stampCreate());
    } else {
      toSave = expense.copyWith(audit: _stampUpdate(expense.audit));
    }
    await _write(
      [SetOp(Collections.expenses, toSave.id, toSave.toMap())],
      optional: [
        _logOp(
          isNew ? AuditAction.create : AuditAction.update,
          'Expense',
          toSave.id,
          businessId: toSave.businessId,
          summary: toSave.name,
        ),
      ],
    );
    _emit(Upserted(Collections.expenses, toSave.id, toSave));
    return toSave;
  }

  /// Pass the in-memory [known] expense to skip re-reading it.
  Future<void> deleteExpense(String id, {Expense? known}) async {
    _require(Permission.deleteExpense);
    final expense =
        known ?? Expense.fromMap(await _fetchOrThrow(Collections.expenses, id));
    _requireBusinessAccess(expense.businessId);
    if (expense.isFromDealer) {
      throw const AppException(
        'This expense is managed by its dealer. Edit or remove the dealer instead.',
      );
    }
    await _write(
      [DeleteOp(Collections.expenses, id)],
      optional: [
        _logOp(
          AuditAction.delete,
          'Expense',
          id,
          businessId: expense.businessId,
          summary: expense.name,
        ),
      ],
    );
    _emit(Removed(Collections.expenses, id));
  }

  // ---- Dealers --------------------------------------------------------------

  Future<List<Dealer>> fetchDealers({String? businessId}) =>
      _fetchScoped(Collections.dealers, Dealer.fromMap, businessId: businessId);

  Future<Dealer> saveDealer(Dealer dealer, {required bool isNew}) async {
    _require(isNew ? Permission.createDealer : Permission.editDealer);
    _requireBusinessAccess(dealer.businessId);
    var toSave = dealer;
    if (isNew) {
      final id = await _nextScopedId(
        IdGenerator.dealerPrefix,
        Collections.dealers,
      );
      toSave = dealer.copyWith(id: id, audit: _stampCreate());
    } else {
      toSave = dealer.copyWith(audit: _stampUpdate(dealer.audit));
    }
    // The dealer and its mirrored expense land together, or not at all.
    final mirror = _mirrorDealerExpense(toSave);
    await _write(
      [
        SetOp(Collections.dealers, toSave.id, toSave.toMap()),
        SetOp(Collections.expenses, mirror.id, mirror.toMap()),
      ],
      optional: [
        _logOp(
          isNew ? AuditAction.create : AuditAction.update,
          'Dealer',
          toSave.id,
          businessId: toSave.businessId,
          summary: toSave.name,
        ),
      ],
    );
    _emit(Upserted(Collections.dealers, toSave.id, toSave));
    _emit(Upserted(Collections.expenses, mirror.id, mirror));
    return toSave;
  }

  /// The Business Expense (category = Dealer) kept in sync with the dealer's
  /// cost so dealer spend automatically flows into operating expenses.
  Expense _mirrorDealerExpense(Dealer dealer) => Expense(
    id: 'EXP-DLR-${dealer.id}',
    businessId: dealer.businessId,
    name: 'Dealer: ${dealer.name}',
    category: ExpenseCategory.dealer,
    description: dealer.description,
    amount: dealer.cost,
    frequency: dealer.costFrequency,
    startDate: dealer.startDate,
    endDate: dealer.endDate,
    vendor: dealer.name,
    status: dealer.status,
    sourceDealerId: dealer.id,
    audit: _stampUpdate(dealer.audit),
  );

  /// Pass the in-memory [known] dealer to skip re-reading it.
  Future<void> deleteDealer(String id, {Dealer? known}) async {
    _require(Permission.deleteDealer);
    final dealer =
        known ?? Dealer.fromMap(await _fetchOrThrow(Collections.dealers, id));
    _requireBusinessAccess(dealer.businessId);
    final mirrorId = 'EXP-DLR-$id';
    await _write(
      [
        DeleteOp(Collections.dealers, id),
        // Remove the mirrored expense too.
        DeleteOp(Collections.expenses, mirrorId),
      ],
      optional: [
        _logOp(
          AuditAction.delete,
          'Dealer',
          id,
          businessId: dealer.businessId,
          summary: dealer.name,
        ),
      ],
    );
    _emit(Removed(Collections.dealers, id));
    _emit(Removed(Collections.expenses, mirrorId));
  }

  // ---- Customers ------------------------------------------------------------

  /// Customers can be tagged to several businesses, so scoping uses an
  /// `array-contains` query per assigned business (never an unfiltered list for
  /// non-owners), de-duplicated by customer id since one customer may match more
  /// than one of the caller's businesses.
  ///
  /// Each scoped read is a single `where('businessIds', arrayContains: id)`
  /// query for an assigned `id`. This is the only shape Firestore can prove
  /// authorizable against the customers read rule ("rules are not filters"): the
  /// query guarantees `id ∈ businessIds` for every result, and `id` is a member
  /// of the caller's assigned set, so the rule's `businessIds.hasAny(assigned)`
  /// holds for every returned document. A scalar `businessId` filter is NOT used
  /// — the field is never written (see [Customer.toMap]) and such a query is not
  /// provably authorizable, which would make Firestore reject the whole read.
  Future<List<Customer>> fetchCustomers({String? businessId}) async {
    final user = _currentUser;
    if (user == null) return const [];

    List<Map<String, dynamic>> docs;
    if (businessId != null) {
      _requireBusinessAccess(businessId);
      docs = await _fetchCustomerDocsForBusiness(businessId);
    } else if (user.isOwner) {
      docs = await _backend.fetchCollection(Collections.customers);
    } else {
      final perBusiness = await Future.wait(
        user.assignedBusinessIds.map(_fetchCustomerDocsForBusiness),
      );
      docs = perBusiness.expand((d) => d).toList();
    }

    final byId = <String, Customer>{};
    for (final doc in docs) {
      final c = Customer.fromMap(doc);
      byId[c.id] = c;
    }
    return byId.values.toList();
  }

  /// Customer documents tagged to [businessId] via the `businessIds` array.
  ///
  /// A single `array-contains` query — the only provably-authorizable shape for
  /// a non-owner (see [fetchCustomers]). No scalar `businessId` fallback: that
  /// field is never persisted and the extra query would be rejected wholesale.
  Future<List<Map<String, dynamic>>> _fetchCustomerDocsForBusiness(
    String businessId,
  ) => _backend.fetchWhereArrayContains(
    Collections.customers,
    'businessIds',
    businessId,
  );

  Future<Customer> saveCustomer(
    Customer customer, {
    required bool isNew,
  }) async {
    _require(isNew ? Permission.createCustomer : Permission.editCustomer);
    final user = _currentUser;
    final isOwner = user?.isOwner ?? false;

    var toSave = customer;
    if (isNew) {
      // A new customer must be tagged to at least one business, and a non-owner
      // may only tag businesses assigned to them.
      if (customer.businessIds.isEmpty) {
        throw const PermissionDeniedException(
          'Select at least one business for this customer.',
        );
      }
      if (!isOwner &&
          customer.businessIds.any(
            (id) => !(user?.canAccessBusiness(id) ?? false),
          )) {
        throw const PermissionDeniedException(
          'You can only tag customers to businesses assigned to you.',
        );
      }
      _requireAnyBusinessAccess(customer.businessIds);
      // A contract can only be recorded for a business the customer is tagged
      // to (and, since every tag is accessible for a non-owner above, only for
      // a business the caller can access).
      if (customer.contractsByBusiness.keys.any(
        (id) => !customer.businessIds.contains(id),
      )) {
        throw const PermissionDeniedException(
          'A service contract can only be recorded for a business the '
          'customer is tagged to.',
        );
      }
      final id = await _nextScopedId(
        IdGenerator.customerPrefix,
        Collections.customers,
        arrayScoped: true,
      );
      toSave = _withCustomerId(customer.copyWith(audit: _stampCreate()), id);
    } else {
      // Authorize the edit against the record's *current* tags, then merge back
      // any tags to businesses the caller cannot see so a non-owner never
      // silently drops (or leaks) a business outside their scope. This read
      // stays: the merge must use what is stored, not what is in memory.
      final existingDoc = await _backend.fetchDoc(
        Collections.customers,
        customer.id,
      );
      if (existingDoc == null) throw const NotFoundException();
      final existing = Customer.fromMap(existingDoc);
      _requireAnyBusinessAccess(existing.businessIds);

      var next = customer;
      if (!isOwner) {
        final hidden = existing.businessIds
            .where((id) => !(user?.canAccessBusiness(id) ?? false))
            .toList();
        // Drop any tag the caller cannot access from what they submitted, then
        // union the hidden prior tags back in.
        final visibleSubmitted = customer.businessIds.where(
          (id) => user?.canAccessBusiness(id) ?? false,
        );
        // A non-owner can neither see nor overwrite contracts for businesses
        // outside their scope: strip any submitted contract under a hidden
        // business, then restore the record's *stored* hidden contracts so an
        // edit made from a scoped view never drops (or forges) them.
        final mergedContracts = <String, BusinessContract>{
          for (final e in customer.contractsByBusiness.entries)
            if (user?.canAccessBusiness(e.key) ?? false) e.key: e.value,
          for (final id in hidden)
            if (existing.contractsByBusiness.containsKey(id))
              id: existing.contractsByBusiness[id]!,
        };
        next = customer.copyWith(
          businessIds: {...visibleSubmitted, ...hidden}.toList(),
          contractsByBusiness: mergedContracts,
        );
      }
      if (next.businessIds.isEmpty) {
        throw const PermissionDeniedException(
          'A customer must remain tagged to at least one business.',
        );
      }
      // A contract must be filed under a business the customer is tagged to.
      if (next.contractsByBusiness.keys.any(
        (id) => !next.businessIds.contains(id),
      )) {
        throw const PermissionDeniedException(
          'A service contract can only be recorded for a business the '
          'customer is tagged to.',
        );
      }
      toSave = next.copyWith(audit: _stampUpdate(next.audit));
    }
    await _write(
      [SetOp(Collections.customers, toSave.id, toSave.toMap())],
      optional: [
        _logOp(
          isNew ? AuditAction.create : AuditAction.update,
          'Customer',
          toSave.id,
          businessId: toSave.businessIds.isEmpty
              ? null
              : toSave.businessIds.first,
          summary: toSave.name,
        ),
      ],
    );
    _emit(Upserted(Collections.customers, toSave.id, toSave));
    return toSave;
  }

  Customer _withCustomerId(Customer c, String id) => Customer(
    id: id,
    businessIds: c.businessIds,
    name: c.name,
    businessType: c.businessType,
    size: c.size,
    contactNo: c.contactNo,
    email: c.email,
    city: c.city,
    state: c.state,
    country: c.country,
    socialMedia: c.socialMedia,
    dealStatus: c.dealStatus,
    description: c.description,
    contractsByBusiness: c.contractsByBusiness,
    contacts: c.contacts,
    comments: c.comments,
    audit: c.audit,
  );

  /// Pass the in-memory [known] customer to skip re-reading it.
  Future<void> deleteCustomer(String id, {Customer? known}) async {
    _require(Permission.deleteCustomer);
    final customer =
        known ??
        Customer.fromMap(await _fetchOrThrow(Collections.customers, id));
    _requireAnyBusinessAccess(customer.businessIds);
    await _write(
      [DeleteOp(Collections.customers, id)],
      optional: [
        _logOp(
          AuditAction.delete,
          'Customer',
          id,
          businessId: customer.businessIds.isEmpty
              ? null
              : customer.businessIds.first,
          summary: customer.name,
        ),
      ],
    );
    _emit(Removed(Collections.customers, id));
  }

  // ---- Users ----------------------------------------------------------------

  Future<List<AppUser>> fetchUsers() async {
    final docs = await _backend.fetchCollection(Collections.users);
    final users = docs.map(AppUser.fromMap).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    _usersCache = Future.value(users);
    return users;
  }

  Future<List<AppUser>>? _usersCache;

  /// [fetchUsers], read once per session and then reused (the Team Access
  /// cards on detail pages). Any user write through this repository, a new
  /// sign-in or a backend switch drops it.
  Future<List<AppUser>> fetchUsersCached() {
    final cached = _usersCache;
    if (cached != null) return cached;
    final next = fetchUsers();
    _usersCache = next;
    next.then(
      (_) {},
      onError: (Object _) {
        if (identical(_usersCache, next)) _usersCache = null;
      },
    );
    return next;
  }

  Future<AppUser?> fetchUserByUid(String uid) async {
    final doc = await _backend.fetchDoc(Collections.users, uid);
    return doc == null ? null : AppUser.fromMap(doc);
  }

  /// First-run bootstrap: if the project has never been claimed (no
  /// `meta/system` sentinel), the first authenticated user becomes the OWNER.
  /// This lets a fresh Firebase project be set up simply by signing in with
  /// Google, without hand-seeding a `users/{uid}` document.
  ///
  /// Returns the newly-provisioned Owner profile, or `null` if the project is
  /// already claimed (in which case an unknown user must be onboarded by the
  /// existing Owner and should not be granted access).
  Future<AppUser?> bootstrapFirstOwnerIfNeeded(AuthAccount account) async {
    final claimed = await _backend.fetchDoc(Collections.meta, 'system');
    if (claimed != null) return null;

    final now = _now;
    final name = account.displayName.trim().isNotEmpty
        ? account.displayName.trim()
        : (account.email.contains('@')
              ? account.email.split('@').first
              : 'Owner');
    final owner = AppUser(
      uid: account.uid,
      loginId: account.email.isNotEmpty ? account.email : account.uid,
      name: name,
      email: account.email,
      role: UserRole.owner,
      status: AccountStatus.active,
      audit: AuditFields(
        createdAt: now,
        updatedAt: now,
        createdBy: account.uid,
        updatedBy: account.uid,
      ),
    );
    // Write the profile first, then claim the project so subsequent sign-ins
    // are treated as ordinary users (to be onboarded by this Owner).
    await _backend.setDoc(Collections.users, account.uid, owner.toMap());
    await _backend.setDoc(Collections.meta, 'system', {
      'ownerUid': account.uid,
      'ownerEmail': account.email,
      'claimedAt': now.toIso8601String(),
    });
    return owner;
  }

  /// Resolves a friendly login id (or email) to a profile by scanning
  /// `users`. Only works where listing users is allowed (the Owner, or the
  /// local demo backend); sign-in uses [emailForLogin] instead.
  Future<AppUser?> resolveUserByLogin(String loginOrEmail) async {
    final docs = await _backend.fetchCollection(Collections.users);
    final needle = loginOrEmail.trim().toLowerCase();
    for (final doc in docs) {
      final user = AppUser.fromMap(doc);
      if (user.loginId.toLowerCase() == needle ||
          user.email.toLowerCase() == needle) {
        return user;
      }
    }
    return null;
  }

  /// The email to sign in with for [loginOrEmail], before anyone is signed in.
  ///
  /// An email is used as typed. A login id is looked up with a single `get`
  /// of `loginIndex/{id}` where the backend has security rules (listing users
  /// before sign-in is denied, which is what broke login-id sign-in); the demo
  /// backend has no rules, so it scans. Returns null when not found.
  Future<String?> emailForLogin(String loginOrEmail) async {
    final input = loginOrEmail.trim();
    if (input.contains('@')) return input;
    final key = loginIndexKey(input);
    if (key == null) return null;
    if (_backend case final PublicLookupCapable lookup) {
      try {
        final doc = await lookup.fetchPublicDoc(Collections.loginIndex, key);
        final email = (doc?['email'] as String?)?.trim() ?? '';
        return email.isEmpty ? null : email;
      } catch (_) {
        return null;
      }
    }
    try {
      return (await resolveUserByLogin(input))?.email;
    } catch (_) {
      return null;
    }
  }

  /// The `loginIndex` document id for a login id, or null when it doesn't
  /// need one (an email signs in directly) or can't be a document id.
  static String? loginIndexKey(String loginId) {
    final key = loginId.trim().toLowerCase();
    if (key.isEmpty || key.contains('@') || key.contains('/')) return null;
    if (key == '.' || key == '..' || key.startsWith('__')) return null;
    return key;
  }

  /// The sign-in index writes for saving [user] (replacing [previous]).
  List<WriteOp> _loginIndexOps(AppUser user, {AppUser? previous}) {
    final key = loginIndexKey(user.loginId);
    final oldKey = previous == null ? null : loginIndexKey(previous.loginId);
    return [
      if (oldKey != null && oldKey != key)
        DeleteOp(Collections.loginIndex, oldKey),
      if (key != null && user.email.isNotEmpty)
        SetOp(Collections.loginIndex, key, {'email': user.email.trim()}),
    ];
  }

  /// Rewrites the whole sign-in index from the user profiles (Owner action,
  /// e.g. after deploying the rules for the first time). Returns how many
  /// login ids it indexed.
  Future<int> rebuildLoginIndex() async {
    _require(Permission.manageUsers);
    final users = await fetchUsers();
    final ops = [for (final u in users) ..._loginIndexOps(u)];
    for (var i = 0; i < ops.length; i += BatchCapable.maxOps) {
      final chunk = ops.sublist(i, min(i + BatchCapable.maxOps, ops.length));
      if (_backend case final BatchCapable batch) {
        await batch.commit(chunk);
      } else {
        for (final op in chunk) {
          await _apply(op);
        }
      }
    }
    return ops.length;
  }

  /// Creates a new user: provisions an auth account then writes the profile.
  Future<AppUser> createUser({
    required String loginId,
    required String name,
    required String email,
    required UserRole role,
    required List<String> assignedBusinessIds,
    required String password,
  }) async {
    _require(Permission.manageUsers);
    if (role == UserRole.owner) {
      throw const AppException(
        'Owner accounts cannot be created from this screen.',
      );
    }
    final String uid;
    try {
      uid = await _backend.createAccount(email, password);
    } on AppException catch (e) {
      // A pre-existing auth account (e.g. the person already signed in with
      // Google) collides on email. Point the Owner to the approval flow, which
      // provisions a profile against that existing account instead.
      if (e.code == 'email-already-in-use') {
        throw const AppException(
          'Someone has already signed in with this email but has no profile '
          'yet. Ask them to sign in once (e.g. with Google), then approve '
          'their request under "Pending access requests" — that grants access '
          'without creating a duplicate account.',
          code: 'email-already-in-use',
        );
      }
      rethrow;
    }
    final user = AppUser(
      uid: uid,
      loginId: loginId,
      name: name,
      email: email,
      role: role,
      assignedBusinessIds: assignedBusinessIds,
      audit: _stampCreate(),
    );
    await _write(
      [SetOp(Collections.users, uid, user.toMap())],
      optional: [
        ..._loginIndexOps(user),
        _logOp(AuditAction.create, 'User', uid, summary: name),
      ],
    );
    return user;
  }

  /// Saves an edited profile. Pass the [previous] profile when you have it
  /// (otherwise it is read) so a changed login id drops its old index entry.
  Future<AppUser> saveUserProfile(AppUser user, {AppUser? previous}) async {
    _require(Permission.manageUsers);
    final before = previous ?? await fetchUserByUid(user.uid);
    final updated = user.copyWith(audit: _stampUpdate(user.audit));
    await _write(
      [SetOp(Collections.users, user.uid, updated.toMap())],
      optional: [
        ..._loginIndexOps(updated, previous: before),
        _logOp(AuditAction.update, 'User', user.uid, summary: user.name),
      ],
    );
    return updated;
  }

  Future<void> setUserStatus(String uid, AccountStatus status) async {
    _require(Permission.manageUsers);
    final doc = await _backend.fetchDoc(Collections.users, uid);
    if (doc == null) throw const NotFoundException();
    final before = AppUser.fromMap(doc);
    await saveUserProfile(before.copyWith(status: status), previous: before);
  }

  /// Permanently deletes a user *profile* (`users/{uid}`). Owner-only.
  ///
  /// Note: this removes the application profile and access grant. The
  /// underlying Firebase Auth account can only be deleted with Admin
  /// privileges (a server-side concern), so the account may still exist in
  /// Firebase Auth — but without a profile it cannot access the app, and if it
  /// signs in again it will simply raise a fresh access request. The Owner
  /// account itself can never be deleted from here.
  Future<void> deleteUser(String uid) async {
    _require(Permission.manageUsers);
    final doc = await _backend.fetchDoc(Collections.users, uid);
    if (doc == null) throw const NotFoundException();
    final user = AppUser.fromMap(doc);
    if (user.isOwner) {
      throw const AppException('The owner account cannot be deleted.');
    }
    if (uid == _currentUser?.uid) {
      throw const AppException('You cannot delete your own account.');
    }
    final key = loginIndexKey(user.loginId);
    await _write(
      [
        DeleteOp(Collections.users, uid),
        // Clear any lingering access request for the same identity.
        DeleteOp(Collections.accessRequests, uid),
      ],
      optional: [
        if (key != null) DeleteOp(Collections.loginIndex, key),
        _logOp(AuditAction.delete, 'User', uid, summary: user.name),
      ],
    );
  }

  // ---- Access requests ------------------------------------------------------

  /// Records a pending access request for a signed-in identity that has no
  /// profile yet. Best-effort and called *while the requester is still
  /// authenticated*, so the write is performed as that account (the security
  /// rules allow a signed-in user to create only their own request document).
  Future<void> recordAccessRequest(AuthAccount account) async {
    final request = AccessRequest(
      uid: account.uid,
      email: account.email,
      displayName: account.displayName,
      requestedAt: _now,
    );
    try {
      await _backend.setDoc(
        Collections.accessRequests,
        account.uid,
        request.toMap(),
      );
    } catch (_) {
      // Never surface a failure here — the sign-in has already been rejected
      // and the user is being signed out regardless.
    }
  }

  /// Lists pending access requests, newest first. Owner-only.
  Future<List<AccessRequest>> fetchAccessRequests() async {
    _require(Permission.manageUsers);
    final docs = await _backend.fetchCollection(Collections.accessRequests);
    return docs.map(AccessRequest.fromMap).toList()..sort(
      (a, b) => (b.requestedAt ?? DateTime(0)).compareTo(
        a.requestedAt ?? DateTime(0),
      ),
    );
  }

  /// Approves an access request by provisioning a `users/{uid}` profile against
  /// the requester's *existing* auth account. This is the path for identities
  /// that signed in (e.g. with Google) before the Owner created their profile —
  /// it never creates a new auth account, so it cannot collide on email.
  Future<AppUser> approveAccessRequest(
    AccessRequest request, {
    required String loginId,
    required String name,
    required UserRole role,
    required List<String> assignedBusinessIds,
    Set<Permission> grantedPermissions = const {},
    Set<Permission> revokedPermissions = const {},
  }) async {
    _require(Permission.manageUsers);
    if (role == UserRole.owner) {
      throw const AppException('Owner accounts cannot be assigned here.');
    }
    final existing = await _backend.fetchDoc(Collections.users, request.uid);
    if (existing != null) {
      throw const AppException(
        'This person already has a profile. Remove the request from the queue.',
      );
    }
    final user = AppUser(
      uid: request.uid,
      loginId: loginId,
      name: name,
      email: request.email,
      role: role,
      assignedBusinessIds: assignedBusinessIds,
      grantedPermissions: grantedPermissions,
      revokedPermissions: revokedPermissions,
      audit: _stampCreate(),
    );
    await _write(
      [
        SetOp(Collections.users, request.uid, user.toMap()),
        DeleteOp(Collections.accessRequests, request.uid),
      ],
      optional: [
        ..._loginIndexOps(user),
        _logOp(AuditAction.create, 'User', request.uid, summary: name),
      ],
    );
    return user;
  }

  /// Dismisses a pending access request without granting access. Owner-only.
  Future<void> denyAccessRequest(String uid) async {
    _require(Permission.manageUsers);
    await _backend.deleteDoc(Collections.accessRequests, uid);
  }

  /// Records that [user] signed in. Best-effort, and skipped when it was
  /// already recorded today, so it costs at most one write per person per day.
  ///
  /// Only the `lastLoginAt` field is written: the rules let a user update that
  /// one field of their own profile (rewriting the whole profile is
  /// Owner-only, which is why this used to fail for everyone else).
  Future<void> touchLastLogin(AppUser user) async {
    final now = _now;
    final last = user.lastLoginAt;
    if (last != null &&
        last.year == now.year &&
        last.month == now.month &&
        last.day == now.day) {
      return;
    }
    final backend = _backend;
    try {
      if (backend case final FieldUpdateCapable fields) {
        await fields.updateFields(Collections.users, user.uid, {
          'lastLoginAt': now.toIso8601String(),
        });
      } else {
        final doc = await backend.fetchDoc(Collections.users, user.uid);
        if (doc == null) return;
        final fresh = AppUser.fromMap(doc).copyWith(lastLoginAt: now);
        await backend.setDoc(Collections.users, user.uid, fresh.toMap());
      }
    } catch (_) {
      // Never block or fail a sign-in over a timestamp.
    }
  }

  // ---- Organisation settings ------------------------------------------------

  static const _settingsDoc = 'app';
  static const _logoDoc = 'logo';

  /// Logos are stored inline as a data URL; keep them small (≈150 KB).
  static const maxLogoChars = 210000;

  /// The `settings/app` document, or null when none has been saved yet (all
  /// defaults). One read.
  Future<AppSettings?> fetchAppSettings() async {
    if (_currentUser == null) return null;
    final doc = await _backend.fetchDoc(Collections.settings, _settingsDoc);
    return doc == null ? null : AppSettings.fromMap(doc);
  }

  /// The logo's data URL, or null when there's none. One read; callers only
  /// ask when the settings' `logoHash` changed.
  Future<String?> fetchLogo() async {
    if (_currentUser == null) return null;
    final doc = await _backend.fetchDoc(Collections.settings, _logoDoc);
    final url = doc?['dataUrl'];
    return url is String && url.isNotEmpty ? url : null;
  }

  /// Saves the organisation's settings in one write (plus the logo when
  /// [logoChanged]: [logoDataUrl] sets it, null removes it), with an audit
  /// entry. Returns what was saved, stamped with who and when.
  Future<AppSettings> saveAppSettings(
    AppSettings settings, {
    bool logoChanged = false,
    String? logoDataUrl,
  }) async {
    _require(Permission.manageSettings);
    final user = _currentUser!;
    if (logoDataUrl != null && logoDataUrl.length > maxLogoChars) {
      throw const AppException(
          'That logo is too large. Use an image under 150 KB.');
    }
    final toSave = settings.copyWith(updatedAt: _now, updatedBy: user.name);
    await _write(
      [
        SetOp(Collections.settings, _settingsDoc, toSave.toMap()),
        if (logoChanged)
          if (logoDataUrl == null)
            DeleteOp(Collections.settings, _logoDoc)
          else
            SetOp(Collections.settings, _logoDoc, {
              'dataUrl': logoDataUrl,
              'hash': toSave.branding.logoHash ?? '',
              'updatedAt': _now.toIso8601String(),
              'updatedBy': user.uid,
            }),
      ],
      optional: [
        _logOp(AuditAction.update, 'Settings', _settingsDoc,
            summary: 'Organisation settings'),
      ],
    );
    return toSave;
  }

  // ---- Goals ----------------------------------------------------------------

  /// Goals for every business the user can access (and, for the Owner, the
  /// organisation-wide ones). Non-owners query per assigned business, as the
  /// rules require.
  Future<List<Goal>> fetchGoals() async {
    final user = _currentUser;
    if (user == null) return const [];
    final List<Map<String, dynamic>> docs;
    if (user.isOwner) {
      docs = await _backend.fetchCollection(Collections.goals);
    } else {
      final perBusiness = await Future.wait(
        user.assignedBusinessIds.map(
          (id) => _backend.fetchCollection(Collections.goals, businessId: id),
        ),
      );
      docs = [for (final d in perBusiness) ...d];
    }
    return [for (final d in docs) ?Goal.fromMap(d)];
  }

  void _requireGoalAccess(String businessId) {
    _require(Permission.manageGoals);
    if (businessId == Goal.allBusinesses) {
      if (!(_currentUser?.isOwner ?? false)) {
        throw const PermissionDeniedException(
          'Only the owner can set goals for all businesses.',
        );
      }
      return;
    }
    _requireBusinessAccess(businessId);
  }

  /// Sets (or replaces) goals: one batch per [BatchCapable.maxOps] goals,
  /// with one audit entry per batch. Returns them as saved.
  Future<List<Goal>> saveGoals(List<Goal> goals) async {
    for (final g in goals) {
      _requireGoalAccess(g.businessId);
      if (g.target < 0 || g.target > Goal.maxTarget) {
        throw const AppException('A goal target is out of range.');
      }
    }
    final saved = [
      for (final g in goals)
        g.copyWith(
          note: g.note.length > Goal.maxNote
              ? g.note.substring(0, Goal.maxNote)
              : g.note,
          audit: g.audit.createdAt == null
              ? _stampCreate()
              : _stampUpdate(g.audit),
        ),
    ];
    const chunk = BatchCapable.maxOps - 1;
    for (var i = 0; i < saved.length; i += chunk) {
      final part = saved.sublist(i, min(i + chunk, saved.length));
      await _write(
        [for (final g in part) SetOp(Collections.goals, g.id, g.toMap())],
        optional: [
          _logOp(
            AuditAction.update,
            'Goal',
            part.length == 1 ? part.first.id : '${part.length} goals',
            businessId: part.first.scopeBusinessId,
            summary: part.length == 1
                ? '${part.first.metric.label} · ${part.first.period.label}'
                : 'Set ${part.length} goals',
          ),
        ],
      );
      for (final g in part) {
        _emit(Upserted(Collections.goals, g.id, g));
      }
    }
    return saved;
  }

  Future<Goal> saveGoal(Goal goal) async => (await saveGoals([goal])).first;

  Future<void> deleteGoals(List<Goal> goals) async {
    for (final g in goals) {
      _requireGoalAccess(g.businessId);
    }
    const chunk = BatchCapable.maxOps - 1;
    for (var i = 0; i < goals.length; i += chunk) {
      final part = goals.sublist(i, min(i + chunk, goals.length));
      await _write(
        [for (final g in part) DeleteOp(Collections.goals, g.id)],
        optional: [
          _logOp(
            AuditAction.delete,
            'Goal',
            part.length == 1 ? part.first.id : '${part.length} goals',
            businessId: part.first.scopeBusinessId,
            summary: part.length == 1
                ? '${part.first.metric.label} · ${part.first.period.label}'
                : 'Removed ${part.length} goals',
          ),
        ],
      );
      for (final g in part) {
        _emit(Removed(Collections.goals, g.id));
      }
    }
  }

  Future<void> deleteGoal(Goal goal) => deleteGoals([goal]);

  // ---- Audit logs -----------------------------------------------------------

  /// The latest [limit] audit entries, newest first, for the Owner only.
  /// Reads only those entries where the backend can order and limit on the
  /// server.
  Future<List<AuditLog>> fetchAuditLogs({int limit = 100}) async {
    if (!(_currentUser?.isOwner ?? false)) {
      throw const PermissionDeniedException();
    }
    final docs = switch (_backend) {
      final QueryCapable query => await query.fetchLatest(
        Collections.auditLogs,
        orderBy: 'timestamp',
        limit: limit,
      ),
      final backend => await backend.fetchCollection(Collections.auditLogs),
    };
    final logs = docs.map(AuditLog.fromMap).toList()
      ..sort(
        (a, b) =>
            (b.timestamp ?? DateTime(0)).compareTo(a.timestamp ?? DateTime(0)),
      );
    return logs.take(limit).toList();
  }
}
