import 'package:flutter_test/flutter_test.dart';
import 'package:salesforce_business_manager/core/utils/date_utils.dart';
import 'package:salesforce_business_manager/core/utils/money.dart';
import 'package:salesforce_business_manager/models/goal.dart';
import 'package:salesforce_business_manager/models/order.dart';
import 'package:salesforce_business_manager/services/profit_calculation_service.dart';

const _service = ProfitCalculationService();

/// June 2026 has 30 days: a ₹30,000 target is ₹1,000 a day.
final _june = GoalPeriod.month(2026, 6);
const _target = 3000000;

Goal _goal({
  String businessId = 'BIZ-1',
  GoalMetric metric = GoalMetric.revenue,
  int target = _target,
}) =>
    Goal(
        businessId: businessId,
        period: _june,
        metric: metric,
        target: target);

Order _order(String id, int day, int sellingMinor, {String business = 'BIZ-1'}) =>
    Order(
      id: id,
      businessId: business,
      productId: 'P',
      productName: 'Widget',
      orderDate: DateTime(2026, 6, day),
      quantity: 1,
      sellingCost: Money(sellingMinor),
      buyingCost: Money.zero,
    );

GoalProgress _progress(Goal goal, List<Order> orders, DateTime asOf,
        {double atRiskPercent = 90}) =>
    _service.goalProgress(
      goal: goal,
      orders: orders,
      campaigns: const [],
      expenses: const [],
      asOf: asOf,
      atRiskPercent: atRiskPercent,
    );

void main() {
  group('goalProgress', () {
    test('before the period starts: not started, nothing done', () {
      final p = _progress(_goal(), [_order('a', 1, 500000)], DateTime(2026, 5, 20));
      expect(p.status, GoalStatus.notStarted);
      expect(p.actual, 0);
      expect(p.elapsedDays, 0);
      expect(p.projected, isNull);
      expect(p.requiredPerDay, 100000);
    });

    test('on track: the run rate reaches the target', () {
      final p = _progress(
          _goal(), [_order('a', 5, 1000000)], DateTime(2026, 6, 10));
      expect(p.actual, 1000000);
      expect(p.elapsedDays, 10);
      expect(p.totalDays, 30);
      expect(p.expectedToDate, 1000000);
      expect(p.projected, 3000000);
      expect(p.status, GoalStatus.onTrack);
      expect(p.percent, closeTo(33.33, 0.01));
      expect(p.pace, 100);
      expect(p.projectedPercent, 100);
    });

    test('at risk: projected to land 90-99% of the target', () {
      final p = _progress(
          _goal(), [_order('a', 5, 920000)], DateTime(2026, 6, 10));
      expect(p.projectedPercent, closeTo(92, 0.01));
      expect(p.status, GoalStatus.atRisk);
      expect(p.status.isRunning, isTrue);
    });

    test('the at-risk line follows the setting', () {
      final orders = [_order('a', 5, 920000)];
      final asOf = DateTime(2026, 6, 10);
      expect(_progress(_goal(), orders, asOf, atRiskPercent: 95).status,
          GoalStatus.behind);
      expect(_progress(_goal(), orders, asOf, atRiskPercent: 80).status,
          GoalStatus.atRisk);
    });

    test('behind: projected well short', () {
      final p = _progress(
          _goal(), [_order('a', 5, 500000)], DateTime(2026, 6, 10));
      expect(p.status, GoalStatus.behind);
      expect(p.pace, 50);
    });

    test('achieved as soon as the target is reached, even mid-period', () {
      final p = _progress(
          _goal(), [_order('a', 5, 3000000)], DateTime(2026, 6, 12));
      expect(p.status, GoalStatus.achieved);
      expect(p.remaining, 0);
      expect(p.requiredPerDay, isNull);
      expect(p.percent, 100);
    });

    test('achieved stays achieved once the period is over', () {
      final p = _progress(
          _goal(), [_order('a', 5, 3500000)], DateTime(2026, 7, 8));
      expect(p.status, GoalStatus.achieved);
      expect(p.percent, closeTo(116.7, 0.1));
      expect(p.projected, isNull);
    });

    test('missed: the period is over and the target was not reached', () {
      final p = _progress(
          _goal(), [_order('a', 5, 2000000)], DateTime(2026, 7, 8));
      expect(p.status, GoalStatus.missed);
      expect(p.projected, isNull);
      expect(p.requiredPerDay, isNull);
      expect(p.remaining, 1000000);
      expect(p.elapsedDays, 30);
    });

    test('the first days are too early to judge', () {
      final p = _progress(_goal(), const [], DateTime(2026, 6, 2));
      expect(p.elapsedDays, 2);
      expect(p.status, GoalStatus.onTrack);
      // From the third day on, no sales is behind.
      expect(_progress(_goal(), const [], DateTime(2026, 6, 3)).status,
          GoalStatus.behind);
    });

    test('requiredPerDay spreads what is left over the days left', () {
      final p = _progress(
          _goal(), [_order('a', 5, 1000000)], DateTime(2026, 6, 10));
      // 2,000,000 left over 20 days.
      expect(p.requiredPerDay, 100000);
      final late = _progress(
          _goal(), [_order('a', 5, 1000000)], DateTime(2026, 6, 30));
      // The last day needs everything that is left.
      expect(late.requiredPerDay, 2000000);
    });

    test('a forecast can replace the run rate', () {
      final p = _service.goalProgress(
        goal: _goal(),
        orders: [_order('a', 5, 500000)],
        campaigns: const [],
        expenses: const [],
        asOf: DateTime(2026, 6, 10),
        projectedOverride: 3200000,
      );
      expect(p.projected, 3200000);
      expect(p.status, GoalStatus.onTrack);
    });

    test('counts: orders and units', () {
      final orders = [
        _order('a', 2, 1000),
        _order('b', 3, 1000),
        _order('c', 4, 1000),
      ];
      final p = _progress(
          _goal(metric: GoalMetric.orders, target: 12), orders, DateTime(2026, 6, 10));
      expect(p.actual, 3);
      expect(p.status, GoalStatus.behind);
    });

    test('organisation-wide goals use everyone\'s records, business goals '
        'only their own', () {
      final all = [
        _order('a', 3, 1000000, business: 'BIZ-1'),
        _order('b', 4, 2000000, business: 'BIZ-2'),
      ];
      final asOf = DateTime(2026, 6, 10);
      final org = _progress(_goal(businessId: Goal.allBusinesses), all, asOf);
      expect(org.actual, 3000000);
      expect(org.status, GoalStatus.achieved);

      final one = _progress(
          _goal(), [for (final o in all) if (o.businessId == 'BIZ-1') o], asOf);
      expect(one.actual, 1000000);
      expect(one.status, GoalStatus.onTrack);
    });

    test('orders outside the period do not count', () {
      final p = _progress(
        _goal(),
        [
          Order(
            id: 'old',
            businessId: 'BIZ-1',
            productId: 'P',
            productName: 'Widget',
            orderDate: DateTime(2026, 5, 31),
            quantity: 1,
            sellingCost: const Money(900000),
            buyingCost: Money.zero,
          ),
        ],
        DateTime(2026, 6, 10),
      );
      expect(p.actual, 0);
    });
  });

  group('metricByRange', () {
    test('one figure per range', () {
      final ranges = [
        DateRange(DateTime(2026, 5, 1), DateTime(2026, 5, 31)),
        DateRange(DateTime(2026, 6, 1), DateTime(2026, 6, 30)),
      ];
      final out = _service.metricByRange(
        metric: GoalMetric.revenue,
        orders: [_order('a', 3, 700000)],
        campaigns: const [],
        expenses: const [],
        ranges: ranges,
      );
      expect(out, [0, 700000]);
    });
  });

  group('seasonalSplit', () {
    int sum(List<int> l) => l.fold(0, (a, b) => a + b);

    test('evenly (zero weights) adds up exactly', () {
      final parts = _service.seasonalSplit(1000, List.filled(12, 0.0));
      expect(parts, hasLength(12));
      expect(sum(parts), 1000);
      expect(parts.reduce((a, b) => a > b ? a : b) -
          parts.reduce((a, b) => a < b ? a : b), lessThanOrEqualTo(1));
    });

    test('an exact even split has equal parts', () {
      expect(_service.seasonalSplit(1200, List.filled(12, 0.0)),
          List.filled(12, 100));
    });

    test('weighted follows the weights and adds up exactly', () {
      final parts = _service.seasonalSplit(1001, [1, 2, 3, 4]);
      expect(sum(parts), 1001);
      expect(parts[3], greaterThan(parts[2]));
      expect(parts[2], greaterThan(parts[1]));
      expect(parts[1], greaterThan(parts[0]));
      expect(_service.seasonalSplit(100, [1, 1, 2]), [25, 25, 50]);
    });

    test('lopsided weights still add up', () {
      for (final target in [0, 1, 7, 999999937]) {
        final parts = _service.seasonalSplit(target, [0.1, 33.3, 0, 7.77, 1e-9]);
        expect(sum(parts), target, reason: 'target $target');
        expect(parts.every((p) => p >= 0), isTrue);
        expect(parts[2], 0);
      }
    });

    test('unusable weights split evenly', () {
      final parts =
          _service.seasonalSplit(10, [double.nan, -3, double.infinity]);
      expect(sum(parts), 10);
      expect(parts, [4, 3, 3]);
    });

    test('no weights gives nothing', () {
      expect(_service.seasonalSplit(500, const []), isEmpty);
    });
  });
}
