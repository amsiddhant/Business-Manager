import 'package:flutter/foundation.dart';

import '../core/app_exception.dart';
import '../data/repository.dart';
import '../models/business.dart';
import '../models/campaign.dart';
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

  /// Loads everything the current user can access.
  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        _repository.fetchBusinesses(),
        _repository.fetchProducts(),
        _repository.fetchCampaigns(),
        _repository.fetchOrders(),
        _repository.fetchExpenses(),
        _repository.fetchDealers(),
      ]);
      businesses = results[0] as List<Business>;
      products = results[1] as List<Product>;
      campaigns = results[2] as List<Campaign>;
      orders = results[3] as List<Order>;
      expenses = results[4] as List<Expense>;
      dealers = results[5] as List<Dealer>;
      _loaded = true;
    } catch (e) {
      _error = ErrorMapper.friendly(e);
    } finally {
      _loading = false;
      notifyListeners();
    }
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

  List<Campaign> campaignsForProduct(String productId) =>
      campaigns.where((c) => c.productId == productId).toList();

  List<Order> ordersForProduct(String productId) =>
      orders.where((o) => o.productId == productId).toList();
}
