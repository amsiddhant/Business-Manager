import 'package:flutter_test/flutter_test.dart';
import 'package:salesforce_business_manager/core/enums.dart';
import 'package:salesforce_business_manager/core/utils/date_utils.dart';
import 'package:salesforce_business_manager/models/goal.dart';

void main() {
  tearDown(() => FinancialYear.configureStartMonth(4));

  group('GoalPeriod keys', () {
    test('month, quarter and FY keys', () {
      expect(GoalPeriod.month(2026, 4).key, '2026-04');
      expect(GoalPeriod.month(2027, 1).key, '2027-01');
      expect(GoalPeriod.quarter(2026, 1).key, 'FY2026Q1');
      expect(GoalPeriod.financialYear(2026).key, 'FY2026');
    });

    test('parse round-trips every kind', () {
      for (final p in [
        GoalPeriod.month(2026, 12),
        GoalPeriod.quarter(2026, 3),
        GoalPeriod.financialYear(2027),
      ]) {
        expect(GoalPeriod.parse(p.key), p);
        expect(GoalPeriod.parse(p.key)!.key, p.key);
      }
    });

    test('parse rejects things that are not keys', () {
      for (final bad in ['', 'nope', '2026-13', '2026-00', 'FY2026Q5', 'FY26']) {
        expect(GoalPeriod.parse(bad), isNull, reason: bad);
      }
    });

    test('quarters past Q4 or before Q1 roll into the neighbouring FY', () {
      expect(GoalPeriod.quarter(2026, 5), GoalPeriod.quarter(2027, 1));
      expect(GoalPeriod.quarter(2026, 0), GoalPeriod.quarter(2025, 4));
      expect(GoalPeriod.quarter(2026, 4).next, GoalPeriod.quarter(2027, 1));
      expect(GoalPeriod.quarter(2026, 1).previous, GoalPeriod.quarter(2025, 4));
    });

    test('months roll over the year', () {
      expect(GoalPeriod.month(2026, 12).next, GoalPeriod.month(2027, 1));
      expect(GoalPeriod.month(2026, 1).previous, GoalPeriod.month(2025, 12));
    });

    test('yearEarlier keeps the type and index', () {
      expect(GoalPeriod.month(2026, 4).yearEarlier, GoalPeriod.month(2025, 4));
      expect(GoalPeriod.quarter(2026, 2).yearEarlier,
          GoalPeriod.quarter(2025, 2));
      expect(GoalPeriod.financialYear(2026).yearEarlier,
          GoalPeriod.financialYear(2025));
    });

    test('containing picks the period of a date', () {
      final jan = DateTime(2027, 1, 15);
      expect(GoalPeriod.containing(GoalPeriodType.month, jan),
          GoalPeriod.month(2027, 1));
      expect(GoalPeriod.containing(GoalPeriodType.quarter, jan),
          GoalPeriod.quarter(2026, 4));
      expect(GoalPeriod.containing(GoalPeriodType.financialYear, jan),
          GoalPeriod.financialYear(2026));
    });
  });

  group('GoalPeriod months', () {
    test('lengths', () {
      expect(GoalPeriod.month(2026, 4).months, hasLength(1));
      expect(GoalPeriod.quarter(2026, 1).months, hasLength(3));
      expect(GoalPeriod.financialYear(2026).months, hasLength(12));
    });

    test('an FY runs April to March in order', () {
      final months = GoalPeriod.financialYear(2026).months;
      expect(months.first, GoalPeriod.month(2026, 4));
      expect(months.last, GoalPeriod.month(2027, 3));
      expect(GoalPeriod.quarter(2026, 4).months, [
        GoalPeriod.month(2027, 1),
        GoalPeriod.month(2027, 2),
        GoalPeriod.month(2027, 3),
      ]);
    });
  });

  group('labels', () {
    test('default FY', () {
      expect(GoalPeriod.month(2026, 4).label, 'Apr 2026');
      expect(GoalPeriod.quarter(2026, 1).label, 'Q1 · FY 2026-27');
      expect(GoalPeriod.financialYear(2026).label, 'FY 2026-27');
    });

    test('a January FY is named for its single year', () {
      FinancialYear.configureStartMonth(1);
      expect(GoalPeriod.financialYear(2026).label, 'FY 2026');
      expect(GoalPeriod.quarter(2026, 2).label, 'Q2 · FY 2026');
    });
  });

  group('ranges', () {
    void expectRange(
        DateRange r, DateTime start, DateTime lastDay) {
      expect(r.start, start);
      expect(DateTime(r.end.year, r.end.month, r.end.day), lastDay);
    }

    test('month', () {
      expectRange(GoalPeriod.month(2028, 2).range, DateTime(2028, 2, 1),
          DateTime(2028, 2, 29));
    });

    for (final m in [1, 4, 7, 10]) {
      test('FY and quarters for an FY starting in month $m', () {
        FinancialYear.configureStartMonth(m);
        final fy = GoalPeriod.financialYear(2026).range;
        expectRange(fy, DateTime(2026, m, 1), DateTime(2026, m + 12, 0));

        final q1 = GoalPeriod.quarter(2026, 1).range;
        expectRange(q1, DateTime(2026, m, 1), DateTime(2026, m + 3, 0));
        final q4 = GoalPeriod.quarter(2026, 4).range;
        expectRange(q4, DateTime(2026, m + 9, 1), DateTime(2026, m + 12, 0));
      });
    }

    test('a goal keeps its dates when the FY start moves later', () {
      final q = GoalPeriod.quarter(2026, 1);
      FinancialYear.configureStartMonth(10);
      expect(q.range.start, DateTime(2026, 4, 1));
    });
  });

  group('Goal', () {
    test('idFor is deterministic', () {
      expect(
          Goal.idFor('BIZ-1', GoalPeriod.month(2026, 4), GoalMetric.revenue),
          'BIZ-1_2026-04_revenue');
      expect(
          Goal.idFor(Goal.allBusinesses, GoalPeriod.financialYear(2026),
              GoalMetric.netProfit),
          'ALL_FY2026_netProfit');
    });

    test('scope', () {
      final org = Goal(
          businessId: Goal.allBusinesses,
          period: GoalPeriod.month(2026, 4),
          metric: GoalMetric.orders,
          target: 10);
      expect(org.isOrgWide, isTrue);
      expect(org.scopeBusinessId, isNull);
      expect(org.copyWith(businessId: 'BIZ-1').scopeBusinessId, 'BIZ-1');
    });

    test('targetLabel formats money and counts', () {
      final money = Goal(
          businessId: 'B',
          period: GoalPeriod.month(2026, 4),
          metric: GoalMetric.revenue,
          target: 12500000);
      expect(money.targetLabel, '₹1,25,000');
      expect(money.copyWith(metric: GoalMetric.orders, target: 42).targetLabel,
          '42');
    });

    test('toMap / fromMap round trip', () {
      final goal = Goal(
        businessId: 'BIZ-1',
        period: GoalPeriod.quarter(2026, 3),
        metric: GoalMetric.netProfit,
        target: 987654300,
        currency: CurrencyCode.usd,
        note: 'Festive push',
      );
      final back = Goal.fromMap(goal.toMap())!;
      expect(back, goal);
      expect(back.period.key, 'FY2026Q3');
      expect(back.metric, GoalMetric.netProfit);
      expect(back.currency, CurrencyCode.usd);
      expect(back.note, 'Festive push');
    });

    test('fromMap keeps the FY start the goal was set under', () {
      FinancialYear.configureStartMonth(1);
      final goal = Goal(
          businessId: 'B',
          period: GoalPeriod.quarter(2026, 2),
          metric: GoalMetric.revenue,
          target: 100);
      FinancialYear.configureStartMonth(4);
      expect(Goal.fromMap(goal.toMap())!.period.range.start,
          DateTime(2026, 4, 1));
    });

    test('fromMap clamps targets into range', () {
      final base = Goal(
              businessId: 'B',
              period: GoalPeriod.month(2026, 4),
              metric: GoalMetric.revenue,
              target: 1)
          .toMap();
      expect(Goal.fromMap({...base, 'target': -5})!.target, 0);
      expect(Goal.fromMap({...base, 'target': 1e18})!.target, Goal.maxTarget);
    });

    test('invalid maps give null', () {
      final ok = Goal(
              businessId: 'B',
              period: GoalPeriod.month(2026, 4),
              metric: GoalMetric.revenue,
              target: 1)
          .toMap();
      expect(Goal.fromMap(ok), isNotNull);
      expect(Goal.fromMap({}), isNull);
      expect(Goal.fromMap({...ok, 'metric': 'karma'}), isNull);
      expect(Goal.fromMap({...ok, 'periodKey': 'soon'}), isNull);
      expect(Goal.fromMap({...ok, 'periodKey': null}), isNull);
      expect(Goal.fromMap({...ok, 'businessId': ''}), isNull);
      expect(Goal.fromMap({...ok, 'businessId': 3}), isNull);
      expect(Goal.fromMap({...ok, 'target': 'lots'}), isNull);
    });
  });
}
