import '../core/app_exception.dart';
import '../core/enums.dart';
import '../core/permissions.dart';
import '../core/utils/id_generator.dart';
import '../models/access_request.dart';
import '../models/app_user.dart';
import '../models/audit_fields.dart';
import '../models/audit_log.dart';
import '../models/business.dart';
import '../models/campaign.dart';
import '../models/customer.dart';
import '../models/dealer.dart';
import '../models/expense.dart';
import '../models/order.dart';
import '../models/product.dart';
import 'backend.dart';

/// Typed data-access layer over a [Backend].
///
/// Responsibilities:
///  * converts between domain models and raw maps,
///  * enforces role/permission and per-business authorization in the *service
///    layer* (not just the UI),
///  * stamps audit fields (createdAt/updatedAt/createdBy/updatedBy),
///  * writes audit-log entries for sensitive operations,
///  * keeps dealer costs mirrored into Business Expenses.
///
/// The [currentUser] is injected so authorization can be enforced consistently.
class Repository {
  Repository({required Backend backend, AppUser? currentUser})
      : _backend = backend,
        _currentUser = currentUser;

  Backend _backend;
  AppUser? _currentUser;

  Backend get backend => _backend;
  AppUser? get currentUser => _currentUser;

  /// Rebinds the repository to a new backend (e.g. after the Owner enables
  /// Firebase) and/or a freshly signed-in user.
  void rebind({Backend? backend, AppUser? currentUser}) {
    if (backend != null) _backend = backend;
    _currentUser = currentUser;
  }

  void setCurrentUser(AppUser? user) => _currentUser = user;

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
          "You don't have access to this business.");
    }
  }

  /// Grants access when the caller can reach *any* of [businessIds] (they share
  /// at least one assigned business with the record). Used for records that may
  /// be tagged to several businesses at once (e.g. customers).
  void _requireAnyBusinessAccess(Iterable<String> businessIds) {
    final user = _currentUser;
    if (user == null ||
        !businessIds.any((id) => user.canAccessBusiness(id))) {
      throw const PermissionDeniedException(
          "You don't have access to this business.");
    }
  }


  AuditFields _stampCreate() => AuditFields(
        createdAt: _now,
        updatedAt: _now,
        createdBy: _currentUser?.uid,
        updatedBy: _currentUser?.uid,
      );

  AuditFields _stampUpdate(AuditFields existing) => existing.copyWith(
        updatedAt: _now,
        updatedBy: _currentUser?.uid,
      );

  Future<void> _log(AuditAction action, String entityType, String entityId,
      {String? businessId, String summary = ''}) async {
    final user = _currentUser;
    if (user == null) return;
    final id = 'LOG-${_now.microsecondsSinceEpoch}';
    final entry = AuditLog(
      id: id,
      userId: user.uid,
      userName: user.name,
      action: action,
      entityType: entityType,
      entityId: entityId,
      businessId: businessId,
      timestamp: _now,
      summary: summary,
    );
    try {
      await _backend.setDoc(Collections.auditLogs, id, entry.toMap());
    } catch (_) {
      // Audit logging must never block the primary operation.
    }
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
      final docs = await Future.wait(user.assignedBusinessIds
          .map((id) => _backend.fetchDoc(Collections.businesses, id)));
      all = docs
          .whereType<Map<String, dynamic>>()
          .map(Business.fromMap)
          .toList();
    }
    return all..sort((a, b) => a.name.compareTo(b.name));
  }

  Future<Business> saveBusiness(Business business, {required bool isNew}) async {
    _require(isNew ? Permission.createBusiness : Permission.editBusiness);
    var toSave = business;
    if (isNew) {
      final existing = await _backend.fetchCollection(Collections.businesses);
      final id = business.id.isEmpty
          ? IdGenerator.next(IdGenerator.businessPrefix,
              existing.map((e) => e['id'] as String? ?? ''))
          : business.id;
      toSave = business.copyWith(id: id, audit: _stampCreate());
    } else {
      _requireBusinessAccess(business.id);
      toSave = business.copyWith(audit: _stampUpdate(business.audit));
    }
    await _backend.setDoc(Collections.businesses, toSave.id, toSave.toMap());
    await _log(isNew ? AuditAction.create : AuditAction.update, 'Business',
        toSave.id, businessId: toSave.id, summary: toSave.name);
    return toSave;
  }

  /// Soft-deletes (archives) a business — financial data is never hard-deleted.
  Future<void> archiveBusiness(String id) async {
    _require(Permission.deleteBusiness);
    _requireBusinessAccess(id);
    final doc = await _backend.fetchDoc(Collections.businesses, id);
    if (doc == null) throw const NotFoundException();
    final business = Business.fromMap(doc)
        .copyWith(status: EntityStatus.archived);
    await _backend.setDoc(Collections.businesses, id,
        business.copyWith(audit: _stampUpdate(business.audit)).toMap());
    await _log(AuditAction.archive, 'Business', id,
        businessId: id, summary: business.name);
  }

  // ---- Generic business-scoped helpers -------------------------------------

  /// Computes the next sequential id for [collection] *without* an unfiltered
  /// `list`. Owners scan the whole collection; non-owners scan only their
  /// assigned businesses — an unfiltered list would be rejected wholesale by
  /// the security rules ("rules are not filters"), which is exactly what broke
  /// record creation for Admin/User accounts.
  ///
  /// Because the Owner provisions the bulk of data (businesses and typically
  /// products), ids remain globally sequential in practice. The only way a
  /// non-owner could mint an id that already exists in a business they cannot
  /// see is if numbering was interleaved across businesses by the Owner; that
  /// edge case is documented here rather than hardened, since eliminating it
  /// entirely would require a server-side counter or a doc-key scheme change.
  ///
  /// [arrayScoped] marks collections scoped by an array membership field (e.g.
  /// customers' `businessIds`) rather than a scalar `businessId`. Non-owners
  /// must scan via the matching query type, otherwise a scalar `businessId`
  /// filter matches nothing and every id collides at `<prefix>-00001`, silently
  /// overwriting prior records.
  Future<String> _nextScopedId(String prefix, String collection,
      {int width = 5, bool arrayScoped = false}) async {
    final user = _currentUser;
    List<Map<String, dynamic>> docs;
    if (user == null || user.isOwner) {
      docs = await _backend.fetchCollection(collection);
    } else if (arrayScoped) {
      final perBusiness = await Future.wait(
          user.assignedBusinessIds.map(_fetchCustomerDocsForBusiness));
      docs = perBusiness.expand((d) => d).toList();
    } else {
      final perBusiness = await Future.wait(user.assignedBusinessIds
          .map((id) => _backend.fetchCollection(collection, businessId: id)));
      docs = perBusiness.expand((d) => d).toList();
    }
    return IdGenerator.next(prefix, docs.map((e) => e['id'] as String? ?? ''),
        width: width);
  }

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
      final docs =
          await _backend.fetchCollection(collection, businessId: businessId);
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
    final perBusiness = await Future.wait(user.assignedBusinessIds.map(
        (id) => _backend.fetchCollection(collection, businessId: id)));
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
          IdGenerator.productPrefix, Collections.products);
      toSave = product.copyWith(id: id, audit: _stampCreate());
    } else {
      toSave = product.copyWith(audit: _stampUpdate(product.audit));
    }
    await _backend.setDoc(Collections.products, toSave.id, toSave.toMap());
    await _log(isNew ? AuditAction.create : AuditAction.update, 'Product',
        toSave.id, businessId: toSave.businessId, summary: toSave.name);
    return toSave;
  }

  Future<void> deleteProduct(String id) async {
    _require(Permission.deleteProduct);
    final doc = await _backend.fetchDoc(Collections.products, id);
    if (doc == null) throw const NotFoundException();
    final product = Product.fromMap(doc);
    _requireBusinessAccess(product.businessId);
    await _backend.deleteDoc(Collections.products, id);
    await _log(AuditAction.delete, 'Product', id,
        businessId: product.businessId, summary: product.name);
  }

  // ---- Campaigns ------------------------------------------------------------

  Future<List<Campaign>> fetchCampaigns({String? businessId}) => _fetchScoped(
        Collections.campaigns,
        Campaign.fromMap,
        businessId: businessId,
      );

  Future<Campaign> saveCampaign(Campaign campaign, {required bool isNew}) async {
    _require(isNew ? Permission.createCampaign : Permission.editCampaign);
    _requireBusinessAccess(campaign.businessId);
    var toSave = campaign;
    if (isNew) {
      final id = await _nextScopedId(
          IdGenerator.campaignPrefix, Collections.campaigns);
      toSave = campaign.copyWith(id: id, audit: _stampCreate());
    } else {
      toSave = campaign.copyWith(audit: _stampUpdate(campaign.audit));
    }
    await _backend.setDoc(Collections.campaigns, toSave.id, toSave.toMap());
    await _log(isNew ? AuditAction.create : AuditAction.update, 'Campaign',
        toSave.id, businessId: toSave.businessId, summary: toSave.name);
    return toSave;
  }

  Future<void> deleteCampaign(String id) async {
    _require(Permission.deleteCampaign);
    final doc = await _backend.fetchDoc(Collections.campaigns, id);
    if (doc == null) throw const NotFoundException();
    final campaign = Campaign.fromMap(doc);
    _requireBusinessAccess(campaign.businessId);
    await _backend.deleteDoc(Collections.campaigns, id);
    await _log(AuditAction.delete, 'Campaign', id,
        businessId: campaign.businessId, summary: campaign.name);
  }

  // ---- Orders ---------------------------------------------------------------

  Future<List<Order>> fetchOrders({String? businessId}) => _fetchScoped(
        Collections.orders,
        Order.fromMap,
        businessId: businessId,
      );

  Future<Order> saveOrder(Order order, {required bool isNew}) async {
    _require(isNew ? Permission.createOrder : Permission.editOrder);
    _requireBusinessAccess(order.businessId);
    var toSave = order;
    if (isNew) {
      final id = await _nextScopedId(
          IdGenerator.orderPrefix, Collections.orders,
          width: 6);
      toSave = order.copyWith(id: id, audit: _stampCreate());
    } else {
      toSave = order.copyWith(audit: _stampUpdate(order.audit));
    }
    await _backend.setDoc(Collections.orders, toSave.id, toSave.toMap());
    await _log(isNew ? AuditAction.create : AuditAction.update, 'Order',
        toSave.id, businessId: toSave.businessId, summary: toSave.productName);
    return toSave;
  }

  Future<void> deleteOrder(String id) async {
    _require(Permission.deleteOrder);
    final doc = await _backend.fetchDoc(Collections.orders, id);
    if (doc == null) throw const NotFoundException();
    final order = Order.fromMap(doc);
    _requireBusinessAccess(order.businessId);
    await _backend.deleteDoc(Collections.orders, id);
    await _log(AuditAction.delete, 'Order', id,
        businessId: order.businessId, summary: order.id);
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
          IdGenerator.expensePrefix, Collections.expenses);
      toSave = expense.copyWith(id: id, audit: _stampCreate());
    } else {
      toSave = expense.copyWith(audit: _stampUpdate(expense.audit));
    }
    await _backend.setDoc(Collections.expenses, toSave.id, toSave.toMap());
    await _log(isNew ? AuditAction.create : AuditAction.update, 'Expense',
        toSave.id, businessId: toSave.businessId, summary: toSave.name);
    return toSave;
  }

  Future<void> deleteExpense(String id) async {
    _require(Permission.deleteExpense);
    final doc = await _backend.fetchDoc(Collections.expenses, id);
    if (doc == null) throw const NotFoundException();
    final expense = Expense.fromMap(doc);
    _requireBusinessAccess(expense.businessId);
    if (expense.isFromDealer) {
      throw const AppException(
          'This expense is managed by its dealer. Edit or remove the dealer instead.');
    }
    await _backend.deleteDoc(Collections.expenses, id);
    await _log(AuditAction.delete, 'Expense', id,
        businessId: expense.businessId, summary: expense.name);
  }

  // ---- Dealers --------------------------------------------------------------

  Future<List<Dealer>> fetchDealers({String? businessId}) => _fetchScoped(
        Collections.dealers,
        Dealer.fromMap,
        businessId: businessId,
      );

  Future<Dealer> saveDealer(Dealer dealer, {required bool isNew}) async {
    _require(isNew ? Permission.createDealer : Permission.editDealer);
    _requireBusinessAccess(dealer.businessId);
    var toSave = dealer;
    if (isNew) {
      final id = await _nextScopedId(
          IdGenerator.dealerPrefix, Collections.dealers);
      toSave = dealer.copyWith(id: id, audit: _stampCreate());
    } else {
      toSave = dealer.copyWith(audit: _stampUpdate(dealer.audit));
    }
    await _backend.setDoc(Collections.dealers, toSave.id, toSave.toMap());
    // Mirror dealer cost into a linked business expense.
    await _mirrorDealerExpense(toSave);
    await _log(isNew ? AuditAction.create : AuditAction.update, 'Dealer',
        toSave.id, businessId: toSave.businessId, summary: toSave.name);
    return toSave;
  }

  /// Keeps a Business Expense (category = Dealer) in sync with the dealer's cost
  /// so dealer spend automatically flows into operating expenses.
  Future<void> _mirrorDealerExpense(Dealer dealer) async {
    final expenseId = 'EXP-DLR-${dealer.id}';
    final expense = Expense(
      id: expenseId,
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
    await _backend.setDoc(Collections.expenses, expenseId, expense.toMap());
  }

  Future<void> deleteDealer(String id) async {
    _require(Permission.deleteDealer);
    final doc = await _backend.fetchDoc(Collections.dealers, id);
    if (doc == null) throw const NotFoundException();
    final dealer = Dealer.fromMap(doc);
    _requireBusinessAccess(dealer.businessId);
    await _backend.deleteDoc(Collections.dealers, id);
    // Remove the mirrored expense too.
    await _backend.deleteDoc(Collections.expenses, 'EXP-DLR-$id');
    await _log(AuditAction.delete, 'Dealer', id,
        businessId: dealer.businessId, summary: dealer.name);
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
          user.assignedBusinessIds.map(_fetchCustomerDocsForBusiness));
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
          String businessId) =>
      _backend.fetchWhereArrayContains(
          Collections.customers, 'businessIds', businessId);

  Future<Customer> saveCustomer(Customer customer,
      {required bool isNew}) async {
    _require(isNew ? Permission.createCustomer : Permission.editCustomer);
    final user = _currentUser;
    final isOwner = user?.isOwner ?? false;

    var toSave = customer;
    if (isNew) {
      // A new customer must be tagged to at least one business, and a non-owner
      // may only tag businesses assigned to them.
      if (customer.businessIds.isEmpty) {
        throw const PermissionDeniedException(
            'Select at least one business for this customer.');
      }
      if (!isOwner &&
          customer.businessIds.any((id) => !(user?.canAccessBusiness(id) ?? false))) {
        throw const PermissionDeniedException(
            'You can only tag customers to businesses assigned to you.');
      }
      _requireAnyBusinessAccess(customer.businessIds);
      // A contract can only be recorded for a business the customer is tagged
      // to (and, since every tag is accessible for a non-owner above, only for
      // a business the caller can access).
      if (customer.contractsByBusiness.keys
          .any((id) => !customer.businessIds.contains(id))) {
        throw const PermissionDeniedException(
            'A service contract can only be recorded for a business the '
            'customer is tagged to.');
      }
      final id = await _nextScopedId(
          IdGenerator.customerPrefix, Collections.customers,
          arrayScoped: true);
      toSave = _withCustomerId(customer.copyWith(audit: _stampCreate()), id);
    } else {
      // Authorize the edit against the record's *current* tags, then merge back
      // any tags to businesses the caller cannot see so a non-owner never
      // silently drops (or leaks) a business outside their scope.
      final existingDoc =
          await _backend.fetchDoc(Collections.customers, customer.id);
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
        final visibleSubmitted = customer.businessIds
            .where((id) => user?.canAccessBusiness(id) ?? false);
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
            'A customer must remain tagged to at least one business.');
      }
      // A contract must be filed under a business the customer is tagged to.
      if (next.contractsByBusiness.keys
          .any((id) => !next.businessIds.contains(id))) {
        throw const PermissionDeniedException(
            'A service contract can only be recorded for a business the '
            'customer is tagged to.');
      }
      toSave = next.copyWith(audit: _stampUpdate(next.audit));
    }
    await _backend.setDoc(Collections.customers, toSave.id, toSave.toMap());
    await _log(isNew ? AuditAction.create : AuditAction.update, 'Customer',
        toSave.id,
        businessId: toSave.businessIds.isEmpty ? null : toSave.businessIds.first,
        summary: toSave.name);
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
        comments: c.comments,
        audit: c.audit,
      );

  Future<void> deleteCustomer(String id) async {
    _require(Permission.deleteCustomer);
    final doc = await _backend.fetchDoc(Collections.customers, id);
    if (doc == null) throw const NotFoundException();
    final customer = Customer.fromMap(doc);
    _requireAnyBusinessAccess(customer.businessIds);
    await _backend.deleteDoc(Collections.customers, id);
    await _log(AuditAction.delete, 'Customer', id,
        businessId:
            customer.businessIds.isEmpty ? null : customer.businessIds.first,
        summary: customer.name);
  }

  // ---- Users ----------------------------------------------------------------

  Future<List<AppUser>> fetchUsers() async {
    final docs = await _backend.fetchCollection(Collections.users);
    return docs.map(AppUser.fromMap).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
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

  /// Resolves a friendly login id (or email) to a profile, used at login.
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
          'Owner accounts cannot be created from this screen.');
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
            code: 'email-already-in-use');
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
    await _backend.setDoc(Collections.users, uid, user.toMap());
    await _log(AuditAction.create, 'User', uid, summary: name);
    return user;
  }

  Future<AppUser> saveUserProfile(AppUser user) async {
    _require(Permission.manageUsers);
    final updated = user.copyWith(audit: _stampUpdate(user.audit));
    await _backend.setDoc(Collections.users, user.uid, updated.toMap());
    await _log(AuditAction.update, 'User', user.uid, summary: user.name);
    return updated;
  }

  Future<void> setUserStatus(String uid, AccountStatus status) async {
    _require(Permission.manageUsers);
    final doc = await _backend.fetchDoc(Collections.users, uid);
    if (doc == null) throw const NotFoundException();
    final user = AppUser.fromMap(doc).copyWith(status: status);
    await saveUserProfile(user);
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
    await _backend.deleteDoc(Collections.users, uid);
    // Clear any lingering access request for the same identity.
    await _backend.deleteDoc(Collections.accessRequests, uid);
    await _log(AuditAction.delete, 'User', uid, summary: user.name);
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
          Collections.accessRequests, account.uid, request.toMap());
    } catch (_) {
      // Never surface a failure here — the sign-in has already been rejected
      // and the user is being signed out regardless.
    }
  }

  /// Lists pending access requests, newest first. Owner-only.
  Future<List<AccessRequest>> fetchAccessRequests() async {
    _require(Permission.manageUsers);
    final docs = await _backend.fetchCollection(Collections.accessRequests);
    return docs.map(AccessRequest.fromMap).toList()
      ..sort((a, b) => (b.requestedAt ?? DateTime(0))
          .compareTo(a.requestedAt ?? DateTime(0)));
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
          'This person already has a profile. Remove the request from the queue.');
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
    await _backend.setDoc(Collections.users, request.uid, user.toMap());
    await _backend.deleteDoc(Collections.accessRequests, request.uid);
    await _log(AuditAction.create, 'User', request.uid, summary: name);
    return user;
  }

  /// Dismisses a pending access request without granting access. Owner-only.
  Future<void> denyAccessRequest(String uid) async {
    _require(Permission.manageUsers);
    await _backend.deleteDoc(Collections.accessRequests, uid);
  }

  /// Updates the last-login timestamp for [uid]. Best-effort.
  Future<void> touchLastLogin(String uid) async {
    final doc = await _backend.fetchDoc(Collections.users, uid);
    if (doc == null) return;
    final user = AppUser.fromMap(doc).copyWith(lastLoginAt: _now);
    await _backend.setDoc(Collections.users, uid, user.toMap());
  }

  // ---- Audit logs -----------------------------------------------------------

  Future<List<AuditLog>> fetchAuditLogs({int limit = 100}) async {
    _require(Permission.manageSettings);
    final docs = await _backend.fetchCollection(Collections.auditLogs);
    final logs = docs.map(AuditLog.fromMap).toList()
      ..sort((a, b) => (b.timestamp ?? DateTime(0))
          .compareTo(a.timestamp ?? DateTime(0)));
    return logs.take(limit).toList();
  }
}
