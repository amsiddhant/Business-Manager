import 'package:flutter/foundation.dart';

import '../core/app_exception.dart';
import '../data/repository.dart';
import '../models/business.dart';
import '../models/campaign.dart';
import '../models/customer.dart';
import '../models/dealer.dart';
import '../models/expense.dart';
import '../models/order.dart';
import '../models/product.dart';

/// Loads and caches the full working set of entities the signed-in user can
/// access. Screens read from here and call [refresh] after mutations.
///
/// Filtering by business/period for display is applied by consumers using the
/// [FilterController]; this controller loads the union of accessible data once
/// and shares it, avoiding repeated round-trips per screen.
class DataController extends ChangeNotifier {
  DataController(this._repository);

  Repository _repository;

  /// Called when the underlying repository/backend changes (e.g. Firebase
  /// activation) so subsequent loads target the new backend.
  void rebind(Repository repository) {
    _repository = repository;
  }

  bool _loading = false;
  bool get loading => _loading;

  bool _loaded = false;
  bool get loaded => _loaded;

  String? _error;
  String? get error => _error;

  List<Business> businesses = [];
  List<Product> products = [];
  List<Campaign> campaigns = [];
  List<Order> orders = [];
  List<Expense> expenses = [];
  List<Dealer> dealers = [];
  List<Customer> customers = [];

  /// Non-fatal, per-collection load failures (e.g. one collection is denied by
  /// the security rules while the rest load cleanly). Surfaced as a dismissible
  /// warning banner rather than a full-screen block. Cleared on every load.
  final List<String> warnings = [];

  bool get hasWarnings => warnings.isNotEmpty;

  /// Loads everything the current user can access.
  ///
  /// Only [businesses] — the scope root — is treated as essential: without it
  /// there is nothing to render, so its failure surfaces full-screen. Every
  /// other collection is loaded in isolation; a single collection failing (for
  /// example a Firestore permission-denied on one query) degrades to an empty
  /// list plus a warning instead of blanking the entire application.
  Future<void> load() async {
    _loading = true;
    _error = null;
    warnings.clear();
    notifyListeners();

    // Essential: without businesses there is no scope to render anything.
    try {
      businesses = await _repository.fetchBusinesses();
    } catch (e) {
      businesses = [];
      _error = ErrorMapper.friendly(e);
      _loaded = false;
      _loading = false;
      notifyListeners();
      return;
    }

    // Non-critical collections, each isolated. A failure clears stale data for
    // that collection and records a warning; it never blocks the whole app.
    Future<void> guard<T>(
      String label,
      Future<List<T>> Function() run,
      void Function(List<T>) assign,
    ) async {
      try {
        assign(await run());
      } catch (e) {
        assign(const []);
        warnings.add('$label: ${ErrorMapper.friendly(e)}');
        debugPrint('DataController.load: $label failed: $e');
      }
    }

    await Future.wait([
      guard('Products', _repository.fetchProducts, (v) => products = v),
      guard('Campaigns', _repository.fetchCampaigns, (v) => campaigns = v),
      guard('Orders', _repository.fetchOrders, (v) => orders = v),
      guard('Expenses', _repository.fetchExpenses, (v) => expenses = v),
      guard('Dealers', _repository.fetchDealers, (v) => dealers = v),
      guard('Customers', _repository.fetchCustomers, (v) => customers = v),
    ]);

    _loaded = true;
    _loading = false;
    notifyListeners();
  }

  /// Reloads from the backend (after create/update/delete).
  Future<void> refresh() => load();

  /// Clears cached data (e.g. on sign-out).
  void clear() {
    businesses = [];
    products = [];
    campaigns = [];
    orders = [];
    expenses = [];
    dealers = [];
    customers = [];
    warnings.clear();
    _loaded = false;
    _error = null;
    notifyListeners();
  }

  // ---- Scoped views ---------------------------------------------------------

  /// Businesses that are currently active/selectable (excludes archived).
  List<Business> get selectableBusinesses =>
      businesses.where((b) => b.status.name != 'archived').toList();

  Business? businessById(String id) {
    for (final b in businesses) {
      if (b.id == id) return b;
    }
    return null;
  }

  Product? productById(String id) {
    for (final p in products) {
      if (p.id == id) return p;
    }
    return null;
  }

  List<Product> productsFor(String? businessId) => businessId == null
      ? products
      : products.where((p) => p.businessId == businessId).toList();

  List<Campaign> campaignsFor(String? businessId) => businessId == null
      ? campaigns
      : campaigns.where((c) => c.businessId == businessId).toList();

  List<Order> ordersFor(String? businessId) => businessId == null
      ? orders
      : orders.where((o) => o.businessId == businessId).toList();

  List<Expense> expensesFor(String? businessId) => businessId == null
      ? expenses
      : expenses.where((e) => e.businessId == businessId).toList();

  List<Dealer> dealersFor(String? businessId) => businessId == null
      ? dealers
      : dealers.where((d) => d.businessId == businessId).toList();

  List<Customer> customersFor(String? businessId) => businessId == null
      ? customers
      : customers.where((c) => c.businessIds.contains(businessId)).toList();

  Customer? customerById(String id) {
    for (final c in customers) {
      if (c.id == id) return c;
    }
    return null;
  }

  Campaign? campaignById(String id) {
    for (final c in campaigns) {
      if (c.id == id) return c;
    }
    return null;
  }

  Order? orderById(String id) {
    for (final o in orders) {
      if (o.id == id) return o;
    }
    return null;
  }

  Expense? expenseById(String id) {
    for (final e in expenses) {
      if (e.id == id) return e;
    }
    return null;
  }

  Dealer? dealerById(String id) {
    for (final d in dealers) {
      if (d.id == id) return d;
    }
    return null;
  }

  List<Campaign> campaignsForProduct(String productId) =>
      campaigns.where((c) => c.productId == productId).toList();

  List<Order> ordersForProduct(String productId) =>
      orders.where((o) => o.productId == productId).toList();

  /// Orders that reference [customerId] via their `customerReference`.
  List<Order> ordersForCustomer(String customerId) =>
      orders.where((o) => o.customerReference == customerId).toList();

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
}
