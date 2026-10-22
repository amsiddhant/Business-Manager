import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/app_exception.dart';
import '../core/utils/id_generator.dart';
import '../data/backend.dart';
import '../data/backend_capabilities.dart';
import '../data/repo_change.dart';
import '../data/repository.dart';
import '../models/business.dart';
import '../models/campaign.dart';
import '../models/customer.dart';
import '../models/dealer.dart';
import '../models/expense.dart';
import '../models/goal.dart';
import '../models/order.dart';
import '../models/product.dart';
import 'memo.dart';

/// Loads and caches the full working set of entities the signed-in user can
/// access. Screens read from here.
///
/// After the first load, saves and deletes made through the [Repository]
/// update the lists in place (via `Repository.changes`), so a mutation costs
/// its own write and no re-read of every collection. [sync] re-reads
/// everything on demand ("Sync now"), and [softSyncIfStale] does so when the
/// tab comes back after a while, to pick up other people's changes.
///
/// Filtering by business/period for display is applied by consumers using the
/// [FilterController]; this controller loads the union of accessible data once
/// and shares it, avoiding repeated round-trips per screen.
class DataController extends ChangeNotifier {
  DataController(Repository repository) {
    bind(repository);
  }

  late Repository _repository;
  StreamSubscription<RepoChange>? _changesSub;
  bool _disposed = false;

  /// Points the controller at [repository] and follows its writes. Calling it
  /// again with the same repository does nothing.
  void bind(Repository repository) {
    if (_changesSub != null && identical(repository, _repository)) return;
    _changesSub?.cancel();
    _repository = repository;
    repository.idHint = highestIdNumber;
    _changesSub = repository.changes.listen(_apply);
  }

  /// Called when the underlying repository/backend changes (e.g. Firebase
  /// activation) so subsequent loads target the new backend.
  void rebind(Repository repository) => bind(repository);

  bool _loading = false;
  bool get loading => _loading;

  bool _loaded = false;
  bool get loaded => _loaded;

  String? _error;
  String? get error => _error;

  /// Changes on every load and every applied write. Use it to memoise values
  /// derived from the lists (see [StampedMemo]).
  int get version => _version;
  int _version = 0;

  /// When the working set was last read from the server (null before that).
  DateTime? get lastSyncedAt => _lastSyncedAt;
  DateTime? _lastSyncedAt;

  /// True while the lists shown are the on-device copy from the last visit and
  /// the server read hasn't finished yet.
  bool get showingCachedData => _showingCachedData;
  bool _showingCachedData = false;

  /// True while a read from the server is running. Kept apart from the
  /// controller itself so only the sync indicator rebuilds.
  final ValueNotifier<bool> syncing = ValueNotifier(false);

  List<Business> businesses = [];
  List<Product> products = [];
  List<Campaign> campaigns = [];
  List<Order> orders = [];
  List<Expense> expenses = [];
  List<Dealer> dealers = [];
  List<Customer> customers = [];

  /// Goals the user can see (the Owner's include the organisation-wide ones).
  List<Goal> goals = [];

  /// True when goals couldn't be read (typically: the rules for them haven't
  /// been deployed yet). Goals are optional, so this is not a [warnings] entry.
  bool goalsUnavailable = false;

  /// Non-fatal, per-collection load failures (e.g. one collection is denied by
  /// the security rules while the rest load cleanly). Surfaced as a dismissible
  /// warning banner rather than a full-screen block. Cleared on every load.
  final List<String> warnings = [];

  bool get hasWarnings => warnings.isNotEmpty;

  final StampedMemo _memo = StampedMemo();

  // Which backend + account the loaded lists belong to.
  (Backend, String?)? _loadedScope;

  Future<void>? _inflight;
  (Backend, String?)? _inflightScope;
  final List<RepoChange> _changesDuringLoad = [];
  String? _countersHealedFor;

  (Backend, String?) get _scope =>
      (_repository.backend, _repository.currentUser?.uid);

  /// Loads everything the current user can access.
  ///
  /// Only [businesses] — the scope root — is treated as essential: without it
  /// there is nothing to render, so its failure surfaces full-screen. Every
  /// other collection is loaded in isolation; a single collection failing (for
  /// example a Firestore permission-denied on one query) degrades to an empty
  /// list plus a warning instead of blanking the entire application.
  ///
  /// On the first load, a matching on-device copy (Firebase) is shown at once
  /// while the server read runs. Calls made while a load for the same account
  /// is running share it.
  Future<void> load() {
    final scope = _scope;
    final running = _inflight;
    if (running != null && _inflightScope == scope) return running;
    late final Future<void> next;
    next = () async {
      if (running != null) await running.catchError((_) {});
      await _run();
    }()
        .whenComplete(() {
      if (identical(_inflight, next)) {
        _inflight = null;
        _inflightScope = null;
      }
    });
    _inflight = next;
    _inflightScope = scope;
    return next;
  }

  /// Re-reads everything from the server ("Sync now"). The current lists stay
  /// on screen meanwhile.
  Future<void> sync() => load();

  /// Kept for existing callers (error retry); same as [sync].
  Future<void> refresh() => sync();

  /// Syncs when the last server read is older than [maxAge] (e.g. the tab
  /// comes back to the foreground after a while).
  Future<void> softSyncIfStale(
      {Duration maxAge = const Duration(minutes: 30)}) async {
    if (!_loaded || _inflight != null) return;
    final last = _lastSyncedAt;
    if (last != null && DateTime.now().difference(last) < maxAge) return;
    await sync();
  }

  Future<void> _run() async {
    final repo = _repository;
    final scope = _scope;
    final uid = scope.$2;
    if (_loaded && _loadedScope != scope) {
      // Another backend or account: never show the previous one's data.
      _assign(const _Fetched.empty());
      _loaded = false;
      _lastSyncedAt = null;
      _bump();
    }
    _changesDuringLoad.clear();
    if (!_loaded) {
      _loading = true;
      _error = null;
      warnings.clear();
      _notify();
    }
    syncing.value = true;

    try {
      // 1. Instant paint from the on-device copy, when it is this person's.
      final cache = switch (repo.backend) {
        final CacheCapable c => c,
        _ => null,
      };
      if (!_loaded && uid != null && cache != null && cache.cachedUid == uid) {
        try {
          final cached = await cache.fromCache(() => _fetchAll(repo));
          if (cached.error == null &&
              cached.warnings.isEmpty &&
              _scope == scope) {
            _assign(cached);
            _loaded = true;
            _loadedScope = scope;
            _loading = false;
            _showingCachedData = true;
            _bump();
            _notify();
          }
        } catch (_) {
          // Nothing usable cached; the server read below fills the screen.
        }
      }

      // 2. The server.
      final fresh = await _fetchAll(repo);
      if (_scope != scope) return; // signed out or switched meanwhile

      warnings.clear();
      if (fresh.error != null) {
        if (_loaded) {
          // Keep what is on screen (e.g. offline with cached data).
          warnings.add("Couldn't refresh from the server: ${fresh.error}");
        } else {
          _assign(const _Fetched.empty());
          _error = fresh.error;
        }
      } else {
        _assign(fresh);
        warnings.addAll(fresh.warnings);
        _error = null;
        _loaded = true;
        _loadedScope = scope;
        _showingCachedData = false;
        _lastSyncedAt = DateTime.now();
        if (cache != null && uid != null) unawaited(cache.setCachedUid(uid));
        // Writes that landed while the read was running may be missing from
        // it; re-applying them is harmless when they are already included.
        for (final change in _changesDuringLoad) {
          _applyToLists(change);
        }
        _healCountersOnce(uid);
      }
      _changesDuringLoad.clear();
      _bump();
    } finally {
      _loading = false;
      syncing.value = false;
      _notify();
    }
  }

  Future<_Fetched> _fetchAll(Repository repo) async {
    // Essential: without businesses there is no scope to render anything.
    final List<Business> businesses;
    try {
      businesses = await repo.fetchBusinesses();
    } catch (e) {
      return _Fetched.failed(ErrorMapper.friendly(e));
    }

    // Non-critical collections, each isolated. A failure clears stale data for
    // that collection and records a warning; it never blocks the whole app.
    final warnings = <String>[];
    Future<List<T>> guard<T>(String label, Future<List<T>> Function() run) async {
      try {
        return await run();
      } catch (e) {
        warnings.add('$label: ${ErrorMapper.friendly(e)}');
        debugPrint('DataController.load: $label failed: $e');
        return <T>[];
      }
    }

    // Started together so they run in parallel.
    final products = guard('Products', repo.fetchProducts);
    final campaigns = guard('Campaigns', repo.fetchCampaigns);
    final orders = guard('Orders', repo.fetchOrders);
    final expenses = guard('Expenses', repo.fetchExpenses);
    final dealers = guard('Dealers', repo.fetchDealers);
    final customers = guard('Customers', repo.fetchCustomers);
    // Optional: a failure hides goals rather than raising a warning.
    var goalsUnavailable = false;
    final goals = repo.fetchGoals().catchError((Object e) {
      goalsUnavailable = true;
      debugPrint('DataController.load: Goals unavailable: $e');
      return <Goal>[];
    });
    return _Fetched(
      businesses: businesses,
      products: await products,
      campaigns: await campaigns,
      orders: await orders,
      expenses: await expenses,
      dealers: await dealers,
      customers: await customers,
      goals: await goals,
      goalsUnavailable: goalsUnavailable,
      warnings: warnings,
    );
  }

  void _assign(_Fetched f) {
    businesses = [...f.businesses];
    products = [...f.products];
    campaigns = [...f.campaigns];
    orders = [...f.orders];
    expenses = [...f.expenses];
    dealers = [...f.dealers];
    customers = [...f.customers];
    goals = [...f.goals];
    goalsUnavailable = f.goalsUnavailable;
  }

  /// Clears cached data (e.g. on sign-out).
  void clear() {
    _assign(const _Fetched.empty());
    warnings.clear();
    _changesDuringLoad.clear();
    _loaded = false;
    _loadedScope = null;
    _error = null;
    _lastSyncedAt = null;
    _showingCachedData = false;
    _countersHealedFor = null;
    _bump();
    _notify();
  }

  void _bump() => _version++;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // ---- Applying writes ------------------------------------------------------

  void _apply(RepoChange change) {
    if (_inflight != null) _changesDuringLoad.add(change);
    if (!_loaded) return;
    _applyToLists(change);
    _bump();
    _notifySoon();
  }

  void _applyToLists(RepoChange change) {
    final id = change.id;
    final entity = change is Upserted ? change.entity : null;
    switch (change.collection) {
      case Collections.businesses:
        businesses = _put(businesses, id, entity as Business?, (b) => b.id,
            visible: (b) => _canSee(b.id))
          ..sort((a, b) => a.name.compareTo(b.name));
      case Collections.products:
        products = _put(products, id, entity as Product?, (p) => p.id,
            visible: (p) => _canSee(p.businessId));
      case Collections.campaigns:
        campaigns = _put(campaigns, id, entity as Campaign?, (c) => c.id,
            visible: (c) => _canSee(c.businessId));
      case Collections.orders:
        orders = _put(orders, id, entity as Order?, (o) => o.id,
            visible: (o) => _canSee(o.businessId));
      case Collections.expenses:
        expenses = _put(expenses, id, entity as Expense?, (e) => e.id,
            visible: (e) => _canSee(e.businessId));
      case Collections.dealers:
        dealers = _put(dealers, id, entity as Dealer?, (d) => d.id,
            visible: (d) => _canSee(d.businessId));
      case Collections.customers:
        customers = _put(customers, id, entity as Customer?, (c) => c.id,
            visible: (c) => c.businessIds.any(_canSee));
      case Collections.goals:
        goals = _put(goals, id, entity as Goal?, (g) => g.id,
            visible: (g) => g.isOrgWide
                ? _repository.currentUser?.isOwner ?? false
                : _canSee(g.businessId));
    }
  }

  /// A copy of [list] with [id] replaced by [item] (in place), added at the
  /// end when new, or removed when [item] is null or no longer visible to the
  /// signed-in user. Copy-on-write, so a list a consumer already holds never
  /// changes under it.
  List<T> _put<T>(List<T> list, String id, T? item, String Function(T) idOf,
      {required bool Function(T) visible}) {
    final next = [...list];
    final i = next.indexWhere((e) => idOf(e) == id);
    final keep = item != null && visible(item);
    if (i >= 0) {
      if (keep) {
        next[i] = item;
      } else {
        next.removeAt(i);
      }
    } else if (keep) {
      next.add(item);
    }
    return next;
  }

  bool _canSee(String businessId) =>
      _repository.currentUser?.canAccessBusiness(businessId) ?? false;

  bool _notifyScheduled = false;

  /// Notifies once for a burst of writes (e.g. a CSV import).
  void _notifySoon() {
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    scheduleMicrotask(() {
      _notifyScheduled = false;
      _notify();
    });
  }

  // ---- Ids ------------------------------------------------------------------

  static const List<String> _idPrefixes = [
    IdGenerator.businessPrefix,
    IdGenerator.productPrefix,
    IdGenerator.campaignPrefix,
    IdGenerator.orderPrefix,
    IdGenerator.expensePrefix,
    IdGenerator.dealerPrefix,
    IdGenerator.customerPrefix,
  ];

  /// The highest number among loaded ids with [prefix] (`PROD-00042` → 42).
  /// The repository uses it as a floor when minting ids.
  int highestIdNumber(String prefix) => _memo.get(_version, (#maxId, prefix),
      () => IdGenerator.maxNumber(prefix, _idsFor(prefix)));

  Iterable<String> _idsFor(String prefix) => switch (prefix) {
        IdGenerator.businessPrefix => businesses.map((e) => e.id),
        IdGenerator.productPrefix => products.map((e) => e.id),
        IdGenerator.campaignPrefix => campaigns.map((e) => e.id),
        IdGenerator.orderPrefix => orders.map((e) => e.id),
        IdGenerator.expensePrefix => expenses.map((e) => e.id),
        IdGenerator.dealerPrefix => dealers.map((e) => e.id),
        IdGenerator.customerPrefix => customers.map((e) => e.id),
        _ => const <String>[],
      };

  /// After the Owner's first full load, raises any id counter that lags behind
  /// the ids already in use (e.g. minted by an older version of the app).
  void _healCountersOnce(String? uid) {
    final user = _repository.currentUser;
    if (uid == null || user == null || !user.isOwner) return;
    if (_countersHealedFor == uid) return;
    if (_repository.backend is! CounterCapable) return;
    _countersHealedFor = uid;
    unawaited(_repository.healIdCounters(
        {for (final prefix in _idPrefixes) prefix: highestIdNumber(prefix)}));
  }

  // ---- Scoped views ---------------------------------------------------------

  /// Businesses that are currently active/selectable (excludes archived).
  List<Business> get selectableBusinesses => _memo.get(_version, #selectable,
      () => businesses.where((b) => b.status.name != 'archived').toList());

  Map<String, T> _index<T>(Symbol name, List<T> list, String Function(T) idOf) =>
      _memo.get(_version, name, () => {for (final e in list) idOf(e): e});

  Business? businessById(String id) =>
      _index(#businesses, businesses, (b) => b.id)[id];

  Product? productById(String id) =>
      _index(#products, products, (p) => p.id)[id];

  List<Product> productsFor(String? businessId) => businessId == null
      ? products
      : _memo.get(_version, (#products, businessId),
          () => products.where((p) => p.businessId == businessId).toList());

  List<Campaign> campaignsFor(String? businessId) => businessId == null
      ? campaigns
      : _memo.get(_version, (#campaigns, businessId),
          () => campaigns.where((c) => c.businessId == businessId).toList());

  List<Order> ordersFor(String? businessId) => businessId == null
      ? orders
      : _memo.get(_version, (#orders, businessId),
          () => orders.where((o) => o.businessId == businessId).toList());

  List<Expense> expensesFor(String? businessId) => businessId == null
      ? expenses
      : _memo.get(_version, (#expenses, businessId),
          () => expenses.where((e) => e.businessId == businessId).toList());

  List<Dealer> dealersFor(String? businessId) => businessId == null
      ? dealers
      : _memo.get(_version, (#dealers, businessId),
          () => dealers.where((d) => d.businessId == businessId).toList());

  /// Goals set for exactly [businessId] (null = the organisation-wide ones).
  List<Goal> goalsFor(String? businessId) {
    final scope = businessId ?? Goal.allBusinesses;
    return _memo.get(_version, (#goals, scope),
        () => goals.where((g) => g.businessId == scope).toList());
  }

  List<Customer> customersFor(String? businessId) => businessId == null
      ? customers
      : _memo.get(
          _version,
          (#customers, businessId),
          () => customers
              .where((c) => c.businessIds.contains(businessId))
              .toList());

  Customer? customerById(String id) =>
      _index(#customers, customers, (c) => c.id)[id];

  Campaign? campaignById(String id) =>
      _index(#campaigns, campaigns, (c) => c.id)[id];

  Order? orderById(String id) => _index(#orders, orders, (o) => o.id)[id];

  Expense? expenseById(String id) =>
      _index(#expenses, expenses, (e) => e.id)[id];

  Dealer? dealerById(String id) => _index(#dealers, dealers, (d) => d.id)[id];

  List<Campaign> campaignsForProduct(String productId) => _memo.get(
      _version,
      (#campaignsForProduct, productId),
      () => campaigns.where((c) => c.productId == productId).toList());

  List<Order> ordersForProduct(String productId) => _memo.get(
      _version,
      (#ordersForProduct, productId),
      () => orders.where((o) => o.productId == productId).toList());

  /// Orders that reference [customerId] via their `customerReference`.
  List<Order> ordersForCustomer(String customerId) => _memo.get(
      _version,
      (#ordersForCustomer, customerId),
      () => orders.where((o) => o.customerReference == customerId).toList());

  /// Dealers linked to a mirrored expense (expense id `EXP-DLR-<dealerId>`).
  Dealer? dealerForExpense(String expenseId) {
    if (!expenseId.startsWith('EXP-DLR-')) return null;
    return dealerById(expenseId.substring('EXP-DLR-'.length));
  }

  /// All meaningful activity dates across orders, campaigns and expenses,
  /// optionally scoped to a business. Powers the data-derived period selector
  /// so the FY/year filter reflects the real span of data, not a hardcoded set.
  Iterable<DateTime> activityDates({String? businessId}) sync* {
    for (final o in ordersFor(businessId)) {
      final d = o.orderDate ?? o.audit.createdAt;
      if (d != null) yield d;
      if (o.refundDate != null) yield o.refundDate!;
    }
    for (final c in campaignsFor(businessId)) {
      final start = c.startDate ?? c.audit.createdAt;
      if (start != null) yield start;
      if (c.endDate != null) yield c.endDate!;
    }
    for (final e in expensesFor(businessId)) {
      final start = e.startDate ?? e.audit.createdAt;
      if (start != null) yield start;
      if (e.endDate != null) yield e.endDate!;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _changesSub?.cancel();
    syncing.dispose();
    super.dispose();
  }
}

/// One read of the whole working set.
class _Fetched {
  const _Fetched({
    required this.businesses,
    required this.products,
    required this.campaigns,
    required this.orders,
    required this.expenses,
    required this.dealers,
    required this.customers,
    this.goals = const [],
    this.goalsUnavailable = false,
    this.warnings = const [],
  }) : error = null;

  const _Fetched.empty()
      : businesses = const [],
        products = const [],
        campaigns = const [],
        orders = const [],
        expenses = const [],
        dealers = const [],
        customers = const [],
        goals = const [],
        goalsUnavailable = false,
        warnings = const [],
        error = null;

  const _Fetched.failed(String this.error)
      : businesses = const [],
        products = const [],
        campaigns = const [],
        orders = const [],
        expenses = const [],
        dealers = const [],
        customers = const [],
        goals = const [],
        goalsUnavailable = false,
        warnings = const [];

  final List<Business> businesses;
  final List<Product> products;
  final List<Campaign> campaigns;
  final List<Order> orders;
  final List<Expense> expenses;
  final List<Dealer> dealers;
  final List<Customer> customers;
  final List<Goal> goals;
  final bool goalsUnavailable;
  final List<String> warnings;

  /// Set when the essential businesses read failed.
  final String? error;
}
