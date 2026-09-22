import '../core/enums.dart';
import '../core/permissions.dart';
import '../core/utils/money.dart';
import '../models/app_user.dart';
import '../models/audit_fields.dart';
import '../models/business.dart';
import '../models/campaign.dart';
import '../models/dealer.dart';
import '../models/expense.dart';
import '../models/order.dart';
import '../models/product.dart';
import 'backend.dart';

/// A fully-built demo dataset used to bootstrap the local backend so the
/// dashboard demonstrates realistic numbers on first run.
///
/// Deterministic (no randomness) so tests and the UI are reproducible. The
/// [now] parameter anchors relative dates.
class DemoSeed {
  DemoSeed(this.now);

  final DateTime now;

  /// Demo credentials surfaced on the login screen.
  static const ownerEmail = 'owner@demo.com';
  static const adminEmail = 'admin@demo.com';
  static const userEmail = 'staff@demo.com';
  static const password = 'demo1234';

  static const ownerLogin = 'owner';
  static const adminLogin = 'admin';
  static const userLogin = 'staff';

  late final DateTime _fyStart = _financialYearStart(now);

  DateTime _financialYearStart(DateTime d) =>
      d.month < 4 ? DateTime(d.year - 1, 4, 1) : DateTime(d.year, 4, 1);

  DateTime _monthsAfterFyStart(int months, {int day = 5}) {
    final total = _fyStart.month - 1 + months;
    final year = _fyStart.year + total ~/ 12;
    final month = total % 12 + 1;
    return DateTime(year, month, day);
  }

  AuditFields _audit(DateTime at, {String by = 'seed'}) =>
      AuditFields(createdAt: at, updatedAt: at, createdBy: by, updatedBy: by);

  // ---- Businesses -----------------------------------------------------------

  static const bizAId = 'BIZ-00001';
  static const bizBId = 'BIZ-00002';

  List<Business> businesses() => [
        Business(
          id: bizAId,
          name: 'Aurora Gadgets',
          description: 'Direct-to-consumer electronics & accessories store.',
          type: 'E-commerce',
          website: 'https://aurora-gadgets.example.com',
          currency: CurrencyCode.inr,
          country: 'India',
          status: EntityStatus.active,
          lifecycle: BusinessLifecycle.active,
          foundedBy: 'Olivia Owner',
          ownedBy: 'Olivia Owner',
          // ~4 years of trading, anchored well before the current FY.
          startDate: DateTime(_fyStart.year - 4, 6, 15),
          audit: _audit(_fyStart),
        ),
        Business(
          id: bizBId,
          name: 'Bloom Organics',
          description: 'Organic skincare and wellness brand.',
          type: 'Retail',
          website: 'https://bloom-organics.example.com',
          currency: CurrencyCode.inr,
          country: 'India',
          status: EntityStatus.active,
          lifecycle: BusinessLifecycle.active,
          foundedBy: 'Olivia Owner & Adam Admin',
          ownedBy: 'Olivia Owner',
          startDate: DateTime(_fyStart.year - 2, 1, 10),
          audit: _audit(_fyStart),
        ),
      ];

  // ---- Users ----------------------------------------------------------------

  List<AppUser> users() => [
        AppUser(
          uid: 'user-owner',
          loginId: ownerLogin,
          name: 'Olivia Owner',
          email: ownerEmail,
          role: UserRole.owner,
          assignedBusinessIds: const [bizAId, bizBId],
          lastLoginAt: now,
          audit: _audit(_fyStart),
        ),
        AppUser(
          uid: 'user-admin',
          loginId: adminLogin,
          name: 'Adam Admin',
          email: adminEmail,
          role: UserRole.admin,
          assignedBusinessIds: const [bizAId],
          lastLoginAt: now.subtract(const Duration(days: 2)),
          audit: _audit(_fyStart),
        ),
        AppUser(
          uid: 'user-staff',
          loginId: userLogin,
          name: 'Sam Staff',
          email: userEmail,
          role: UserRole.user,
          assignedBusinessIds: const [bizAId],
          grantedPermissions: const {Permission.viewReports},
          lastLoginAt: now.subtract(const Duration(days: 5)),
          audit: _audit(_fyStart),
        ),
      ];

  // ---- Products -------------------------------------------------------------

  List<Product> products() => [
        _product(bizAId, 'PROD-00001', 'Wireless Earbuds Pro', 'Audio',
            buy: 1200, sell: 2999, sku: 'AUR-WEP-01'),
        _product(bizAId, 'PROD-00002', 'Smart Fitness Band', 'Wearables',
            buy: 900, sell: 2199, sku: 'AUR-SFB-02'),
        _product(bizAId, 'PROD-00003', 'USB-C Fast Charger 65W', 'Accessories',
            buy: 450, sell: 1299, sku: 'AUR-UFC-03'),
        _product(bizAId, 'PROD-00004', 'Bluetooth Speaker Mini', 'Audio',
            buy: 700, sell: 1799, sku: 'AUR-BSM-04'),
        _product(bizBId, 'PROD-00005', 'Vitamin C Face Serum', 'Skincare',
            buy: 250, sell: 899, sku: 'BLM-VCS-01'),
        _product(bizBId, 'PROD-00006', 'Herbal Shampoo Bar', 'Haircare',
            buy: 90, sell: 349, sku: 'BLM-HSB-02'),
      ];

  Product _product(String biz, String id, String name, String category,
      {required num buy, required num sell, required String sku}) {
    return Product(
      id: id,
      businessId: biz,
      name: name,
      description: '$name — premium quality, best seller.',
      buyingPrice: Money.fromMajor(buy),
      sellingPrice: Money.fromMajor(sell),
      url: 'https://example.com/${sku.toLowerCase()}',
      sku: sku,
      category: category,
      status: EntityStatus.active,
      audit: _audit(_fyStart),
    );
  }

  // ---- Campaigns ------------------------------------------------------------

  List<Campaign> campaigns() => [
        _campaign(bizAId, 'CMP-00001', 'PROD-00001', 'Earbuds Launch — Meta',
            CampaignPlatform.meta, 45000, monthOffset: 0,
            impressions: 320000, clicks: 9600, conversions: 480,
            status: CampaignStatus.completed),
        _campaign(bizAId, 'CMP-00002', 'PROD-00001', 'Earbuds Retargeting — Google',
            CampaignPlatform.google, 28000, monthOffset: 1,
            impressions: 150000, clicks: 6000, conversions: 300,
            status: CampaignStatus.active),
        _campaign(bizAId, 'CMP-00003', 'PROD-00002', 'Fitness Band — TikTok',
            CampaignPlatform.tiktok, 32000, monthOffset: 2,
            impressions: 500000, clicks: 12000, conversions: 360,
            status: CampaignStatus.active),
        _campaign(bizAId, 'CMP-00004', 'PROD-00004', 'Speaker — YouTube',
            CampaignPlatform.youtube, 18000, monthOffset: 3,
            impressions: 210000, clicks: 4200, conversions: 168,
            status: CampaignStatus.paused),
        _campaign(bizBId, 'CMP-00005', 'PROD-00005', 'Serum Awareness — Meta',
            CampaignPlatform.meta, 26000, monthOffset: 1,
            impressions: 280000, clicks: 8400, conversions: 420,
            status: CampaignStatus.active),
        _campaign(bizBId, 'CMP-00006', 'PROD-00006', 'Shampoo — Google',
            CampaignPlatform.google, 12000, monthOffset: 4,
            impressions: 90000, clicks: 3600, conversions: 180,
            status: CampaignStatus.active),
      ];

  Campaign _campaign(String biz, String id, String productId, String name,
      CampaignPlatform platform, num invested,
      {required int monthOffset,
      required int impressions,
      required int clicks,
      required int conversions,
      required CampaignStatus status}) {
    final start = _monthsAfterFyStart(monthOffset, day: 1);
    return Campaign(
      id: id,
      businessId: biz,
      productId: productId,
      name: name,
      platform: platform,
      type: 'Conversion',
      startDate: start,
      endDate: DateTime(start.year, start.month + 1, 0),
      budget: Money.fromMajor(invested * 1.2),
      amountInvested: Money.fromMajor(invested),
      impressions: impressions,
      clicks: clicks,
      conversions: conversions,
      status: status,
      url: 'https://ads.example.com/$id',
      notes: '',
      audit: _audit(start),
    );
  }

  // ---- Orders ---------------------------------------------------------------

  /// Generates a realistic spread of orders across the financial year.
  List<Order> orders() {
    final products = this.products();
    final result = <Order>[];
    var seq = 1;

    // Deterministic per-product monthly quantities across the FY so charts
    // show a believable trend.
    final Map<String, List<int>> monthlyQtyByProduct = {
      'PROD-00001': [40, 55, 48, 62, 70, 58, 65, 72, 60, 55, 68, 74],
      'PROD-00002': [30, 34, 40, 38, 44, 50, 46, 52, 48, 42, 55, 60],
      'PROD-00003': [80, 76, 90, 88, 95, 100, 92, 98, 110, 105, 120, 115],
      'PROD-00004': [20, 24, 22, 28, 26, 30, 27, 33, 31, 29, 35, 38],
      'PROD-00005': [50, 58, 62, 66, 70, 68, 72, 78, 74, 80, 85, 90],
      'PROD-00006': [90, 95, 100, 110, 105, 120, 115, 125, 130, 128, 140, 150],
    };

    // Only include months up to the current month within the FY.
    final monthsElapsed = _monthsElapsedInFy();

    for (final product in products) {
      final quantities = monthlyQtyByProduct[product.id]!;
      for (var m = 0; m < 12 && m <= monthsElapsed; m++) {
        final qty = quantities[m];
        if (qty <= 0) continue;
        final orderDate = _monthsAfterFyStart(m, day: 12);
        // Split each month into two orders for a richer table.
        final firstQty = (qty * 0.6).round();
        final secondQty = qty - firstQty;
        result.add(_order(seq++, product, orderDate, firstQty,
            OrderStatus.delivered));
        if (secondQty > 0) {
          final status = m == monthsElapsed
              ? OrderStatus.processing
              : OrderStatus.delivered;
          result.add(_order(seq++, product,
              orderDate.add(const Duration(days: 8)), secondQty, status));
        }
      }
    }

    // A couple of cancelled/returned orders to exercise revenue exclusion.
    if (products.isNotEmpty && monthsElapsed >= 1) {
      result.add(_order(seq++, products.first,
          _monthsAfterFyStart(1, day: 20), 5, OrderStatus.cancelled));
      result.add(_order(seq++, products.first,
          _monthsAfterFyStart(1, day: 22), 3, OrderStatus.returned));
    }
    return result;
  }

  int _monthsElapsedInFy() {
    final months = (now.year - _fyStart.year) * 12 + (now.month - _fyStart.month);
    return months.clamp(0, 11);
  }

  Order _order(int seq, Product p, DateTime date, int qty, OrderStatus status) {
    // Small deterministic per-order discount / shipping for variety.
    final discount = Money.fromMajor((seq % 3) * 50);
    final shipping = Money.fromMajor(qty > 40 ? 0 : 49);
    return Order(
      id: 'ORD-${seq.toString().padLeft(6, '0')}',
      businessId: p.businessId,
      productId: p.id,
      productName: p.name,
      orderDate: date,
      quantity: qty,
      sellingCost: p.sellingPrice,
      discount: discount,
      shippingRevenue: shipping,
      otherRevenue: Money.zero,
      buyingCost: p.buyingPrice,
      marketingAllocation: Money.zero,
      status: status,
      customerReference: 'CUST-${(seq * 7 % 900 + 100)}',
      notes: '',
      audit: _audit(date),
    );
  }

  // ---- Dealers --------------------------------------------------------------

  List<Dealer> dealers() => [
        Dealer(
          id: 'DLR-00001',
          businessId: bizAId,
          name: 'Shenzhen Direct Supply',
          url: 'https://sds.example.com',
          description: 'Primary electronics component supplier.',
          cost: Money.fromMajor(10000),
          costFrequency: RecurrenceFrequency.monthly,
          startDate: _fyStart,
          status: EntityStatus.active,
          contactName: 'Li Wei',
          contactInfo: 'li.wei@sds.example.com',
          audit: _audit(_fyStart),
        ),
        Dealer(
          id: 'DLR-00002',
          businessId: bizBId,
          name: 'Green Valley Botanicals',
          url: 'https://gvb.example.com',
          description: 'Organic ingredient wholesaler.',
          cost: Money.fromMajor(8000),
          costFrequency: RecurrenceFrequency.monthly,
          startDate: _fyStart,
          status: EntityStatus.active,
          contactName: 'Meera Nair',
          contactInfo: '+91 98765 43210',
          audit: _audit(_fyStart),
        ),
      ];

  // ---- Expenses -------------------------------------------------------------

  List<Expense> expenses() {
    final result = <Expense>[
      _expense(bizAId, 'EXP-00001', 'Domain (aurora-gadgets.com)',
          ExpenseCategory.domain, 1200, RecurrenceFrequency.yearly),
      _expense(bizAId, 'EXP-00002', 'Cloud Hosting',
          ExpenseCategory.hosting, 3000, RecurrenceFrequency.monthly),
      _expense(bizAId, 'EXP-00003', 'CRM Subscription',
          ExpenseCategory.crm, 2000, RecurrenceFrequency.monthly),
      _expense(bizAId, 'EXP-00004', 'Payment Gateway Fees',
          ExpenseCategory.paymentGateway, 1500, RecurrenceFrequency.monthly),
      _expense(bizBId, 'EXP-00005', 'Domain (bloom-organics.com)',
          ExpenseCategory.domain, 1400, RecurrenceFrequency.yearly),
      _expense(bizBId, 'EXP-00006', 'Shopify Plan',
          ExpenseCategory.subscription, 2500, RecurrenceFrequency.monthly),
      _expense(bizBId, 'EXP-00007', 'Warehouse Rent',
          ExpenseCategory.office, 15000, RecurrenceFrequency.monthly),
    ];

    // Dealer-sourced expenses (mirrors dealer costs into expenses).
    for (final dealer in dealers()) {
      result.add(Expense(
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
        audit: _audit(_fyStart),
      ));
    }
    return result;
  }

  Expense _expense(String biz, String id, String name, ExpenseCategory cat,
      num amount, RecurrenceFrequency freq) {
    return Expense(
      id: id,
      businessId: biz,
      name: name,
      category: cat,
      description: '',
      amount: Money.fromMajor(amount),
      frequency: freq,
      startDate: _fyStart,
      vendor: '',
      status: EntityStatus.active,
      audit: _audit(_fyStart),
    );
  }

  /// Builds the complete backend document map: collection -> (id -> data).
  Map<String, Map<String, Map<String, dynamic>>> buildStore() {
    final store = <String, Map<String, Map<String, dynamic>>>{};

    void put<T>(String collection, List<T> items,
        String Function(T) idOf, Map<String, dynamic> Function(T) toMap) {
      final coll = <String, Map<String, dynamic>>{};
      for (final item in items) {
        coll[idOf(item)] = toMap(item);
      }
      store[collection] = coll;
    }

    put(Collections.businesses, businesses(), (b) => b.id, (b) => b.toMap());
    put(Collections.users, users(), (u) => u.uid, (u) => u.toMap());
    put(Collections.products, products(), (p) => p.id, (p) => p.toMap());
    put(Collections.campaigns, campaigns(), (c) => c.id, (c) => c.toMap());
    put(Collections.orders, orders(), (o) => o.id, (o) => o.toMap());
    put(Collections.dealers, dealers(), (d) => d.id, (d) => d.toMap());
    put(Collections.expenses, expenses(), (e) => e.id, (e) => e.toMap());
    store[Collections.auditLogs] = {};
    return store;
  }
}
