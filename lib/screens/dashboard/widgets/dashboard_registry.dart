import '../../../services/profit_calculation_service.dart';

/// The dashboard's sections, in their default order. The dashboard builds
/// them from this list, so Settings (P4) can reorder and hide them without
/// touching the screen.
enum DashboardSectionId {
  hero('Headline figures'),
  attention('Alerts and insights'),
  goals('Goals'),
  overview('Revenue and expenses'),
  profit('Profit and trend'),
  scorecards('More figures'),
  products('Products'),
  trends('Marketing and orders'),
  breakdowns('Breakdowns'),
  tables('Tables');

  const DashboardSectionId(this.label);
  final String label;
}

/// The default layout: every section, in order.
const kDefaultDashboardSections = DashboardSectionId.values;

/// The figures the dashboard shows, in order: the first four make the
/// headline row, the rest the "More figures" section. Settings can pick a
/// different headline four ([DashboardSettings.heroKpis] holds their names).
const kDashboardKpis = [
  KpiMetric.revenue,
  KpiMetric.netProfit,
  KpiMetric.netMargin,
  KpiMetric.orders,
  KpiMetric.productCost,
  KpiMetric.marketingCost,
  KpiMetric.operatingExpenses,
  KpiMetric.grossProfit,
  KpiMetric.contributionProfit,
  KpiMetric.units,
];

/// How many figures the headline row holds.
const kHeroKpiCount = 4;
