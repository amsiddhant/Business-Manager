import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/enums.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/money.dart';
import '../../models/order.dart';
import '../../services/profit_calculation_service.dart';
import '../../state/data_controller.dart';
import '../../state/filter_controller.dart';
import '../../widgets/charts/chart_card.dart';
import '../../widgets/charts/dashboard_charts.dart';
import '../../widgets/common/app_card.dart';
import '../../widgets/common/currency_display.dart';
import '../../widgets/common/data_table_card.dart';
import '../../widgets/common/page_header.dart';
import '../../widgets/common/responsive.dart';
import '../../widgets/common/scorecard.dart';
import '../../widgets/common/search_field.dart';
import '../../widgets/common/state_views.dart';
import '../../widgets/common/status_badge.dart';

/// The primary landing screen. Every figure here is derived live from the
/// working data set via [ProfitCalculationService] over the currently selected
/// business and reporting period — nothing is hardcoded.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  static const _service = ProfitCalculationService();

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataController>();
    final filter = context.watch<FilterController>();

    if (data.loading && !data.loaded) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(title: 'Dashboard'),
          SizedBox(height: 48),
          LoadingView(label: 'Loading your dashboard…'),
        ],
      );
    }
    if (data.error != null && !data.loaded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PageHeader(title: 'Dashboard'),
          const SizedBox(height: 48),
          ErrorView(message: data.error!, onRetry: () => data.refresh()),
        ],
      );
    }

    final bizId = filter.selectedBusinessId;
    final range = filter.range;

    final orders = data.ordersFor(bizId);
    final campaigns = data.campaignsFor(bizId);
    final expenses = data.expensesFor(bizId);
    final products = data.productsFor(bizId);

    final currency = _resolveCurrency(data, bizId);

    final summary = _service.summarise(
      orders: orders,
      campaigns: campaigns,
      expenses: expenses,
      range: range,
    );

    final productProfit = _service.productProfitability(
      products: products,
      orders: orders,
      campaigns: campaigns,
      range: range,
    );

    final campaignPerf = _service.campaignPerformance(
      campaigns: campaigns,
      orders: orders,
      range: range,
    );

    final series = _service.timeSeries(
      orders: orders,
      campaigns: campaigns,
      expenses: expenses,
      range: range,
    );

    final breakdown = _service.expenseBreakdown(
      orders: orders,
      campaigns: campaigns,
      expenses: expenses,
      range: range,
    );

    final subtitle =
        '${filter.periodLabel} · ${range.toString()}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: 'Dashboard',
          subtitle: subtitle,
          actions: [
            OutlinedButton.icon(
              onPressed: () => data.refresh(),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Refresh'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        _Scorecards(summary: summary, currency: currency),
        const SizedBox(height: AppSpacing.lg),
        _ChartsGrid(
          series: series,
          breakdown: breakdown,
          productProfit: productProfit,
          currency: currency,
        ),
        const SizedBox(height: AppSpacing.lg),
        _TopProductsTable(rows: productProfit, currency: currency),
        const SizedBox(height: AppSpacing.lg),
        _RecentOrdersTable(
          orders: orders,
          range: range,
          currency: currency,
        ),
        const SizedBox(height: AppSpacing.lg),
        _CampaignPerformanceTable(rows: campaignPerf, currency: currency),
      ],
    );
  }

  CurrencyCode _resolveCurrency(DataController data, String? bizId) {
    if (bizId != null) {
      final biz = data.businessById(bizId);
      if (biz != null) return biz.currency;
    }
    return CurrencyCode.inr;
  }
}

/// The 10 headline metrics, laid out in a responsive grid.
class _Scorecards extends StatelessWidget {
  const _Scorecards({required this.summary, required this.currency});

  final ProfitSummary summary;
  final CurrencyCode currency;

  @override
  Widget build(BuildContext context) {
    String money(Money m) => MoneyFormatter.format(m, currency);

    final cards = <Widget>[
      Scorecard(
        label: 'Revenue',
        value: money(summary.revenue),
        icon: Icons.trending_up,
        accent: AppColors.chartSeries[0],
        tooltip: 'Total recognised sales revenue.',
      ),
      Scorecard(
        label: 'Product Cost',
        value: money(summary.productCost),
        icon: Icons.inventory_2_outlined,
        accent: AppColors.chartSeries[3],
        tooltip: 'Total product purchasing cost for recognised orders.',
      ),
      Scorecard(
        label: 'Marketing',
        value: money(summary.marketingCost),
        icon: Icons.campaign_outlined,
        accent: AppColors.chartSeries[6],
        tooltip: 'Total advertising spend in the selected period.',
      ),
      Scorecard(
        label: 'Operating Expenses',
        value: money(summary.operatingExpenses),
        icon: Icons.receipt_long_outlined,
        accent: AppColors.chartSeries[5],
        tooltip: 'Prorated operating costs (excluding advertising).',
      ),
      Scorecard(
        label: 'Gross Profit',
        value: money(summary.grossProfit),
        icon: Icons.savings_outlined,
        accent: AppColors.success,
        caption: 'Margin ${PercentFormatter.format(summary.grossMargin)}',
        tooltip: 'Revenue − Product Cost.',
      ),
      Scorecard(
        label: 'Contribution Profit',
        value: money(summary.contributionProfit),
        icon: Icons.stacked_line_chart,
        accent: AppColors.chartSeries[7],
        tooltip: 'Gross Profit − Marketing Cost.',
      ),
      Scorecard(
        label: 'Net Profit',
        value: money(summary.netProfit),
        icon: Icons.account_balance_wallet_outlined,
        accent: summary.netProfit.isNegative
            ? AppColors.error
            : AppColors.success,
        caption: 'Revenue − all costs',
        captionTone:
            summary.netProfit.isNegative ? AppColors.error : null,
        tooltip: 'Revenue − Product Cost − Marketing − Operating Expenses.',
      ),
      Scorecard(
        label: 'Net Margin',
        value: PercentFormatter.format(summary.netMargin),
        icon: Icons.percent,
        accent: AppColors.chartSeries[1],
        tooltip: 'Net Profit / Revenue × 100.',
      ),
      Scorecard(
        label: 'Total Orders',
        value: summary.orderCount.toString(),
        icon: Icons.shopping_cart_outlined,
        accent: AppColors.chartSeries[8],
        tooltip: 'Number of recognised orders.',
      ),
      Scorecard(
        label: 'Units Sold',
        value: summary.unitsSold.toString(),
        icon: Icons.local_shipping_outlined,
        accent: AppColors.chartSeries[9],
        tooltip: 'Total quantity across recognised orders.',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final screen = Responsive.of(context);
        final columns = switch (screen) {
          ScreenType.mobile => 1,
          ScreenType.tablet => 2,
          ScreenType.desktop => constraints.maxWidth > 1180 ? 5 : 3,
        };
        const gap = AppSpacing.md;
        final tileWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final card in cards)
              SizedBox(width: tileWidth, child: card),
          ],
        );
      },
    );
  }
}

/// Charts arranged two-up on wide screens, stacked on narrow ones.
class _ChartsGrid extends StatelessWidget {
  const _ChartsGrid({
    required this.series,
    required this.breakdown,
    required this.productProfit,
    required this.currency,
  });

  final List<TimeSeriesPoint> series;
  final List<CategorySlice> breakdown;
  final List<ProductProfit> productProfit;
  final CurrencyCode currency;

  @override
  Widget build(BuildContext context) {
    // Revenue by product / profit by product use the top products by revenue.
    final byRevenue = [...productProfit]
      ..sort((a, b) => b.revenue.minor.compareTo(a.revenue.minor));
    final topRevenue = byRevenue.take(8).toList();

    final byProfit = [...productProfit]
      ..sort((a, b) => b.netProfit.minor.compareTo(a.netProfit.minor));
    final topProfit = byProfit.take(8).toList();

    final revenueVsExpenses = ChartCard(
      title: 'Revenue vs Expenses',
      subtitle: 'Grouped by period',
      isEmpty: series.isEmpty,
      child: RevenueExpenseChart(points: series, currency: currency),
    );

    final expenseBreakdown = ChartCard(
      title: 'Expense Breakdown',
      subtitle: 'Where the money goes',
      isEmpty: breakdown.isEmpty,
      child: ExpenseDonutChart(slices: breakdown, currency: currency),
    );

    final revenueByProduct = ChartCard(
      title: 'Revenue by Product',
      isEmpty: topRevenue.isEmpty,
      child: CategoryBarChart(
        labels: [for (final p in topRevenue) p.product.name],
        values: [for (final p in topRevenue) p.revenue],
        currency: currency,
        color: AppColors.chartSeries[0],
      ),
    );

    final profitByProduct = ChartCard(
      title: 'Profit by Product',
      isEmpty: topProfit.isEmpty,
      child: CategoryBarChart(
        labels: [for (final p in topProfit) p.product.name],
        values: [for (final p in topProfit) p.netProfit],
        currency: currency,
        color: AppColors.success,
      ),
    );

    final marketingSpend = ChartCard(
      title: 'Marketing Spend',
      subtitle: 'Advertising over time',
      isEmpty: series.isEmpty,
      child: TrendLineChart(
        labels: [for (final p in series) p.label],
        values: [for (final p in series) p.marketingCost.major],
        color: AppColors.chartSeries[6],
        currency: currency,
      ),
    );

    final ordersTrend = ChartCard(
      title: 'Orders Trend',
      subtitle: 'Recognised orders over time',
      isEmpty: series.isEmpty,
      child: TrendLineChart(
        labels: [for (final p in series) p.label],
        values: [for (final p in series) p.orders.toDouble()],
        color: AppColors.chartSeries[1],
      ),
    );

    final rows = <List<Widget>>[
      [revenueVsExpenses, expenseBreakdown],
      [revenueByProduct, profitByProduct],
      [marketingSpend, ordersTrend],
    ];

    final isNarrow = !Responsive.isDesktop(context);
    if (isNarrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final pair in rows)
            for (final chart in pair)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                child: chart,
              ),
        ],
      );
    }

    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: rows[i][0]),
              const SizedBox(width: AppSpacing.lg),
              Expanded(child: rows[i][1]),
            ],
          ),
          if (i < rows.length - 1) const SizedBox(height: AppSpacing.lg),
        ],
      ],
    );
  }
}

class _TopProductsTable extends StatefulWidget {
  const _TopProductsTable({required this.rows, required this.currency});

  final List<ProductProfit> rows;
  final CurrencyCode currency;

  @override
  State<_TopProductsTable> createState() => _TopProductsTableState();
}

class _TopProductsTableState extends State<_TopProductsTable> {
  String _productSearch = '';

  @override
  Widget build(BuildContext context) {
    final currency = widget.currency;
    final sorted = [...widget.rows]
      ..sort((a, b) => b.revenue.minor.compareTo(a.revenue.minor));
    final top = sorted.take(10).toList();

    return SectionCard(
      title: 'Top Products',
      subtitle: 'Ranked by revenue in the selected period',
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            child: SearchField(
              hintText: 'Search products by name…',
              onChanged: (v) => setState(() => _productSearch = v),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppDataTable<ProductProfit>(
            rows: top,
            rowsPerPage: 10,
            searchText: _productSearch,
            searchableText: (p) => p.product.name,
            emptyTitle: 'No product activity',
            emptyMessage: 'Recognised orders will populate this table.',
            columns: [
              AppColumn(
                label: 'Product',
                cell: (p) => Text(p.product.name,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                sortValue: (p) => p.product.name.toLowerCase(),
              ),
              AppColumn(
                label: 'Orders',
                numeric: true,
                cell: (p) => Text('${p.orderCount}'),
                sortValue: (p) => p.orderCount,
              ),
              AppColumn(
                label: 'Revenue',
                numeric: true,
                cell: (p) => CurrencyText(p.revenue, currency: currency),
                sortValue: (p) => p.revenue.minor,
              ),
              AppColumn(
                label: 'Cost',
                numeric: true,
                cell: (p) => CurrencyText(p.productCost, currency: currency),
                sortValue: (p) => p.productCost.minor,
              ),
              AppColumn(
                label: 'Marketing',
                numeric: true,
                cell: (p) => CurrencyText(p.marketingCost, currency: currency),
                sortValue: (p) => p.marketingCost.minor,
              ),
              AppColumn(
                label: 'Gross Profit',
                numeric: true,
                cell: (p) => CurrencyText(p.grossProfit, currency: currency),
                sortValue: (p) => p.grossProfit.minor,
              ),
              AppColumn(
                label: 'Net Profit',
                numeric: true,
                cell: (p) => CurrencyText(p.netProfit, currency: currency),
                sortValue: (p) => p.netProfit.minor,
              ),
              AppColumn(
                label: 'Margin',
                numeric: true,
                cell: (p) => Text(PercentFormatter.format(p.margin)),
                sortValue: (p) => p.margin.isFinite ? p.margin : -1,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecentOrdersTable extends StatefulWidget {
  const _RecentOrdersTable({
    required this.orders,
    required this.range,
    required this.currency,
  });

  final List<Order> orders;
  final DateRange range;
  final CurrencyCode currency;

  @override
  State<_RecentOrdersTable> createState() => _RecentOrdersTableState();
}

class _RecentOrdersTableState extends State<_RecentOrdersTable> {
  String _orderSearch = '';

  static final _epoch = DateTime.fromMillisecondsSinceEpoch(0);
  static DateTime _dateOf(Order o) =>
      o.orderDate ?? o.audit.createdAt ?? _epoch;

  @override
  Widget build(BuildContext context) {
    final currency = widget.currency;
    final range = widget.range;
    final inRange = widget.orders
        .where((o) => range.contains(_dateOf(o)))
        .toList()
      ..sort((a, b) => _dateOf(b).compareTo(_dateOf(a)));
    final recent = inRange.take(10).toList();

    return SectionCard(
      title: 'Recent Orders',
      subtitle: 'Latest activity in the selected period',
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            child: SearchField(
              hintText: 'Search orders by ID, product or status…',
              onChanged: (v) => setState(() => _orderSearch = v),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppDataTable<Order>(
            rows: recent,
            rowsPerPage: 10,
            searchText: _orderSearch,
            searchableText: (o) =>
                '${o.id} ${o.productName} ${o.status.label}',
            emptyTitle: 'No orders yet',
            emptyMessage: 'Orders in the selected period will appear here.',
            columns: [
              AppColumn(
                label: 'Order ID',
                cell: (o) => Text(o.id,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                sortValue: (o) => o.id,
              ),
              AppColumn(
                label: 'Product',
                cell: (o) => Text(o.productName),
                sortValue: (o) => o.productName.toLowerCase(),
              ),
              AppColumn(
                label: 'Date',
                cell: (o) => Text(AppDate.short(_dateOf(o))),
                sortValue: (o) => _dateOf(o).millisecondsSinceEpoch,
              ),
              AppColumn(
                label: 'Revenue',
                numeric: true,
                cell: (o) =>
                    CurrencyText(o.recognisedRevenue, currency: currency),
                sortValue: (o) => o.recognisedRevenue.minor,
              ),
              AppColumn(
                label: 'Cost',
                numeric: true,
                cell: (o) =>
                    CurrencyText(o.recognisedProductCost, currency: currency),
                sortValue: (o) => o.recognisedProductCost.minor,
              ),
              AppColumn(
                label: 'Profit',
                numeric: true,
                cell: (o) =>
                    CurrencyText(o.recognisedGrossProfit, currency: currency),
                sortValue: (o) => o.recognisedGrossProfit.minor,
              ),
              AppColumn(
                label: 'Status',
                cell: (o) => StatusBadge.order(o.status),
                sortValue: (o) => o.status.label,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CampaignPerformanceTable extends StatefulWidget {
  const _CampaignPerformanceTable({required this.rows, required this.currency});

  final List<CampaignPerformance> rows;
  final CurrencyCode currency;

  @override
  State<_CampaignPerformanceTable> createState() =>
      _CampaignPerformanceTableState();
}

class _CampaignPerformanceTableState extends State<_CampaignPerformanceTable> {
  String _campaignSearch = '';

  @override
  Widget build(BuildContext context) {
    final currency = widget.currency;
    final sorted = [...widget.rows]
      ..sort((a, b) => b.spend.minor.compareTo(a.spend.minor));
    final top = sorted.take(10).toList();

    return SectionCard(
      title: 'Campaign Performance',
      subtitle: 'Spend and return by campaign',
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            child: SearchField(
              hintText: 'Search campaigns by name or platform…',
              onChanged: (v) => setState(() => _campaignSearch = v),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppDataTable<CampaignPerformance>(
            rows: top,
            rowsPerPage: 10,
            searchText: _campaignSearch,
            searchableText: (c) =>
                '${c.campaign.name} ${c.campaign.platform.label}',
            emptyTitle: 'No campaign activity',
            emptyMessage: 'Campaigns with spend will appear here.',
            columns: [
              AppColumn(
                label: 'Campaign',
                cell: (c) => Text(c.campaign.name,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                sortValue: (c) => c.campaign.name.toLowerCase(),
              ),
              AppColumn(
                label: 'Platform',
                cell: (c) => StatusBadge(
                  label: c.campaign.platform.label,
                  tone: BadgeTone.info,
                ),
                sortValue: (c) => c.campaign.platform.label,
              ),
              AppColumn(
                label: 'Spend',
                numeric: true,
                cell: (c) => CurrencyText(c.spend, currency: currency),
                sortValue: (c) => c.spend.minor,
              ),
              AppColumn(
                label: 'Clicks',
                numeric: true,
                cell: (c) => Text('${c.campaign.clicks}'),
                sortValue: (c) => c.campaign.clicks,
              ),
              AppColumn(
                label: 'Conversions',
                numeric: true,
                cell: (c) => Text('${c.campaign.conversions}'),
                sortValue: (c) => c.campaign.conversions,
              ),
              AppColumn(
                label: 'Revenue',
                numeric: true,
                cell: (c) =>
                    CurrencyText(c.attributedRevenue, currency: currency),
                sortValue: (c) => c.attributedRevenue.minor,
              ),
              AppColumn(
                label: 'ROI',
                numeric: true,
                cell: (c) => Text(c.roi == null
                    ? 'N/A'
                    : PercentFormatter.format(c.roi!)),
                sortValue: (c) => c.roi ?? -1,
              ),
              AppColumn(
                label: 'ROAS',
                numeric: true,
                cell: (c) => Text(PercentFormatter.roas(c.roas)),
                sortValue: (c) => c.roas ?? -1,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
