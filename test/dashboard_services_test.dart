import 'package:flutter_test/flutter_test.dart';
import 'package:salesforce_business_manager/core/enums.dart';
import 'package:salesforce_business_manager/core/utils/date_utils.dart';
import 'package:salesforce_business_manager/core/utils/money.dart';
import 'package:salesforce_business_manager/models/order.dart';
import 'package:salesforce_business_manager/services/profit_calculation_service.dart';

const _service = ProfitCalculationService();

ProfitSummary _summary({
  int revenue = 0,
  int productCost = 0,
  int marketing = 0,
  int operating = 0,
  int orders = 0,
}) =>
    ProfitSummary(
      revenue: Money.fromMajor(revenue),
      productCost: Money.fromMajor(productCost),
      marketingCost: Money.fromMajor(marketing),
      operatingExpenses: Money.fromMajor(operating),
      orderCount: orders,
      unitsSold: orders,
    );

Order _order(String id, DateTime date, OrderStatus status) => Order(
      id: id,
      businessId: 'BIZ-1',
      productId: 'PROD-1',
      productName: 'Widget',
      orderDate: date,
      quantity: 1,
      sellingCost: Money.fromMajor(100),
      buyingCost: Money.zero,
      shippingRevenue: Money.zero,
      otherRevenue: Money.zero,
      discount: Money.zero,
      status: status,
      refundAmount: Money.zero,
    );

void main() {
  group('compare', () {
    final c = _service.compare(
      _summary(revenue: 1200, productCost: 600, orders: 12),
      _summary(revenue: 1000, productCost: 400, orders: 10),
    );

    test('amounts and counts change in %', () {
      expect(c[KpiMetric.revenue].change, closeTo(20, 1e-9));
      expect(c[KpiMetric.orders].change, closeTo(20, 1e-9));
    });

    test('a cost going up is bad news, revenue going up is good', () {
      expect(c[KpiMetric.revenue].favourable, isTrue);
      expect(c[KpiMetric.productCost].favourable, isFalse);
    });

    test('margins change in percentage points', () {
      // 50% net margin now, 60% before.
      expect(c[KpiMetric.netMargin].change, closeTo(-10, 1e-9));
    });

    test('no change and no basis when the comparison period is empty', () {
      final empty = _service.compare(_summary(revenue: 500), _summary());
      expect(empty.hasPrevious, isFalse);
      expect(empty[KpiMetric.revenue].change, isNull);
      expect(empty[KpiMetric.revenue].favourable, isNull);
    });

    test('a margin has no basis when the previous revenue was zero', () {
      final c = _service.compare(
          _summary(revenue: 500), _summary(operating: 100));
      expect(c[KpiMetric.netMargin].previous, isNull);
      expect(c[KpiMetric.operatingExpenses].previous, 100);
    });
  });

  test('profitWaterfall steps down from revenue to net profit', () {
    final steps = _service.profitWaterfall(_summary(
        revenue: 1000, productCost: 300, marketing: 200, operating: 100));
    expect([for (final s in steps) s.label],
        ['Revenue', 'Product Cost', 'Marketing', 'Operating', 'Net Profit']);
    expect(steps[1].start.major, 1000);
    expect(steps[1].end.major, 700);
    expect(steps[3].end.major, 400);
    expect(steps.last.kind, WaterfallKind.total);
    expect(steps.last.end.major, 400);
  });

  test('orderStatusBreakdown counts every status in the range only', () {
    final range = DateRange(DateTime(2026, 6, 1), DateTime(2026, 6, 30));
    final counts = _service.orderStatusBreakdown([
      _order('1', DateTime(2026, 6, 2), OrderStatus.delivered),
      _order('2', DateTime(2026, 6, 3), OrderStatus.delivered),
      _order('3', DateTime(2026, 6, 4), OrderStatus.cancelled),
      _order('4', DateTime(2026, 7, 1), OrderStatus.delivered),
    ], range);
    expect(counts.keys.toSet(), OrderStatus.values.toSet());
    expect(counts[OrderStatus.delivered], 2);
    expect(counts[OrderStatus.cancelled], 1);
  });

  group('projectRunRate', () {
    final january = DateRange(DateTime(2026, 1, 1), DateTime(2026, 1, 31));

    test('carries the daily rate to the end of the period', () {
      final p = _service.projectRunRate(
        toDate: _summary(revenue: 1000, operating: 500),
        range: january,
        asOf: DateTime(2026, 1, 10),
      )!;
      expect(p.elapsedDays, 10);
      expect(p.totalDays, 31);
      expect(p.revenue.major, closeTo(3100, 0.01));
      expect(p.netProfit.major, closeTo(1550, 0.01));
    });

    test('waits for a week of data', () {
      expect(
          _service.projectRunRate(
              toDate: _summary(revenue: 100),
              range: january,
              asOf: DateTime(2026, 1, 3)),
          isNull);
    });

    test('is null once the period is over', () {
      expect(
          _service.projectRunRate(
              toDate: _summary(revenue: 100),
              range: january,
              asOf: DateTime(2026, 2, 5)),
          isNull);
    });
  });
}
