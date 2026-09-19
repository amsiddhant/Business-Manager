import '../core/app_exception.dart';
import '../core/enums.dart';
import '../core/permissions.dart';
import '../core/utils/id_generator.dart';
import '../models/app_user.dart';
import '../models/audit_fields.dart';
import '../models/audit_log.dart';
import '../models/business.dart';
import '../models/campaign.dart';
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

  /// Filters a list of business-scoped documents down to those the current
  /// user may access.
  List<T> _visible<T>(List<T> items, String Function(T) businessOf) {
    final user = _currentUser;
    if (user == null) return const [];
    if (user.isOwner) return items;
    return items
        .where((item) => user.assignedBusinessIds.contains(businessOf(item)))
        .toList();
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
    final docs = await _backend.fetchCollection(Collections.businesses);
    final all = docs.map(Business.fromMap).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return _visible(all, (b) => b.id);
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
      toSave = business.copyWith(audit: _stampCreate());
      toSave = Business(
        id: id,
        name: toSave.name,
        description: toSave.description,
        type: toSave.type,
        website: toSave.website,
        currency: toSave.currency,
        country: toSave.country,
        status: toSave.status,
        audit: toSave.audit,
      );
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

  Future<List<T>> _fetchScoped<T>(
    String collection,
    T Function(Map<String, dynamic>) fromMap,
    String Function(T) businessOf, {
    String? businessId,
  }) async {
    if (businessId != null) _requireBusinessAccess(businessId);
    final docs =
        await _backend.fetchCollection(collection, businessId: businessId);
    final all = docs.map(fromMap).toList();
    return businessId != null ? all : _visible(all, businessOf);
  }

  // ---- Products -------------------------------------------------------------

  Future<List<Product>> fetchProducts({String? businessId}) => _fetchScoped(
        Collections.products,
        Product.fromMap,
        (p) => p.businessId,
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
      final existing = await _backend.fetchCollection(Collections.products);
      final id = IdGenerator.next(IdGenerator.productPrefix,
          existing.map((e) => e['id'] as String? ?? ''));
      toSave = Product(
        id: id,
        businessId: product.businessId,
        name: product.name,
        description: product.description,
        buyingPrice: product.buyingPrice,
        sellingPrice: product.sellingPrice,
        url: product.url,
        sku: product.sku,
        category: product.category,
        status: product.status,
        audit: _stampCreate(),
      );
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
        (c) => c.businessId,
        businessId: businessId,
      );

  Future<Campaign> saveCampaign(Campaign campaign, {required bool isNew}) async {
    _require(isNew ? Permission.createCampaign : Permission.editCampaign);
    _requireBusinessAccess(campaign.businessId);
    var toSave = campaign;
    if (isNew) {
      final existing = await _backend.fetchCollection(Collections.campaigns);
      final id = IdGenerator.next(IdGenerator.campaignPrefix,
          existing.map((e) => e['id'] as String? ?? ''));
      toSave = campaign.copyWith(audit: _stampCreate());
      toSave = _withCampaignId(toSave, id);
    } else {
      toSave = campaign.copyWith(audit: _stampUpdate(campaign.audit));
    }
    await _backend.setDoc(Collections.campaigns, toSave.id, toSave.toMap());
    await _log(isNew ? AuditAction.create : AuditAction.update, 'Campaign',
        toSave.id, businessId: toSave.businessId, summary: toSave.name);
    return toSave;
  }

  Campaign _withCampaignId(Campaign c, String id) => Campaign(
        id: id,
        businessId: c.businessId,
        productId: c.productId,
        name: c.name,
        platform: c.platform,
        type: c.type,
        startDate: c.startDate,
        endDate: c.endDate,
        budget: c.budget,
        amountInvested: c.amountInvested,
        impressions: c.impressions,
        clicks: c.clicks,
        conversions: c.conversions,
        status: c.status,
        url: c.url,
        notes: c.notes,
        audit: c.audit,
      );

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
        (o) => o.businessId,
        businessId: businessId,
      );

  Future<Order> saveOrder(Order order, {required bool isNew}) async {
    _require(isNew ? Permission.createOrder : Permission.editOrder);
    _requireBusinessAccess(order.businessId);
    var toSave = order;
    if (isNew) {
      final existing = await _backend.fetchCollection(Collections.orders);
      final id = IdGenerator.next(IdGenerator.orderPrefix,
          existing.map((e) => e['id'] as String? ?? ''),
          width: 6);
      toSave = order.copyWith(audit: _stampCreate());
      toSave = _withOrderId(toSave, id);
    } else {
      toSave = order.copyWith(audit: _stampUpdate(order.audit));
    }
    await _backend.setDoc(Collections.orders, toSave.id, toSave.toMap());
    await _log(isNew ? AuditAction.create : AuditAction.update, 'Order',
        toSave.id, businessId: toSave.businessId, summary: toSave.productName);
    return toSave;
  }

  Order _withOrderId(Order o, String id) => Order(
        id: id,
        businessId: o.businessId,
        productId: o.productId,
        productName: o.productName,
        orderDate: o.orderDate,
        quantity: o.quantity,
        sellingCost: o.sellingCost,
        discount: o.discount,
        shippingRevenue: o.shippingRevenue,
        otherRevenue: o.otherRevenue,
        buyingCost: o.buyingCost,
        marketingAllocation: o.marketingAllocation,
        status: o.status,
        customerReference: o.customerReference,
        notes: o.notes,
        audit: o.audit,
      );

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
        (e) => e.businessId,
        businessId: businessId,
      );

  Future<Expense> saveExpense(Expense expense, {required bool isNew}) async {
    _require(isNew ? Permission.createExpense : Permission.editExpense);
    _requireBusinessAccess(expense.businessId);
    var toSave = expense;
    if (isNew) {
      final existing = await _backend.fetchCollection(Collections.expenses);
      final id = IdGenerator.next(IdGenerator.expensePrefix,
          existing.map((e) => e['id'] as String? ?? ''));
      toSave = expense.copyWith(audit: _stampCreate());
      toSave = _withExpenseId(toSave, id);
    } else {
      toSave = expense.copyWith(audit: _stampUpdate(expense.audit));
    }
    await _backend.setDoc(Collections.expenses, toSave.id, toSave.toMap());
    await _log(isNew ? AuditAction.create : AuditAction.update, 'Expense',
        toSave.id, businessId: toSave.businessId, summary: toSave.name);
    return toSave;
  }

  Expense _withExpenseId(Expense e, String id) => Expense(
        id: id,
        businessId: e.businessId,
        name: e.name,
        category: e.category,
        description: e.description,
        amount: e.amount,
        frequency: e.frequency,
        startDate: e.startDate,
        endDate: e.endDate,
        vendor: e.vendor,
        status: e.status,
        notes: e.notes,
        sourceDealerId: e.sourceDealerId,
        audit: e.audit,
      );

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
        (d) => d.businessId,
        businessId: businessId,
      );

  Future<Dealer> saveDealer(Dealer dealer, {required bool isNew}) async {
    _require(isNew ? Permission.createDealer : Permission.editDealer);
    _requireBusinessAccess(dealer.businessId);
    var toSave = dealer;
    if (isNew) {
      final existing = await _backend.fetchCollection(Collections.dealers);
      final id = IdGenerator.next(IdGenerator.dealerPrefix,
          existing.map((e) => e['id'] as String? ?? ''));
      toSave = dealer.copyWith(audit: _stampCreate());
      toSave = _withDealerId(toSave, id);
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

  Dealer _withDealerId(Dealer d, String id) => Dealer(
        id: id,
        businessId: d.businessId,
        name: d.name,
        url: d.url,
        description: d.description,
        cost: d.cost,
        costFrequency: d.costFrequency,
        startDate: d.startDate,
        endDate: d.endDate,
        status: d.status,
        contactName: d.contactName,
        contactInfo: d.contactInfo,
        notes: d.notes,
        audit: d.audit,
      );

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
    final uid = await _backend.createAccount(email, password);
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
