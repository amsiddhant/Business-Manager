import 'package:flutter_test/flutter_test.dart';
import 'package:salesforce_business_manager/core/enums.dart';
import 'package:salesforce_business_manager/core/utils/date_utils.dart';
import 'package:salesforce_business_manager/core/utils/money.dart';
import 'package:salesforce_business_manager/models/campaign.dart';
import 'package:salesforce_business_manager/models/expense.dart';
import 'package:salesforce_business_manager/models/order.dart';
import 'package:salesforce_business_manager/models/product.dart';
import 'package:salesforce_business_manager/services/profit_calculation_service.dart';

const _service = ProfitCalculationService();

// The FY 2026-27 reporting window used by most tests.
final _fy = const FinancialYear(2026).range;

Order _order({
  String id = 'ORD-1',
  String productId = 'PROD-1',
  DateTime? date,
  int quantity = 1,
  int sellingMinor = 0,
  int buyingMinor = 0,
  int shippingMinor = 0,
  int otherMinor = 0,
  int discountMinor = 0,
  OrderStatus status = OrderStatus.delivered,
  int refundMinor = 0,
  DateTime? refundDate,
}) =>
    Order(
      id: id,
      businessId: 'BIZ-1',
      productId: productId,
      productName: 'Widget',
      orderDate: date ?? DateTime(2026, 6, 1),
      quantity: quantity,
      sellingCost: Money(sellingMinor),
      buyingCost: Money(buyingMinor),
      shippingRevenue: Money(shippingMinor),
      otherRevenue: Money(otherMinor),
      discount: Money(discountMinor),
      status: status,
      refundAmount: Money(refundMinor),
      refundDate: refundDate,
    );

Campaign _campaign({
  String id = 'CAM-1',
  String productId = 'PROD-1',
  DateTime? start,
  int investedMinor = 0,
  CampaignStatus status = CampaignStatus.active,
  CampaignPlatform platform = CampaignPlatform.meta,
}) =>
    Campaign(
      id: id,
      businessId: 'BIZ-1',
      productId: productId,
      name: 'Campaign',
      platform: platform,
      startDate: start ?? DateTime(2026, 6, 1),
      amountInvested: Money(investedMinor),
      status: status,
    );

Expense _expense({
  String id = 'EXP-1',
  int amountMinor = 0,
  RecurrenceFrequency frequency = RecurrenceFrequency.oneTime,
  ExpenseCategory category = ExpenseCategory.hosting,
  DateTime? start,
  DateTime? end,
  EntityStatus status = EntityStatus.active,
}) =>
    Expense(
      id: id,
      businessId: 'BIZ-1',
      name: 'Expense',
      category: category,
      amount: Money(amountMinor),
      frequency: frequency,
      startDate: start,
      endDate: end,
      status: status,
    );

Product _product(String id) =>
    Product(id: id, businessId: 'BIZ-1', name: 'Product $id');

void main() {
  group('Order-level financial getters', () {
    test('revenue = selling×qty + shipping + other − discount', () {
      final o = _order(
        quantity: 3,
        sellingMinor: 100000, // ₹1000
        shippingMinor: 5000, // ₹50
        otherMinor: 2000, // ₹20
        discountMinor: 10000, // ₹100
      );
      // 3*1000 + 50 + 20 - 100 = 2970
      expect(o.totalRevenue.minor, 297000);
      expect(o.productRevenue.minor, 300000);
    });

    test('product cost = buying×qty', () {
      final o = _order(quantity: 4, buyingMinor: 60000);
      expect(o.productCost.minor, 240000);
    });

    test('gross profit = revenue − product cost', () {
      final o = _order(quantity: 2, sellingMinor: 100000, buyingMinor: 60000);
      // rev 2000, cost 1200 -> 800
      expect(o.grossProfit.minor, 80000);
    });
  });

  group('Return / refund recognition', () {
    test('full return (no explicit refund) reverses revenue and cost', () {
      final o = _order(
        quantity: 2,
        sellingMinor: 100000, // rev 2000
        buyingMinor: 60000, // cost 1200
        status: OrderStatus.returned,
      );
      // Whole order refunded -> nothing recognised, gross profit ~zero.
      expect(o.effectiveRefund.minor, 200000);
      expect(o.recognisedRevenue, Money.zero);
      expect(o.recognisedProductCost, Money.zero);
      expect(o.recognisedGrossProfit, Money.zero);
    });

    test('partial refund nets revenue and reverses cost proportionally', () {
      final o = _order(
        quantity: 4,
        sellingMinor: 100000, // rev 4000
        buyingMinor: 50000, // cost 2000
        status: OrderStatus.returned,
        refundMinor: 100000, // ₹1000 refunded = 25% of ₹4000
      );
      expect(o.effectiveRefund.minor, 100000);
      // Net revenue = 4000 - 1000 = 3000
      expect(o.recognisedRevenue.minor, 300000);
      // Cost reversed by 25% -> 2000 * 0.75 = 1500
      expect(o.recognisedProductCost.minor, 150000);
      // Gross = 3000 - 1500 = 1500
      expect(o.recognisedGrossProfit.minor, 150000);
    });

    test('refund is capped at total revenue', () {
      final o = _order(
        quantity: 1,
        sellingMinor: 100000, // rev 1000
        status: OrderStatus.returned,
        refundMinor: 500000, // absurd over-refund
      );
      expect(o.effectiveRefund.minor, 100000);
      expect(o.recognisedRevenue, Money.zero);
    });

    test('refund on a non-returned order is ignored', () {
      final o = _order(
        quantity: 1,
        sellingMinor: 100000,
        buyingMinor: 40000,
        status: OrderStatus.delivered,
        refundMinor: 50000, // stale refund left from an earlier return
      );
      expect(o.effectiveRefund, Money.zero);
      expect(o.recognisedRevenue.minor, 100000);
      expect(o.recognisedProductCost.minor, 40000);
    });
  });

  group('recognisedOrdersIn', () {
    test('excludes cancelled but keeps returned (partially recognised)', () {
      final orders = [
        _order(id: 'a', status: OrderStatus.delivered),
        _order(id: 'b', status: OrderStatus.cancelled),
        _order(id: 'c', status: OrderStatus.returned),
        _order(id: 'd', status: OrderStatus.pending),
      ];
      final recognised = _service.recognisedOrdersIn(orders, _fy);
      // Returned orders stay in the set so partial refunds still contribute.
      expect(recognised.map((o) => o.id), containsAll(['a', 'c', 'd']));
      expect(recognised.map((o) => o.id), isNot(contains('b')));
      expect(recognised.length, 3);
    });

    test('excludes orders outside the range', () {
      final orders = [
        _order(id: 'in', date: DateTime(2026, 6, 1)),
        _order(id: 'out', date: DateTime(2025, 6, 1)),
      ];
      final recognised = _service.recognisedOrdersIn(orders, _fy);
      expect(recognised.single.id, 'in');
    });
  });

  group('summarise (top-level profit engine)', () {
    test('computes revenue, costs and derived profits', () {
      final orders = [
        _order(quantity: 5, sellingMinor: 100000, buyingMinor: 60000), // rev 5000, cost 3000
        _order(id: 'ORD-2', quantity: 2, sellingMinor: 50000, buyingMinor: 30000), // rev 1000, cost 600
        _order(id: 'ORD-X', status: OrderStatus.cancelled, sellingMinor: 999999),
      ];
      final campaigns = [_campaign(investedMinor: 85000)]; // ₹850 marketing
      final expenses = [
        _expense(amountMinor: 120000, frequency: RecurrenceFrequency.yearly), // ₹1200/yr
      ];

      final s = _service.summarise(
        orders: orders,
        campaigns: campaigns,
        expenses: expenses,
        range: _fy,
      );

      expect(s.revenue.minor, 600000); // 5000 + 1000
      expect(s.productCost.minor, 360000); // 3000 + 600
      expect(s.marketingCost.minor, 85000);
      expect(s.orderCount, 2);
      expect(s.unitsSold, 7);

      // Gross = 6000 - 3600 = 2400
      expect(s.grossProfit.minor, 240000);
      // Contribution = gross - marketing = 2400 - 850 = 1550
      expect(s.contributionProfit.minor, 155000);
      // Operating expenses ≈ full ₹1200 yearly prorated across the whole FY.
      expect(s.operatingExpenses.major, closeTo(1200, 5));
      // Net = 6000 - 3600 - 850 - ~1200 ≈ 350
      expect(s.netProfit.major, closeTo(350, 5));
    });

    test('partial refunds net down revenue and cost in the summary', () {
      final orders = [
        _order(quantity: 2, sellingMinor: 100000, buyingMinor: 60000), // rev 2000, cost 1200
        _order(
          id: 'ORD-R',
          quantity: 4,
          sellingMinor: 100000, // rev 4000
          buyingMinor: 50000, // cost 2000
          status: OrderStatus.returned,
          refundMinor: 100000, // 25% refunded -> net rev 3000, cost 1500
        ),
      ];
      final s = _service.summarise(
        orders: orders,
        campaigns: const [],
        expenses: const [],
        range: _fy,
      );
      // Revenue = 2000 + 3000 = 5000
      expect(s.revenue.minor, 500000);
      // Product cost = 1200 + 1500 = 2700
      expect(s.productCost.minor, 270000);
      // Gross = 5000 - 2700 = 2300
      expect(s.grossProfit.minor, 230000);
    });

    test('gross & net margin handle zero revenue safely', () {
      final s = _service.summarise(
        orders: const [],
        campaigns: const [],
        expenses: const [],
        range: _fy,
      );
      expect(s.grossMargin, 0);
      expect(s.netMargin, 0);
      expect(s.revenue, Money.zero);
    });

    test('margins computed as percentages', () {
      final orders = [
        _order(quantity: 1, sellingMinor: 100000, buyingMinor: 60000), // rev 1000, cost 600
      ];
      final s = _service.summarise(
        orders: orders,
        campaigns: const [],
        expenses: const [],
        range: _fy,
      );
      // Gross 400 / rev 1000 = 40%
      expect(s.grossMargin, closeTo(40, 0.001));
      // No marketing/opex -> net == gross here
      expect(s.netMargin, closeTo(40, 0.001));
    });
  });

  group('Recurring expense proration', () {
    test('yearly cost prorates to a single month (~1/12)', () {
      final expense = _expense(
        amountMinor: 1200000, // ₹12,000/yr
        frequency: RecurrenceFrequency.yearly,
      );
      final april = DateRange(DateTime(2026, 4, 1), DateTime(2026, 4, 30));
      final prorated = _service.proratedExpense(expense, april);
      // 12,000 * 30/365 ≈ 986
      expect(prorated.major, closeTo(12000 * 30 / 365, 1));
    });

    test('yearly cost over full FY ≈ full annual amount', () {
      final expense = _expense(
        amountMinor: 1200000,
        frequency: RecurrenceFrequency.yearly,
      );
      final prorated = _service.proratedExpense(expense, _fy);
      expect(prorated.major, closeTo(12000, 20));
    });

    test('monthly cost annualises before prorating', () {
      // ₹2000/month = ₹24,000/yr.
      final expense = _expense(
        amountMinor: 200000,
        frequency: RecurrenceFrequency.monthly,
      );
      expect(expense.annualisedAmount.minor, 2400000);
      final oneMonth = DateRange(DateTime(2026, 5, 1), DateTime(2026, 5, 31));
      // 24000 * 31/365 ≈ 2038
      expect(_service.proratedExpense(expense, oneMonth).major,
          closeTo(24000 * 31 / 365, 2));
    });

    test('one-time expense counts fully iff its date is in range', () {
      final inRange = _expense(
        amountMinor: 500000,
        frequency: RecurrenceFrequency.oneTime,
        start: DateTime(2026, 7, 1),
      );
      expect(_service.proratedExpense(inRange, _fy).minor, 500000);

      final outOfRange = _expense(
        amountMinor: 500000,
        frequency: RecurrenceFrequency.oneTime,
        start: DateTime(2025, 7, 1),
      );
      expect(_service.proratedExpense(outOfRange, _fy), Money.zero);
    });

    test('recurring cost is clipped to its active window', () {
      // Yearly ₹12,000 but only active from 1 Oct 2026.
      final expense = _expense(
        amountMinor: 1200000,
        frequency: RecurrenceFrequency.yearly,
        start: DateTime(2026, 10, 1),
      );
      // Active window within FY = 1 Oct 2026 → 31 Mar 2027 ≈ 182 days.
      final prorated = _service.proratedExpense(expense, _fy);
      expect(prorated.major, closeTo(12000 * 182 / 365, 60));
      // Definitely less than the full annual amount.
      expect(prorated.major, lessThan(12000));
    });

    test('inactive expenses contribute nothing', () {
      final expense = _expense(
        amountMinor: 1200000,
        frequency: RecurrenceFrequency.yearly,
        status: EntityStatus.inactive,
      );
      expect(_service.proratedExpense(expense, _fy), Money.zero);
    });
  });

  group('operatingExpensesIn', () {
    test('excludes advertising category by default (no double-count)', () {
      final expenses = [
        _expense(id: 'host', amountMinor: 100000, category: ExpenseCategory.hosting, frequency: RecurrenceFrequency.oneTime, start: DateTime(2026, 5, 1)),
        _expense(id: 'ads', amountMinor: 500000, category: ExpenseCategory.advertising, frequency: RecurrenceFrequency.oneTime, start: DateTime(2026, 5, 1)),
      ];
      final total = _service.operatingExpensesIn(expenses, _fy);
      expect(total.minor, 100000); // only hosting
    });
  });

  group('Campaign performance: ROI & ROAS', () {
    test('ROI% = (revenue − spend)/spend×100 and ROAS = revenue/spend', () {
      final orders = [
        _order(quantity: 1, sellingMinor: 250000), // ₹2500 revenue for PROD-1
      ];
      final campaigns = [
        _campaign(investedMinor: 100000), // ₹1000 spend
      ];
      final perf = _service.campaignPerformance(
        campaigns: campaigns,
        orders: orders,
        range: _fy,
      ).single;

      expect(perf.spend.minor, 100000);
      expect(perf.attributedRevenue.minor, 250000);
      // ROAS = 2500/1000 = 2.5
      expect(perf.roas, closeTo(2.5, 0.001));
      // ROI = (2500-1000)/1000*100 = 150
      expect(perf.roi, closeTo(150, 0.001));
    });

    test('zero spend yields null ROI/ROAS (N/A)', () {
      final perf = _service.campaignPerformance(
        campaigns: [_campaign(investedMinor: 0)],
        orders: [_order(sellingMinor: 100000)],
        range: _fy,
      ).single;
      expect(perf.roi, isNull);
      expect(perf.roas, isNull);
    });

    test('shared product revenue is split across campaigns by spend share', () {
      final orders = [
        _order(quantity: 1, sellingMinor: 300000), // ₹3000 for PROD-1
      ];
      final campaigns = [
        _campaign(id: 'c1', investedMinor: 100000), // 1/3 of spend
        _campaign(id: 'c2', investedMinor: 200000), // 2/3 of spend
      ];
      final perf = _service.campaignPerformance(
        campaigns: campaigns,
        orders: orders,
        range: _fy,
      );
      final c1 = perf.firstWhere((p) => p.campaign.id == 'c1');
      final c2 = perf.firstWhere((p) => p.campaign.id == 'c2');
      // 3000 split 1:2 -> 1000 and 2000
      expect(c1.attributedRevenue.major, closeTo(1000, 1));
      expect(c2.attributedRevenue.major, closeTo(2000, 1));
    });
  });

  group('productProfitability', () {
    test('rolls up revenue, cost and marketing per product', () {
      final products = [_product('PROD-1'), _product('PROD-2')];
      final orders = [
        _order(id: 'o1', productId: 'PROD-1', quantity: 2, sellingMinor: 100000, buyingMinor: 60000),
        _order(id: 'o2', productId: 'PROD-2', quantity: 1, sellingMinor: 50000, buyingMinor: 20000),
      ];
      final campaigns = [
        _campaign(id: 'c1', productId: 'PROD-1', investedMinor: 40000),
      ];
      final result = _service.productProfitability(
        products: products,
        orders: orders,
        campaigns: campaigns,
        range: _fy,
      );
      final p1 = result.firstWhere((r) => r.product.id == 'PROD-1');
      final p2 = result.firstWhere((r) => r.product.id == 'PROD-2');

      expect(p1.revenue.minor, 200000);
      expect(p1.productCost.minor, 120000);
      expect(p1.marketingCost.minor, 40000);
      // net = 2000 - 1200 - 400 = 400
      expect(p1.netProfit.minor, 40000);
      // margin = 400/2000 = 20%
      expect(p1.margin, closeTo(20, 0.001));

      expect(p2.marketingCost, Money.zero);
      expect(p2.margin, closeTo((500 - 200) / 500 * 100, 0.001));
    });
  });

  group('marketingByPlatform', () {
    test('groups spend by platform, excluding cancelled', () {
      final campaigns = [
        _campaign(id: 'm1', platform: CampaignPlatform.meta, investedMinor: 100000),
        _campaign(id: 'm2', platform: CampaignPlatform.meta, investedMinor: 50000),
        _campaign(id: 'g1', platform: CampaignPlatform.google, investedMinor: 75000),
        _campaign(id: 'x1', platform: CampaignPlatform.meta, investedMinor: 999999, status: CampaignStatus.cancelled),
      ];
      final byPlatform = _service.marketingByPlatform(campaigns, _fy);
      expect(byPlatform[CampaignPlatform.meta]!.minor, 150000);
      expect(byPlatform[CampaignPlatform.google]!.minor, 75000);
    });
  });
}
