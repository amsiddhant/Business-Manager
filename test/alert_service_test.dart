import 'package:flutter_test/flutter_test.dart';
import 'package:salesforce_business_manager/core/enums.dart';
import 'package:salesforce_business_manager/core/utils/money.dart';
import 'package:salesforce_business_manager/models/app_settings.dart';
import 'package:salesforce_business_manager/models/campaign.dart';
import 'package:salesforce_business_manager/models/goal.dart';
import 'package:salesforce_business_manager/models/order.dart';
import 'package:salesforce_business_manager/services/alert_service.dart';

const _service = AlertService();
final _today = DateTime(2026, 10, 22, 9);

Campaign _campaign(String id,
        {DateTime? start, DateTime? end, int invested = 0}) =>
    Campaign(
      id: id,
      businessId: 'BIZ-1',
      productId: 'PROD-1',
      name: 'Campaign $id',
      platform: CampaignPlatform.meta,
      startDate: start ?? DateTime(2026, 1, 1),
      endDate: end,
      amountInvested: Money.fromMajor(invested),
      status: CampaignStatus.active,
    );

Order _order(String id, int revenue, {String business = 'BIZ-1'}) => Order(
      id: id,
      businessId: business,
      productId: 'PROD-1',
      productName: 'Product',
      orderDate: DateTime(2026, 10, 5),
      sellingCost: Money.fromMajor(revenue),
    );

Goal _revenueGoal(int targetMajor,
        {String business = 'BIZ-1', GoalPeriod? period}) =>
    Goal(
      businessId: business,
      period: period ?? GoalPeriod.month(2026, 10),
      metric: GoalMetric.revenue,
      target: Money.fromMajor(targetMajor).minor,
    );

List<AppAlert> _build({
  List<Campaign> campaigns = const [],
  List<Order> orders = const [],
  List<String> warnings = const [],
  bool demoMode = false,
  AlertSettings settings = const AlertSettings(),
  List<Goal> goals = const [],
}) =>
    _service.build(
      customers: const [],
      campaigns: campaigns,
      orders: orders,
      expenses: const [],
      products: const [],
      warnings: warnings,
      demoMode: demoMode,
      now: _today,
      currencyOf: (_) => CurrencyCode.inr,
      settings: settings,
      goals: goals,
    );

List<AppAlert> _goalAlerts(List<AppAlert> alerts) =>
    [for (final a in alerts) if (a.type == AlertType.goalAtRisk) a];

void main() {
  group('robustZ', () {
    const history = <double>[90, 100, 110, 100, 95, 105];

    test('a value far above the median scores high', () {
      expect(AlertService.robustZ(1000, history), greaterThan(4));
    });

    test('a value at or under the median scores nothing', () {
      expect(AlertService.robustZ(100, history), isNull);
      expect(AlertService.robustZ(50, history), isNull);
    });

    test('needs three months with spend', () {
      expect(AlertService.robustZ(1000, const [0, 0, 100, 100]), isNull);
    });

    test('with no spread, more than double the median counts as far', () {
      expect(AlertService.robustZ(250, const [100, 100, 100]),
          double.infinity);
      expect(AlertService.robustZ(150, const [100, 100, 100]), isNull);
    });
  });

  test('stableHash is FNV-1a and the same on every run', () {
    expect(AlertService.stableHash(''), '811c9dc5');
    expect(AlertService.stableHash('a'), 'e40c292c');
    expect(AlertService.stableHash('Some warning'),
        AlertService.stableHash('Some warning'));
    expect(AlertService.stableHash('one'),
        isNot(AlertService.stableHash('two')));
  });

  test('warnings come first, demo mode last', () {
    final alerts = _build(warnings: ['Orders failed'], demoMode: true);
    expect([for (final a in alerts) a.type],
        [AlertType.dataWarning, AlertType.demoMode]);
    expect(alerts.first.severity, AlertSeverity.high);
    expect(alerts.last.severity, AlertSeverity.info);
    expect(alerts.last.key, 'demo-mode');
  });

  test('a campaign ending within a week raises an alert with a stable key',
      () {
    final campaigns = [
      _campaign('CAM-1', end: DateTime(2026, 10, 25)),
      _campaign('CAM-2', end: DateTime(2026, 11, 30)),
      _campaign('CAM-3', end: DateTime(2026, 10, 1)),
    ];
    final alerts = _build(campaigns: campaigns);
    expect(alerts, hasLength(1));
    expect(alerts.single.type, AlertType.campaignEnding);
    expect(alerts.single.key, 'campaign-ending:CAM-1:2026-10-25');
    expect([for (final a in _build(campaigns: campaigns)) a.key],
        [alerts.single.key]);
  });

  test('a marketing spike this month is flagged as unusual spend', () {
    final campaigns = [
      for (final (m, v) in [(4, 90), (5, 100), (6, 110), (7, 100), (8, 95),
        (9, 105)])
        _campaign('CAM-$m', start: DateTime(2026, m, 10), invested: v),
      _campaign('CAM-10', start: DateTime(2026, 10, 5), invested: 1000),
    ];
    final spend = _build(campaigns: campaigns)
        .where((a) => a.type == AlertType.unusualSpend)
        .toList();
    expect(spend, hasLength(1));
    expect(spend.single.key, 'unusual-spend:BIZ-1:Marketing:2026-10');
    expect(spend.single.severity, AlertSeverity.high);
  });

  group('organisation alert settings', () {
    test('switched-off types are not raised', () {
      const off = AlertSettings(disabledTypes: {'dataWarning', 'demoMode'});
      expect(_build(warnings: ['Orders failed'], demoMode: true, settings: off),
          isEmpty);
      final noEnding = _build(
        campaigns: [_campaign('CAM-1', end: DateTime(2026, 10, 25))],
        settings: const AlertSettings(disabledTypes: {'campaignEnding'}),
      );
      expect(noEnding, isEmpty);
    });

    test('the campaign-ending window follows the setting', () {
      final campaigns = [_campaign('CAM-1', end: DateTime(2026, 11, 15))];
      expect(_build(campaigns: campaigns), isEmpty);
      final wide = _build(
          campaigns: campaigns,
          settings: const AlertSettings(campaignEndingDays: 30));
      expect([for (final a in wide) a.type], [AlertType.campaignEnding]);
    });
  });

  group('goal at risk', () {
    // 22 of October's 31 days have passed on _today.
    test('a goal projected far under target is behind (high)', () {
      final alerts = _goalAlerts(_build(
        orders: [_order('ORD-1', 100)],
        goals: [_revenueGoal(1000)],
      ));
      expect(alerts, hasLength(1));
      final a = alerts.single;
      expect(a.severity, AlertSeverity.high);
      expect(a.key, 'goal-at-risk:BIZ-1_2026-10_revenue:behind');
      expect(a.title, 'Revenue goal is behind · Oct 2026');
      expect(a.message, contains('a day from here'));
      expect(a.route, '/goals');
      expect([a.due!.year, a.due!.month, a.due!.day], [2026, 10, 31]);
    });

    test('a goal projected just under target is at risk (medium)', () {
      // ₹680 so far → about ₹958 by month end, 96% of ₹1,000.
      final alerts = _goalAlerts(_build(
        orders: [_order('ORD-1', 680)],
        goals: [_revenueGoal(1000)],
      ));
      expect(alerts.single.severity, AlertSeverity.medium);
      expect(alerts.single.key, 'goal-at-risk:BIZ-1_2026-10_revenue:atRisk');
    });

    test('the at-risk line follows the setting', () {
      final alerts = _goalAlerts(_build(
        orders: [_order('ORD-1', 680)],
        goals: [_revenueGoal(1000)],
        settings: const AlertSettings(goalAtRiskPercent: 97),
      ));
      expect(alerts.single.key, endsWith(':behind'));
    });

    test('on-track, finished and future goals raise nothing', () {
      final alerts = _goalAlerts(_build(
        orders: [_order('ORD-1', 800)],
        goals: [
          _revenueGoal(1000),
          _revenueGoal(1000, period: GoalPeriod.month(2026, 9)),
          _revenueGoal(1000, period: GoalPeriod.month(2026, 12)),
        ],
      ));
      expect(alerts, isEmpty);
    });

    test("a business goal only counts that business's orders", () {
      final orders = [_order('ORD-1', 900), _order('ORD-2', 900, business: 'BIZ-2')];
      expect(
          _goalAlerts(_build(orders: orders, goals: [_revenueGoal(1200)])),
          isEmpty);
      final allBusinesses = _goalAlerts(_build(
          orders: orders,
          goals: [_revenueGoal(3000, business: Goal.allBusinesses)]));
      // ₹1,800 so far → about ₹2,536, under 90% of ₹3,000.
      expect(allBusinesses.single.key, 'goal-at-risk:ALL_2026-10_revenue:behind');
      expect(
          _goalAlerts(_build(
              orders: [_order('ORD-1', 900)],
              goals: [_revenueGoal(1200, business: 'BIZ-2')])).single.key,
          endsWith(':behind'));
    });

    test('switching the type off silences goal alerts', () {
      final alerts = _goalAlerts(_build(
        orders: [_order('ORD-1', 100)],
        goals: [_revenueGoal(1000)],
        settings: const AlertSettings(disabledTypes: {'goalAtRisk'}),
      ));
      expect(alerts, isEmpty);
    });
  });
}
