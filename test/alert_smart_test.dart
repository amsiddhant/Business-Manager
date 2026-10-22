import 'package:flutter_test/flutter_test.dart';
import 'package:salesforce_business_manager/core/enums.dart';
import 'package:salesforce_business_manager/core/utils/money.dart';
import 'package:salesforce_business_manager/models/campaign.dart';
import 'package:salesforce_business_manager/models/expense.dart';
import 'package:salesforce_business_manager/models/goal.dart';
import 'package:salesforce_business_manager/models/order.dart';
import 'package:salesforce_business_manager/services/alert_service.dart';

const _service = AlertService();
final _today = DateTime(2026, 10, 22, 9);

const _past = [(4, 90), (5, 100), (6, 110), (7, 100), (8, 95), (9, 105)];

Campaign _campaign(int month, int invested) => Campaign(
      id: 'CAM-$month',
      businessId: 'BIZ-1',
      productId: 'PROD-1',
      name: 'Campaign $month',
      platform: CampaignPlatform.meta,
      startDate: DateTime(2026, month, 10),
      amountInvested: Money.fromMajor(invested),
      status: CampaignStatus.active,
    );

Expense _expense(int month, int amount) => Expense(
      id: 'EXP-$month',
      businessId: 'BIZ-1',
      name: 'Tool $month',
      category: ExpenseCategory.software,
      amount: Money.fromMajor(amount),
      startDate: DateTime(2026, month, 10),
    );

/// Marketing and Software both spike in October.
List<String> _spend({
  Map<String, double> scores = const {},
  int marketing = 1000,
  int software = 1000,
}) =>
    [
      for (final a in _service.build(
        customers: const [],
        campaigns: [
          for (final (m, v) in _past) _campaign(m, v),
          _campaign(10, marketing),
        ],
        orders: const [],
        expenses: [
          for (final (m, v) in _past) _expense(m, v),
          _expense(10, software),
        ],
        products: const [],
        warnings: const [],
        demoMode: false,
        now: _today,
        currencyOf: (_) => CurrencyCode.inr,
        spendScores: scores,
      ))
        if (a.type == AlertType.unusualSpend) a.title,
    ];

Order _order(int revenue) => Order(
      id: 'ORD-1',
      businessId: 'BIZ-1',
      productId: 'PROD-1',
      productName: 'Product',
      orderDate: DateTime(2026, 10, 5),
      sellingCost: Money.fromMajor(revenue),
    );

Goal _goal(int target) => Goal(
      businessId: 'BIZ-1',
      period: GoalPeriod.month(2026, 10),
      metric: GoalMetric.revenue,
      target: Money.fromMajor(target).minor,
    );

List<AppAlert> _goals({int? Function(Goal)? projection}) => [
      for (final a in _service.build(
        customers: const [],
        campaigns: const [],
        orders: [_order(100)],
        expenses: const [],
        products: const [],
        warnings: const [],
        demoMode: false,
        now: _today,
        currencyOf: (_) => CurrencyCode.inr,
        goals: [_goal(1000)],
        goalProjection: projection,
      ))
        if (a.type == AlertType.goalAtRisk) a,
    ];

void main() {
  group('spend scores from the on-device model', () {
    test('without scores the built-in check flags both spikes', () {
      expect(_spend(),
          unorderedEquals(['Unusual Marketing spend', 'Unusual Software spend']));
    });

    test('a score replaces the built-in check for that line only', () {
      expect(_spend(scores: {'BIZ-1|Marketing': 0.5}),
          ['Unusual Software spend']);
    });

    test('a high score flags a line the built-in check would not', () {
      expect(
          _spend(marketing: 100, software: 100, scores: {'BIZ-1|Software': 9}),
          ['Unusual Software spend']);
    });

    test('a score for another business does not apply', () {
      expect(_spend(scores: {'BIZ-2|Marketing': 0.5}), hasLength(2));
    });
  });

  group('goal projection from the forecasts', () {
    test('without one, the run rate puts the goal behind', () {
      expect(_goals(), hasLength(1));
    });

    test('a projection that reaches the target clears the alert', () {
      final target = Money.fromMajor(1000).minor;
      expect(_goals(projection: (_) => target), isEmpty);
    });

    test('a projection far under target keeps it behind', () {
      final alerts = _goals(projection: (_) => Money.fromMajor(50).minor);
      expect(alerts.single.key, contains(':behind'));
    });

    test('a null projection falls back to the run rate', () {
      expect(_goals(projection: (_) => null), hasLength(1));
    });
  });
}
