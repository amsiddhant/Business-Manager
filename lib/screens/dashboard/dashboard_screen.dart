import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/enums.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_x.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/money.dart';
import '../../models/app_settings.dart';
import '../../models/app_user.dart';
import '../../services/profit_calculation_service.dart';
import '../../state/alert_controller.dart';
import '../../state/app_state.dart';
import '../../state/data_controller.dart';
import '../../state/filter_controller.dart';
import '../../state/org_settings.dart';
import '../../view_models/dashboard_view_model.dart';
import '../../widgets/alerts/alerts_panel.dart';
import '../../widgets/charts/business_comparison_chart.dart';
import '../../widgets/charts/chart_card.dart';
import '../../widgets/charts/chart_kit.dart';
import '../../widgets/charts/dashboard_charts.dart';
import '../../widgets/charts/marketing_charts.dart';
import '../../widgets/charts/order_status_chart.dart';
import '../../widgets/charts/profit_waterfall_chart.dart';
import '../../widgets/charts/trend_forecast_chart.dart';
import '../../widgets/common/page_header.dart';
import '../../widgets/common/state_views.dart';
import '../../widgets/layout/app_page.dart';
import '../goals/widgets/goals_summary_card.dart';
import 'widgets/attention_strip.dart';
import 'widgets/dashboard_hero.dart';
import 'widgets/dashboard_registry.dart';
import 'widgets/dashboard_section.dart';
import 'widgets/dashboard_tables.dart';
import 'widgets/entrance.dart';
import 'widgets/kpi_tile.dart';

/// The primary landing screen. Every figure here is derived live from the
/// working data set via [ProfitCalculationService] over the currently selected
/// business and reporting period — nothing is hardcoded.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataController>();
    final filter = context.watch<FilterController>();

    if (data.loading && !data.loaded) return const _DashboardSkeleton();
    if (data.error != null && !data.loaded) {
      return AppPage(
        children: [
          const PageHeader(title: 'Dashboard'),
          const SizedBox(height: 48),
          ErrorView(message: data.error!, onRetry: () => data.refresh()),
        ],
      );
    }

    final user = context.select<AppState, AppUser?>((s) => s.currentUser);
    final settings = context.orgSettings((s) => s);
    final sections = _Sections(
      context: context,
      vm: DashboardViewModel.of(data, filter),
      data: data,
      filter: filter,
      user: user,
      settings: settings,
    );
    // The organisation's order and visibility; nothing is ever removed from
    // the totals, only from view.
    final dash = settings.dashboard;
    final built = [
      for (final name in dash.arrange(
          [for (final id in DashboardSectionId.values) id.name]))
        if (dash.isVisible(name))
          if (DashboardSectionId.values.byName(name) case final id)
            if (sections.build(id) case final w?) (id: id, child: w),
    ];

    return AppPage(
      children: [
        for (var i = 0; i < built.length; i++) ...[
          if (i > 0)
            SizedBox(height: i == 1 ? AppSpacing.xl : AppSpacing.xxl),
          Entrance(
            id: 'dashboard-${built[i].id.name}',
            index: i,
            child: built[i].child,
          ),
        ],
      ],
    );
  }
}

/// Builds each dashboard section from the view model.
class _Sections {
  _Sections({
    required this.context,
    required this.vm,
    required this.data,
    required this.filter,
    required this.user,
    required this.settings,
  });

  final BuildContext context;
  final DashboardViewModel vm;
  final DataController data;
  final FilterController filter;
  final AppUser? user;
  final AppSettings settings;

  bool get _insightsOn => settings.features.isOn(AppFeature.insights);
  bool get _forecastsOn => settings.features.isOn(AppFeature.forecasts);

  CurrencyCode get currency => vm.currency;
  ProfitSummary get summary => vm.summary;
  AppTokens get t => context.tokens;

  String money(Money m) => MoneyFormatter.format(m, currency);

  /// "vs previous period", or "vs previous period, to date" while the period
  /// is still running (the deltas compare like with like).
  String get versus =>
      '${vm.basis.shortLabel}${vm.window.isToDate ? ', to date' : ''}';

  /// Whether to link to [route]: the user may open it and its section is on.
  bool can(String route) =>
      Routes.canOpen(user, route) && settings.modules.allows(route);

  VoidCallback? link(String? route) =>
      route != null && can(route) ? () => context.go(route) : null;

  Widget? build(DashboardSectionId id) => switch (id) {
    DashboardSectionId.hero => _hero(),
    DashboardSectionId.attention => _attention(),
    DashboardSectionId.goals => _goals(),
    DashboardSectionId.overview => _overview(),
    DashboardSectionId.profit => _profit(),
    DashboardSectionId.scorecards => _scorecards(),
    DashboardSectionId.products => _products(),
    DashboardSectionId.trends => _trends(),
    DashboardSectionId.breakdowns => _breakdowns(),
    DashboardSectionId.tables => _tables(),
  };

  /// Running goals for the scope; hidden when none are set.
  Widget? _goals() {
    if (!settings.modules.isEnabled(Routes.goals)) return null;
    final businessId = filter.selectedBusinessId;
    if (data.goalsFor(businessId).isEmpty) return null;
    return GoalsSummaryCard(businessId: businessId);
  }

  // ── KPIs ────────────────────────────────────────────────────────────────

  KpiData _kpi(
    KpiMetric metric, {
    required IconData icon,
    required String tooltip,
    required String tab,
    String? label,
    Color? accent,
    String? caption,
    bool negative = false,
  }) {
    final String Function(double) format = metric.isMoney
        ? (v) => money(Money.fromMajor(v))
        : metric.isPercent
            ? (v) => PercentFormatter.format(v)
            : (v) => v.round().toString();
    return KpiData(
      id: metric.name,
      label: label ?? metric.label,
      value: metric.valueOf(summary),
      format: format,
      icon: icon,
      tooltip: tooltip,
      delta: vm.comparison[metric],
      trend: vm.trend(metric),
      caption: caption,
      accent: accent,
      negative: negative,
      onTap: link(Routes.reportsTab(tab)),
    );
  }

  KpiData get _revenue => _kpi(KpiMetric.revenue,
      icon: Icons.trending_up,
      accent: t.chartSeries[0],
      tooltip: 'Total recognised sales revenue.',
      tab: 'sales');

  KpiData get _netProfit {
    final loss = summary.netProfit.isNegative;
    return _kpi(KpiMetric.netProfit,
        icon: Icons.account_balance_wallet_outlined,
        accent: loss ? t.error : t.success,
        caption: 'Revenue − all costs',
        negative: loss,
        tooltip: 'Revenue − Product Cost − Marketing − Operating Expenses.',
        tab: 'business');
  }

  KpiData get _netMargin => _kpi(KpiMetric.netMargin,
      icon: Icons.percent,
      accent: t.chartSeries[1],
      tooltip: 'Net Profit / Revenue × 100.',
      tab: 'business');

  KpiData get _orders => _kpi(KpiMetric.orders,
      icon: Icons.shopping_cart_outlined,
      accent: t.chartSeries[8],
      tooltip: 'Number of recognised orders.',
      tab: 'sales');

  KpiData _kpiOf(KpiMetric m) => switch (m) {
    KpiMetric.revenue => _revenue,
    KpiMetric.netProfit => _netProfit,
    KpiMetric.netMargin => _netMargin,
    KpiMetric.orders => _orders,
    KpiMetric.productCost => _kpi(KpiMetric.productCost,
        icon: Icons.inventory_2_outlined,
        accent: t.chartSeries[3],
        tooltip: 'Total product purchasing cost for recognised orders.',
        tab: 'products'),
    KpiMetric.marketingCost => _kpi(KpiMetric.marketingCost,
        icon: Icons.campaign_outlined,
        accent: t.chartSeries[6],
        tooltip: 'Total advertising spend in the selected period.',
        tab: 'marketing'),
    KpiMetric.operatingExpenses => _kpi(KpiMetric.operatingExpenses,
        icon: Icons.receipt_long_outlined,
        accent: t.chartSeries[5],
        tooltip: 'Prorated operating costs (excluding advertising).',
        tab: 'expenses'),
    KpiMetric.grossProfit => _kpi(KpiMetric.grossProfit,
        icon: Icons.savings_outlined,
        accent: t.success,
        caption: 'Margin ${PercentFormatter.format(summary.grossMargin)}',
        tooltip: 'Revenue − Product Cost.',
        tab: 'products'),
    KpiMetric.contributionProfit => _kpi(KpiMetric.contributionProfit,
        icon: Icons.stacked_line_chart,
        accent: t.chartSeries[7],
        tooltip: 'Gross Profit − Marketing Cost.',
        tab: 'business'),
    KpiMetric.units => _kpi(KpiMetric.units,
        icon: Icons.local_shipping_outlined,
        accent: t.chartSeries[9],
        tooltip: 'Total quantity across recognised orders.',
        tab: 'sales'),
    // Not one of the dashboard's figures (see kDashboardKpis).
    KpiMetric.grossMargin => _kpi(KpiMetric.grossMargin,
        icon: Icons.percent,
        accent: t.success,
        tooltip: 'Gross Profit as a share of Revenue.',
        tab: 'products'),
  };

  /// The four headline figures: the organisation's pick, or the first
  /// [kHeroKpiCount] of [kDashboardKpis].
  List<KpiMetric> get _heroMetrics {
    final named = [
      for (final n in settings.dashboard.heroKpis)
        kDashboardKpis.where((m) => m.name == n).firstOrNull,
    ];
    if (named.length == kHeroKpiCount &&
        !named.contains(null) &&
        named.toSet().length == kHeroKpiCount) {
      return [for (final m in named) m!];
    }
    return kDashboardKpis.take(kHeroKpiCount).toList();
  }

  /// Every other figure, in [kDashboardKpis] order ("More figures").
  List<KpiData> get _secondary {
    final hero = _heroMetrics;
    return [
      for (final m in kDashboardKpis)
        if (!hero.contains(m)) _kpiOf(m),
    ];
  }

  // ── Sections ────────────────────────────────────────────────────────────

  Widget _hero() {
    final bizId = filter.selectedBusinessId;
    final business = bizId == null
        ? 'All Businesses'
        : (data.businessById(bizId)?.name ?? 'Business');
    final p = _forecastsOn ? vm.projection : null;
    return DashboardHero(
      name: user?.name,
      scope: '$business · ${filter.periodLabel} · ${vm.range}',
      basis: vm.basis,
      onBasis: filter.setComparison,
      onSync: () => data.sync(),
      syncing: data.syncing,
      versus: versus,
      kpis: [for (final m in _heroMetrics) _kpiOf(m)],
      projection: p == null
          ? null
          : 'On pace for ${MoneyFormatter.compact(p.revenue, currency)} '
              'revenue · ${MoneyFormatter.compact(p.netProfit, currency)} '
              'net profit by ${AppDate.short(vm.range.end)}',
    );
  }

  Widget _attention() {
    final alerts = context.watch<AlertController>();
    return DashboardSection(
      title: 'Attention & insights',
      subtitle: 'Worked out from your data, on this device',
      tiles: [
        DashTile(
          span: 12,
          child: AttentionStrip(
            alerts: alerts.active(alertsOf(context)),
            insights: _insightsOn ? vm.insights : const [],
            onOpenAlerts: () => AlertsPanel.open(context),
            onOpen: link,
          ),
        ),
      ],
    );
  }

  Widget _overview() {
    final series = vm.series;
    final slices = vm.breakdown;
    var total = Money.zero;
    for (final s in slices) {
      total = total + s.amount;
    }
    return DashboardSection(
      title: 'Money in and out',
      subtitle: vm.range.toString(),
      tiles: [
        DashTile(
          span: 8,
          child: ChartCard(
            icon: Icons.bar_chart_rounded,
            title: 'Revenue vs Expenses',
            subtitle: 'Grouped by period',
            height: 300,
            isEmpty: series.isEmpty,
            table: ChartTableData(
              headers: const [
                'Period',
                'Revenue',
                'Product Cost',
                'Marketing',
                'Operating',
                'Net Profit',
              ],
              rows: [
                for (final p in series)
                  [
                    p.label,
                    money(p.revenue),
                    money(p.productCost),
                    money(p.marketingCost),
                    money(p.operatingExpenses),
                    money(p.netProfit),
                  ],
              ],
            ),
            child: RevenueExpenseChart(points: series, currency: currency),
          ),
        ),
        DashTile(
          span: 4,
          child: ChartCard(
            icon: Icons.donut_large_outlined,
            title: 'Expense Breakdown',
            subtitle: 'Where the money goes',
            height: 300,
            isEmpty: slices.isEmpty,
            table: ChartTableData(
              headers: const ['Category', 'Amount', 'Share'],
              rows: [
                for (final s in slices)
                  [
                    s.label,
                    money(s.amount),
                    total.isZero
                        ? '—'
                        : PercentFormatter.format(
                            s.amount.major / total.major * 100),
                  ],
              ],
            ),
            child: ExpenseDonutChart(slices: slices, currency: currency),
          ),
        ),
      ],
    );
  }

  Widget _profit() {
    final steps = vm.waterfall;
    final projecting = _forecastsOn && vm.projection != null;
    final forecast = _forecastsOn
        ? vm.forecast
        : [
            for (final p in vm.forecast)
              ForecastPoint(
                  label: p.label, revenue: p.revenue, netProfit: p.netProfit),
          ];
    String opt(Money? m) => m == null ? '—' : money(m);
    return DashboardSection(
      title: 'Profit',
      subtitle: 'From revenue to what you keep',
      tiles: [
        DashTile(
          child: ChartCard(
            icon: Icons.waterfall_chart,
            title: 'Profit Waterfall',
            subtitle: 'Revenue, less each cost, to net profit',
            height: 300,
            isEmpty: steps.every((s) => s.amount.isZero),
            table: ChartTableData(
              headers: const ['Step', 'Amount', 'Running total'],
              rows: [
                for (final s in steps)
                  [s.label, money(s.amount), money(s.end)],
              ],
            ),
            child: ProfitWaterfallChart(steps: steps, currency: currency),
          ),
        ),
        DashTile(
          child: ChartCard(
            icon: Icons.auto_graph,
            title: 'Revenue & Profit Trend',
            subtitle: !projecting
                ? 'Revenue and net profit over the period'
                : 'Projected at the current pace to '
                    '${AppDate.short(vm.range.end)}',
            height: 300,
            isEmpty: forecast.isEmpty,
            table: ChartTableData(
              headers: [
                'Period',
                'Revenue',
                'Net Profit',
                if (_forecastsOn) ...['Projected revenue', 'Projected net profit'],
              ],
              rows: [
                for (final p in forecast)
                  [
                    p.label,
                    opt(p.revenue),
                    opt(p.netProfit),
                    if (_forecastsOn) ...[
                      opt(p.projectedRevenue),
                      opt(p.projectedNetProfit),
                    ],
                  ],
              ],
            ),
            child: TrendForecastChart(points: forecast, currency: currency),
          ),
        ),
      ],
    );
  }

  Widget _scorecards() => DashboardSection(
    title: 'Key figures',
    subtitle: 'Tap a figure to open its report',
    tiles: [
      for (final k in _secondary)
        DashTile(
          span: 4,
          tablet: 6,
          mobile: 6,
          child: KpiTile(data: k, versus: versus),
        ),
    ],
  );

  Widget _products() {
    final byRevenue = ([...vm.productProfit]
          ..sort((a, b) => b.revenue.minor.compareTo(a.revenue.minor)))
        .take(8)
        .toList();
    final byProfit = ([...vm.productProfit]
          ..sort((a, b) => b.netProfit.minor.compareTo(a.netProfit.minor)))
        .take(8)
        .toList();
    return DashboardSection(
      title: 'Products',
      subtitle: 'Your top eight by revenue and by profit',
      tiles: [
        DashTile(
          child: ChartCard(
            icon: Icons.inventory_2_outlined,
            title: 'Revenue by Product',
            isEmpty: byRevenue.isEmpty,
            table: ChartTableData(
              headers: const ['Product', 'Revenue'],
              rows: [
                for (final p in byRevenue) [p.product.name, money(p.revenue)],
              ],
            ),
            child: CategoryBarChart(
              revealId: 'revenue-by-product',
              labels: [for (final p in byRevenue) p.product.name],
              values: [for (final p in byRevenue) p.revenue],
              currency: currency,
              color: t.chartSeries[0],
            ),
          ),
        ),
        DashTile(
          child: ChartCard(
            icon: Icons.savings_outlined,
            title: 'Profit by Product',
            isEmpty: byProfit.isEmpty,
            table: ChartTableData(
              headers: const ['Product', 'Net Profit'],
              rows: [
                for (final p in byProfit) [p.product.name, money(p.netProfit)],
              ],
            ),
            child: CategoryBarChart(
              revealId: 'profit-by-product',
              labels: [for (final p in byProfit) p.product.name],
              values: [for (final p in byProfit) p.netProfit],
              currency: currency,
              color: t.success,
            ),
          ),
        ),
      ],
    );
  }

  Widget _trends() {
    final series = vm.series;
    return DashboardSection(
      title: 'Marketing & orders',
      subtitle: 'How spend and orders moved through the period',
      tiles: [
        DashTile(
          child: ChartCard(
            icon: Icons.campaign_outlined,
            title: 'Marketing Spend',
            subtitle: 'Advertising over time',
            isEmpty: series.isEmpty,
            table: ChartTableData(
              headers: const ['Period', 'Marketing'],
              rows: [
                for (final p in series) [p.label, money(p.marketingCost)],
              ],
            ),
            child: TrendLineChart(
              revealId: 'marketing-spend',
              seriesLabel: 'Marketing',
              labels: [for (final p in series) p.label],
              values: [for (final p in series) p.marketingCost.major],
              color: t.chartSeries[6],
              currency: currency,
            ),
          ),
        ),
        DashTile(
          child: ChartCard(
            icon: Icons.shopping_cart_outlined,
            title: 'Orders Trend',
            subtitle: 'Recognised orders over time',
            isEmpty: series.isEmpty,
            table: ChartTableData(
              headers: const ['Period', 'Orders'],
              rows: [
                for (final p in series) [p.label, '${p.orders}'],
              ],
            ),
            child: TrendLineChart(
              revealId: 'orders-trend',
              seriesLabel: 'Orders',
              labels: [for (final p in series) p.label],
              values: [for (final p in series) p.orders.toDouble()],
              color: t.chartSeries[1],
            ),
          ),
        ),
      ],
    );
  }

  Widget _breakdowns() {
    final mix = vm.platformMix.entries.where((e) => !e.value.isZero).toList()
      ..sort((a, b) => b.value.minor.compareTo(a.value.minor));
    var mixTotal = Money.zero;
    for (final e in mix) {
      mixTotal = mixTotal + e.value;
    }
    final roas = RoasChart.pick(vm.campaignPerformance);
    final statuses = vm.statusBreakdown.entries.where((e) => e.value > 0);
    var orderTotal = 0;
    for (final e in statuses) {
      orderTotal += e.value;
    }
    String share(double part, double whole) =>
        whole == 0 ? '—' : PercentFormatter.format(part / whole * 100);
    final comparison = vm.businessComparison;

    return DashboardSection(
      title: 'Mix & performance',
      subtitle: 'Where spend goes, what it earns back, and how orders end up',
      tiles: [
        DashTile(
          span: 4,
          child: ChartCard(
            icon: Icons.pie_chart_outline,
            title: 'Spend by Platform',
            subtitle: 'Advertising mix',
            isEmpty: mix.isEmpty,
            table: ChartTableData(
              headers: const ['Platform', 'Spend', 'Share'],
              rows: [
                for (final e in mix)
                  [
                    e.key.label,
                    money(e.value),
                    share(e.value.major, mixTotal.major),
                  ],
              ],
            ),
            child: PlatformMixChart(mix: vm.platformMix, currency: currency),
          ),
        ),
        DashTile(
          span: 4,
          child: ChartCard(
            icon: Icons.ads_click,
            title: 'Return on Ad Spend',
            subtitle: 'Biggest campaigns, against break-even',
            isEmpty: roas.isEmpty,
            table: ChartTableData(
              headers: const ['Campaign', 'Spend', 'ROAS'],
              rows: [
                for (final c in roas)
                  [
                    c.campaign.name,
                    money(c.spend),
                    PercentFormatter.roas(c.roas),
                  ],
              ],
            ),
            child: RoasChart(
              rows: vm.campaignPerformance,
              currency: currency,
              onTap: can(Routes.campaigns)
                  ? (c) => context
                      .go(Routes.campaignDetailPath(c.campaign.id))
                  : null,
            ),
          ),
        ),
        DashTile(
          span: 4,
          child: ChartCard(
            icon: Icons.local_shipping_outlined,
            title: 'Order Status',
            subtitle: 'Where the period\'s orders stand',
            isEmpty: orderTotal == 0,
            table: ChartTableData(
              headers: const ['Status', 'Orders', 'Share'],
              rows: [
                for (final e in statuses)
                  [
                    e.key.label,
                    '${e.value}',
                    share(e.value.toDouble(), orderTotal.toDouble()),
                  ],
              ],
            ),
            child: OrderStatusChart(breakdown: vm.statusBreakdown),
          ),
        ),
        if (comparison.isNotEmpty)
          DashTile(
            span: 12,
            child: ChartCard(
              icon: Icons.business_outlined,
              title: 'Business Comparison',
              subtitle: 'Revenue, costs and net profit by business',
              height: 300,
              table: ChartTableData(
                headers: const [
                  'Business',
                  'Revenue',
                  'Costs',
                  'Net Profit',
                  'Net margin',
                ],
                rows: [
                  for (final b in comparison)
                    [
                      b.business.name,
                      money(b.summary.revenue),
                      money(b.summary.totalExpenses),
                      money(b.summary.netProfit),
                      PercentFormatter.format(b.summary.netMargin),
                    ],
                ],
              ),
              child: BusinessComparisonChart(
                  rows: comparison, currency: currency),
            ),
          ),
      ],
    );
  }

  Widget _tables() => DashboardSection(
    title: 'Details',
    subtitle: 'Search finds any row in the period, not just the top ten',
    tiles: [
      DashTile(
        span: 12,
        child: TopProductsTable(
          rows: vm.productProfit,
          currency: currency,
          onRowTap: can(Routes.products)
              ? (p) => context.go(Routes.productDetailPath(p.product.id))
              : null,
          onViewAll: link(Routes.reportsTab('products')),
        ),
      ),
      DashTile(
        span: 12,
        child: RecentOrdersTable(
          orders: vm.orders,
          range: vm.range,
          currency: currency,
          onRowTap: can(Routes.orders)
              ? (o) => context.go(Routes.orderDetailPath(o.id))
              : null,
          onViewAll: link(Routes.orders),
        ),
      ),
      DashTile(
        span: 12,
        child: CampaignPerformanceTable(
          rows: vm.campaignPerformance,
          currency: currency,
          onRowTap: can(Routes.campaigns)
              ? (c) => context.go(Routes.campaignDetailPath(c.campaign.id))
              : null,
          onViewAll: link(Routes.reportsTab('marketing')),
        ),
      ),
    ],
  );
}

/// The dashboard's shape while the data loads.
class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    return AppPage(
      children: [
        Semantics(
          label: 'Loading your dashboard…',
          child: const SkeletonBox(height: 300, radius: 20),
        ),
        const SizedBox(height: AppSpacing.xl),
        const DashboardSection(
          tiles: [
            DashTile(span: 8, child: SkeletonCard(lines: 6, height: 380)),
            DashTile(span: 4, child: SkeletonCard(lines: 6, height: 380)),
            DashTile(child: SkeletonCard(lines: 6, height: 380)),
            DashTile(child: SkeletonCard(lines: 6, height: 380)),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        const LoadingView(label: 'Loading your dashboard…'),
      ],
    );
  }
}
