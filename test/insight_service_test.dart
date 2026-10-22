import 'package:flutter_test/flutter_test.dart';
import 'package:salesforce_business_manager/core/enums.dart';
import 'package:salesforce_business_manager/core/routing/app_routes.dart';
import 'package:salesforce_business_manager/core/utils/date_utils.dart';
import 'package:salesforce_business_manager/core/utils/money.dart';
import 'package:salesforce_business_manager/services/insight_service.dart';
import 'package:salesforce_business_manager/services/profit_calculation_service.dart';

ProfitSummary _summary(int revenue, int costs) => ProfitSummary(
      revenue: Money.fromMajor(revenue),
      productCost: Money.fromMajor(costs),
      marketingCost: Money.zero,
      operatingExpenses: Money.zero,
      orderCount: 1,
      unitsSold: 1,
    );

List<Insight> _build(ProfitSummary current, ProfitSummary previous) =>
    const InsightService().build(
      comparison: ProfitComparison(current: current, previous: previous),
      basis: ComparisonBasis.previousPeriod,
      isToDate: false,
      products: const [],
      campaigns: const [],
      monthlySpend: const {},
      customers: const [],
      businessId: null,
      currency: CurrencyCode.inr,
      now: DateTime(2026, 10, 22),
    );

void main() {
  test('a big revenue rise is a positive insight that opens Sales', () {
    final insights = _build(_summary(1200, 600), _summary(1000, 500));
    final revenue =
        insights.firstWhere((i) => i.kind == InsightKind.revenueChange);
    expect(revenue.tone, InsightTone.positive);
    expect(revenue.title, contains('up'));
    expect(revenue.route, Routes.reportsTab('sales'));
  });

  test('a margin drop of 3 points or more is flagged', () {
    // 50% net margin now, 60% before; revenue flat.
    final insights = _build(_summary(1000, 500), _summary(1000, 400));
    final margin =
        insights.firstWhere((i) => i.kind == InsightKind.marginChange);
    expect(margin.tone, InsightTone.negative);
    expect(margin.title, contains('10.0 pts'));
    expect(insights.where((i) => i.kind == InsightKind.revenueChange),
        isEmpty);
  });

  test('small moves say nothing', () {
    final insights = _build(_summary(1050, 500), _summary(1000, 480));
    expect(
        insights.where((i) =>
            i.kind == InsightKind.revenueChange ||
            i.kind == InsightKind.marginChange),
        isEmpty);
  });
}
