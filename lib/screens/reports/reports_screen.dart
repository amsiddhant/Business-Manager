import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/enums.dart';
import '../../core/permissions.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_x.dart';
import '../../core/utils/csv_export.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/money.dart';
import '../../models/business.dart';
import '../../models/campaign.dart';
import '../../models/expense.dart';
import '../../models/order.dart';
import '../../models/product.dart';
import '../../services/profit_calculation_service.dart';
import '../../services/summaries/reports_summaries.dart';
import '../../state/app_state.dart';
import '../../state/data_controller.dart';
import '../../state/filter_controller.dart';
import '../../widgets/common/confirm_dialog.dart';
import '../../widgets/common/page_header.dart';
import '../../widgets/common/state_views.dart';
import '../../widgets/common/status_badge.dart';
import '../../widgets/data/app_data_grid.dart';
import '../../widgets/layout/app_page.dart';
import '../../widgets/layout/kpi_strip.dart';

/// Reporting hub. Presents five tabular reports (Sales, Expenses, Marketing,
/// Product Profitability, Business Profitability) scoped to the global business
/// and period filters. Each tab has its own search, filters and sort, and its
/// CSV export (when the user has [Permission.exportData]) contains exactly the
/// rows that tab is showing.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, this.initialTab});

  /// The tab to open, by key (`/reports?tab=marketing`): one of [tabKeys].
  final String? initialTab;

  static const tabKeys = [
    'sales',
    'expenses',
    'marketing',
    'products',
    'business',
  ];

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen>
    with SingleTickerProviderStateMixin {
  static const _service = ProfitCalculationService();
  late final TabController _tabs;

  /// One grid controller per tab, so each report keeps its own search,
  /// filters, sort and page while the user looks at another one.
  late final List<GridController> _grids;

  static const _reports = [
    'Sales',
    'Expenses',
    'Marketing',
    'Product Profitability',
    'Business Profitability',
  ];

  static const _tabIcons = [
    Icons.receipt_long_outlined,
    Icons.payments_outlined,
    Icons.campaign_outlined,
    Icons.inventory_2_outlined,
    Icons.storefront_outlined,
  ];

  static int _indexOf(String? key) {
    final i = ReportsScreen.tabKeys.indexOf(key ?? '');
    return i < 0 ? 0 : i;
  }

  @override
  void initState() {
    super.initState();
    _grids = [
      GridController(
          sorts: const [GridSort('date', ascending: false)], pageSize: 50),
      GridController(
          sorts: const [GridSort('annualised', ascending: false)],
          pageSize: 50),
      GridController(
          sorts: const [GridSort('spend', ascending: false)], pageSize: 50),
      GridController(
          sorts: const [GridSort('revenue', ascending: false)], pageSize: 50),
      GridController(
          sorts: const [GridSort('revenue', ascending: false)], pageSize: 50),
    ];
    _tabs = TabController(
        length: _reports.length,
        vsync: this,
        initialIndex: _indexOf(widget.initialTab));
    _tabs.addListener(() {
      if (_tabs.indexIsChanging) return;
      setState(() {});
      // Keep the address in step, so a link to the tab the user just left
      // (the same KPI tapped twice) still switches back to it.
      final key = ReportsScreen.tabKeys[_tabs.index];
      if (widget.initialTab != null && key != widget.initialTab) {
        GoRouter.maybeOf(context)?.go(Routes.reportsTab(key));
      }
    });
  }

  @override
  void didUpdateWidget(ReportsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTab != oldWidget.initialTab &&
        widget.initialTab != null) {
      final i = _indexOf(widget.initialTab);
      if (i != _tabs.index) _tabs.animateTo(i);
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    for (final g in _grids) {
      g.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataController>();
    final filter = context.watch<FilterController>();
    final appState = context.watch<AppState>();
    final user = appState.currentUser;

    if (data.loading && !data.loaded) {
      return const AppPage(children: [
        PageHeader(title: 'Reports', icon: Icons.assessment_outlined),
        SizedBox(height: 48),
        LoadingView(),
      ]);
    }
    if (data.error != null && !data.loaded) {
      return AppPage(children: [
        const PageHeader(title: 'Reports', icon: Icons.assessment_outlined),
        const SizedBox(height: 48),
        ErrorView(message: data.error!, onRetry: () => data.refresh()),
      ]);
    }

    final bizId = filter.selectedBusinessId;
    final range = filter.range;
    final canExport = user?.can(Permission.exportData) ?? false;

    final orders = data.ordersFor(bizId);
    final campaigns = data.campaignsFor(bizId);
    final expenses = data.expensesFor(bizId);
    final products = data.productsFor(bizId);
    // Figures follow the selected business's currency; INR for all.
    final currency =
        data.businessById(bizId ?? '')?.currency ?? CurrencyCode.inr;
    CurrencyCode currencyOf(String businessId) =>
        data.businessById(businessId)?.currency ?? currency;

    final active = _tabs.index;
    final ctx = _Ctx(
      tokens: context.tokens,
      currency: currency,
      currencyOf: currencyOf,
      range: range,
    );
    final report = _buildReport(
      index: active,
      ctx: ctx,
      data: data,
      bizId: bizId,
      orders: orders,
      campaigns: campaigns,
      expenses: expenses,
      products: products,
    );

    return AppPage.slivers(
      slivers: [
        SliverToBoxAdapter(
          child: PageHeader(
            title: 'Reports',
            icon: Icons.assessment_outlined,
            subtitle: '${_reports[active]} · ${filter.periodLabel}',
            actions: [
              OutlinedButton.icon(
                onPressed: canExport && report.total > 0
                    ? () => _export(report)
                    : null,
                icon: const Icon(Icons.download, size: 18),
                label: const Text('Export CSV'),
              ),
            ],
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
        SliverToBoxAdapter(
          child: _ReportTabs(
              controller: _tabs, labels: _reports, icons: _tabIcons),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
        if (report.kpis.isNotEmpty) ...[
          SliverToBoxAdapter(child: KpiStrip(items: report.kpis)),
          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
        ],
        report.grid(canExport),
      ],
    );
  }

  void _export(_Report report) {
    final period = context.read<FilterController>().periodLabel;
    final safePeriod = period.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-');
    final csv = report.csv();
    CsvExport.download(
      filename: '${report.slug}-$safePeriod',
      header: csv.first,
      rows: csv.skip(1).toList(),
    );
    showSuccessSnack(
        context,
        'Report exported (${csv.length - 1} '
        'row${csv.length == 2 ? '' : 's'})');
  }

  _Report _buildReport({
    required int index,
    required _Ctx ctx,
    required DataController data,
    required String? bizId,
    required List<Order> orders,
    required List<Campaign> campaigns,
    required List<Expense> expenses,
    required List<Product> products,
  }) {
    switch (index) {
      case 0:
        return _salesReport(ctx, orders);
      case 1:
        return _expenseReport(ctx, expenses);
      case 2:
        return _marketingReport(ctx, campaigns, orders);
      case 3:
        return _productReport(ctx, products, orders, campaigns);
      case 4:
      default:
        return _businessReport(ctx, data, bizId);
    }
  }

  // ---- Sales ----------------------------------------------------------------

  _Report _salesReport(_Ctx c, List<Order> orders) {
    final rows = _service.recognisedOrdersIn(orders, c.range);
    final s = _service.summariseOrders(rows);
    final margin = s.grossMargin;
    final t = c.tokens;
    String money(Money m) => MoneyFormatter.format(m, c.currency);
    return _TypedReport<Order>(
      slug: 'sales-report',
      controller: _grids[0],
      rows: rows,
      rowKey: (o) => o.id,
      title: 'Sales Report',
      subtitle: '${rows.length} recognised orders',
      searchHint: 'Search sales by order ID, product or status…',
      searchText: (o) => '${o.id} ${o.productName} ${o.status.label}',
      emptyTitle: 'No sales in this period',
      emptyIcon: Icons.receipt_long_outlined,
      kpis: [
        KpiItem(
          label: 'Revenue',
          value: MoneyFormatter.compact(s.revenue, c.currency),
          icon: Icons.trending_up,
          caption: 'Net of refunds',
          tooltip: 'Recognised revenue of the orders in this period.',
        ),
        KpiItem(
          label: 'Gross profit',
          value: MoneyFormatter.compact(s.grossProfit, c.currency),
          icon: Icons.savings_outlined,
          tone: s.grossProfit.isNegative ? t.error : t.success,
          caption:
              margin == null ? null : '${margin.toStringAsFixed(1)}% margin',
        ),
        KpiItem(
          label: 'Orders',
          value: '${s.recognisedCount}',
          icon: Icons.receipt_long_outlined,
          caption: '${s.units} units sold',
        ),
        KpiItem(
          label: 'Avg. order value',
          value: MoneyFormatter.compact(s.averageOrderValue, c.currency),
          icon: Icons.shopping_bag_outlined,
          tooltip: 'Revenue ÷ recognised orders.',
        ),
        KpiItem(
          label: 'Refunds',
          value: MoneyFormatter.compact(s.refunds, c.currency),
          icon: Icons.assignment_return_outlined,
          tone: s.refunds.isPositive ? t.warning : null,
          caption: '${s.refundedCount} returned',
        ),
      ],
      quickFilters: [
        for (final st in OrderStatus.values)
          if (st.contributesToRevenue)
            GridQuickFilter<Order>(
              id: st.wire,
              label: st.label,
              test: (o) => o.status == st,
            ),
      ],
      columns: [
        GridColumn<Order>(
          id: 'id',
          label: 'Order ID',
          pinned: true,
          minWidth: 110,
          cardRole: CardRole.subtitle,
          cell: (o) => Text(o.id,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          sortValue: (o) => o.id,
          exportValue: (o) => o.id,
        ),
        GridColumn<Order>(
          id: 'date',
          label: 'Date',
          minWidth: 110,
          cardRole: CardRole.meta,
          cell: (o) => Text(AppDate.format(o.orderDate)),
          sortValue: (o) => o.orderDate?.millisecondsSinceEpoch ?? 0,
          exportValue: (o) => AppDate.format(o.orderDate),
          filter: GridFilter.dateRange((o) => o.orderDate),
        ),
        GridColumn<Order>(
          id: 'product',
          label: 'Product',
          flex: 2,
          cardRole: CardRole.title,
          cell: (o) =>
              Text(o.productName, maxLines: 1, overflow: TextOverflow.ellipsis),
          sortValue: (o) => o.productName.toLowerCase(),
          exportValue: (o) => o.productName,
          filter: GridFilter.choice((o) => o.productName),
        ),
        GridColumn<Order>(
          id: 'qty',
          label: 'Quantity',
          numeric: true,
          minWidth: 80,
          cardRole: CardRole.meta,
          cell: (o) => Text('${o.quantity}'),
          sortValue: (o) => o.quantity,
          exportValue: (o) => '${o.quantity}',
          footer: (r) => '${_service.unitsSoldOf(r)}',
        ),
        _money<Order>(
          id: 'gross',
          label: 'Gross Revenue',
          visible: false,
          role: CardRole.hidden,
          ctx: c,
          currencyOf: (o) => c.currencyOf(o.businessId),
          value: (o) => o.totalRevenue,
        ),
        _money<Order>(
          id: 'revenue',
          label: 'Revenue',
          tooltip: 'Recognised revenue, net of any refund',
          role: CardRole.metric,
          ctx: c,
          currencyOf: (o) => c.currencyOf(o.businessId),
          value: (o) => o.recognisedRevenue,
          filter: true,
          footer: (r) => money(_service.revenueOf(r)),
        ),
        _money<Order>(
          id: 'refund',
          label: 'Refund',
          role: CardRole.meta,
          ctx: c,
          currencyOf: (o) => c.currencyOf(o.businessId),
          value: (o) => o.effectiveRefund,
          dashWhenZero: true,
          footer: (r) => money(_service.summariseOrders(r).refunds),
        ),
        _money<Order>(
          id: 'cost',
          label: 'Cost',
          tooltip: 'Product cost of the recognised units',
          role: CardRole.metric,
          ctx: c,
          currencyOf: (o) => c.currencyOf(o.businessId),
          value: (o) => o.recognisedProductCost,
          footer: (r) => money(_service.productCostOf(r)),
        ),
        _money<Order>(
          id: 'profit',
          label: 'Gross Profit',
          role: CardRole.metric,
          ctx: c,
          currencyOf: (o) => c.currencyOf(o.businessId),
          value: (o) => o.recognisedGrossProfit,
          filter: true,
          tone: true,
          footer: (r) => money(_service.summariseOrders(r).grossProfit),
        ),
        GridColumn<Order>(
          id: 'status',
          label: 'Status',
          minWidth: 120,
          cardRole: CardRole.badge,
          cell: (o) => StatusBadge.order(o.status),
          sortValue: (o) => o.status.label,
          exportValue: (o) => o.status.label,
          filter: GridFilter.choice((o) => o.status.label, options: [
            for (final st in OrderStatus.values)
              if (st.contributesToRevenue) st.label,
          ]),
        ),
      ],
    );
  }

  // ---- Expenses -------------------------------------------------------------

  _Report _expenseReport(_Ctx c, List<Expense> expenses) {
    final rows = [...expenses];
    final totals = _service.expenseReportTotals(rows, c.range);
    String money(Money m) => MoneyFormatter.format(m, c.currency);
    return _TypedReport<Expense>(
      slug: 'expense-report',
      controller: _grids[1],
      rows: rows,
      rowKey: (e) => e.id,
      title: 'Expense Report',
      subtitle: '${rows.length} expenses · prorated to period',
      searchHint: 'Search expenses by name, category, frequency or status…',
      searchText: (e) =>
          '${e.name} ${e.category.label} ${e.frequency.label} ${e.status.label}',
      emptyTitle: 'No expenses in this period',
      emptyIcon: Icons.payments_outlined,
      kpis: [
        KpiItem(
          label: 'In this period',
          value: MoneyFormatter.compact(totals.inPeriod, c.currency),
          icon: Icons.event_note_outlined,
          caption: 'Prorated to the period',
          tooltip: 'What these expenses cost within the selected period.',
        ),
        KpiItem(
          label: 'Annualised',
          value: MoneyFormatter.compact(totals.annualised, c.currency),
          icon: Icons.calendar_month_outlined,
          tooltip: 'Every expense expressed as a yearly figure.',
        ),
        KpiItem(
          label: 'Monthly run rate',
          value: MoneyFormatter.compact(totals.monthlyRunRate, c.currency),
          icon: Icons.speed_outlined,
          caption: 'Annualised ÷ 12',
        ),
        KpiItem(
          label: 'Expenses',
          value: '${totals.count}',
          icon: Icons.receipt_outlined,
          caption: '${totals.activeCount} active',
        ),
      ],
      quickFilters: [
        for (final st in EntityStatus.values)
          GridQuickFilter<Expense>(
            id: st.wire,
            label: st.label,
            test: (e) => e.status == st,
          ),
      ],
      columns: [
        GridColumn<Expense>(
          id: 'name',
          label: 'Expense',
          pinned: true,
          flex: 2,
          cardRole: CardRole.title,
          cell: (e) => Text(e.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          sortValue: (e) => e.name.toLowerCase(),
          exportValue: (e) => e.name,
        ),
        GridColumn<Expense>(
          id: 'category',
          label: 'Category',
          cardRole: CardRole.subtitle,
          cell: (e) => Text(e.category.label),
          sortValue: (e) => e.category.label,
          exportValue: (e) => e.category.label,
          filter: GridFilter.choice((e) => e.category.label),
        ),
        GridColumn<Expense>(
          id: 'frequency',
          label: 'Frequency',
          cardRole: CardRole.meta,
          cell: (e) => Text(e.frequency.label),
          sortValue: (e) => e.frequency.label,
          exportValue: (e) => e.frequency.label,
          filter: GridFilter.choice((e) => e.frequency.label),
        ),
        _money<Expense>(
          id: 'amount',
          label: 'Amount',
          role: CardRole.metric,
          ctx: c,
          currencyOf: (e) => c.currencyOf(e.businessId),
          value: (e) => e.amount,
          filter: true,
        ),
        _money<Expense>(
          id: 'annualised',
          label: 'Annualised',
          role: CardRole.metric,
          ctx: c,
          currencyOf: (e) => c.currencyOf(e.businessId),
          value: (e) => e.annualisedAmount,
          footer: (r) => money(_service.expenseReportTotals(r, c.range).annualised),
        ),
        _money<Expense>(
          id: 'period',
          label: 'In-Period',
          role: CardRole.metric,
          ctx: c,
          currencyOf: (e) => c.currencyOf(e.businessId),
          value: (e) => _service.proratedExpense(e, c.range),
          footer: (r) => money(_service.expenseReportTotals(r, c.range).inPeriod),
        ),
        GridColumn<Expense>(
          id: 'status',
          label: 'Status',
          minWidth: 110,
          cardRole: CardRole.badge,
          cell: (e) => StatusBadge.entity(e.status),
          sortValue: (e) => e.status.label,
          exportValue: (e) => e.status.label,
          filter: GridFilter.choice((e) => e.status.label,
              options: [for (final st in EntityStatus.values) st.label]),
        ),
      ],
    );
  }

  // ---- Marketing ------------------------------------------------------------

  _Report _marketingReport(
      _Ctx c, List<Campaign> campaigns, List<Order> orders) {
    final rows = _service.campaignPerformance(
      campaigns: campaigns,
      orders: orders,
      range: c.range,
    );
    final totals = _service.marketingReportTotals(rows);
    String money(Money m) => MoneyFormatter.format(m, c.currency);
    final roi = totals.roi;
    final rate = totals.conversionRate;
    return _TypedReport<CampaignPerformance>(
      slug: 'marketing-report',
      controller: _grids[2],
      rows: rows,
      rowKey: (p) => p.campaign.id,
      title: 'Marketing Report',
      subtitle: '${rows.length} campaigns',
      searchHint: 'Search campaigns by name or platform…',
      searchText: (p) => '${p.campaign.name} ${p.campaign.platform.label}',
      emptyTitle: 'No campaigns in this period',
      emptyIcon: Icons.campaign_outlined,
      kpis: [
        KpiItem(
          label: 'Spend',
          value: MoneyFormatter.compact(totals.spend, c.currency),
          icon: Icons.account_balance_wallet_outlined,
          caption: '${totals.count} campaigns',
        ),
        KpiItem(
          label: 'Attributed revenue',
          value: MoneyFormatter.compact(totals.attributedRevenue, c.currency),
          icon: Icons.trending_up,
          tooltip: 'Revenue of each campaign\'s product in the period, split '
              'by spend when several campaigns share a product.',
        ),
        KpiItem(
          label: 'ROAS',
          value: PercentFormatter.roas(totals.roas),
          icon: Icons.bolt_outlined,
          tone: totals.roas == null
              ? null
              : totals.roas! >= 1
                  ? c.tokens.success
                  : c.tokens.error,
          tooltip: 'Attributed revenue ÷ spend.',
        ),
        KpiItem(
          label: 'ROI',
          value: PercentFormatter.format(roi ?? double.nan),
          icon: Icons.percent,
          tone: roi == null
              ? null
              : roi >= 0
                  ? c.tokens.success
                  : c.tokens.error,
          tooltip: '(Attributed revenue − spend) ÷ spend.',
        ),
        KpiItem(
          label: 'Clicks',
          value: '${totals.clicks}',
          icon: Icons.ads_click_outlined,
          caption: '${totals.conversions} conversions',
        ),
        KpiItem(
          label: 'Conversion rate',
          value: rate == null ? '—' : PercentFormatter.format(rate),
          icon: Icons.published_with_changes_outlined,
          tooltip: 'Conversions ÷ clicks.',
        ),
      ],
      quickFilters: [
        GridQuickFilter<CampaignPerformance>(
          id: 'profitable',
          label: 'Profitable',
          test: (p) => (p.roas ?? 0) >= 1,
        ),
        GridQuickFilter<CampaignPerformance>(
          id: 'losing',
          label: 'Losing money',
          test: (p) => p.roas != null && p.roas! < 1,
        ),
      ],
      columns: [
        GridColumn<CampaignPerformance>(
          id: 'campaign',
          label: 'Campaign',
          pinned: true,
          flex: 2,
          cardRole: CardRole.title,
          cell: (p) => Text(p.campaign.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          sortValue: (p) => p.campaign.name.toLowerCase(),
          exportValue: (p) => p.campaign.name,
        ),
        GridColumn<CampaignPerformance>(
          id: 'platform',
          label: 'Platform',
          minWidth: 120,
          cardRole: CardRole.badge,
          cell: (p) => StatusBadge(
              label: p.campaign.platform.label, tone: BadgeTone.info),
          sortValue: (p) => p.campaign.platform.label,
          exportValue: (p) => p.campaign.platform.label,
          filter: GridFilter.choice((p) => p.campaign.platform.label),
        ),
        _money<CampaignPerformance>(
          id: 'spend',
          label: 'Spend',
          role: CardRole.metric,
          ctx: c,
          currencyOf: (p) => c.currencyOf(p.campaign.businessId),
          value: (p) => p.spend,
          filter: true,
          footer: (r) => money(_service.marketingReportTotals(r).spend),
        ),
        GridColumn<CampaignPerformance>(
          id: 'clicks',
          label: 'Clicks',
          numeric: true,
          minWidth: 80,
          cardRole: CardRole.meta,
          cell: (p) => Text('${p.campaign.clicks}'),
          sortValue: (p) => p.campaign.clicks,
          exportValue: (p) => '${p.campaign.clicks}',
          footer: (r) => '${_service.marketingReportTotals(r).clicks}',
        ),
        GridColumn<CampaignPerformance>(
          id: 'conversions',
          label: 'Conversions',
          numeric: true,
          minWidth: 100,
          cardRole: CardRole.meta,
          cell: (p) => Text('${p.campaign.conversions}'),
          sortValue: (p) => p.campaign.conversions,
          exportValue: (p) => '${p.campaign.conversions}',
          footer: (r) => '${_service.marketingReportTotals(r).conversions}',
        ),
        _money<CampaignPerformance>(
          id: 'revenue',
          label: 'Attr. Revenue',
          role: CardRole.metric,
          ctx: c,
          currencyOf: (p) => c.currencyOf(p.campaign.businessId),
          value: (p) => p.attributedRevenue,
          footer: (r) =>
              money(_service.marketingReportTotals(r).attributedRevenue),
        ),
        GridColumn<CampaignPerformance>(
          id: 'roi',
          label: 'ROI %',
          numeric: true,
          minWidth: 90,
          cardRole: CardRole.metric,
          cell: (p) => Text(PercentFormatter.format(p.roi ?? double.nan)),
          sortValue: (p) => p.roi ?? -1e9,
          exportValue: (p) => p.roi == null ? 'N/A' : p.roi!.toStringAsFixed(1),
          footer: (r) => PercentFormatter.format(
              _service.marketingReportTotals(r).roi ?? double.nan),
        ),
        GridColumn<CampaignPerformance>(
          id: 'roas',
          label: 'ROAS',
          numeric: true,
          minWidth: 90,
          cardRole: CardRole.meta,
          cell: (p) => Text(PercentFormatter.roas(p.roas)),
          sortValue: (p) => p.roas ?? -1,
          exportValue: (p) =>
              p.roas == null ? 'N/A' : p.roas!.toStringAsFixed(2),
          footer: (r) =>
              PercentFormatter.roas(_service.marketingReportTotals(r).roas),
        ),
      ],
    );
  }

  // ---- Product profitability ------------------------------------------------

  _Report _productReport(_Ctx c, List<Product> products, List<Order> orders,
      List<Campaign> campaigns) {
    final rows = _service.productProfitability(
      products: products,
      orders: orders,
      campaigns: campaigns,
      range: c.range,
    );
    final totals = _service.productReportTotals(rows);
    final t = c.tokens;
    String money(Money m) => MoneyFormatter.format(m, c.currency);
    return _TypedReport<ProductProfit>(
      slug: 'product-profitability',
      controller: _grids[3],
      rows: rows,
      rowKey: (p) => p.product.id,
      title: 'Product Profitability',
      subtitle: '${rows.length} products',
      searchHint: 'Search products by ID or name…',
      searchText: (p) => '${p.product.id} ${p.product.name}',
      emptyTitle: 'No products to report',
      emptyIcon: Icons.inventory_2_outlined,
      kpis: [
        KpiItem(
          label: 'Revenue',
          value: MoneyFormatter.compact(totals.revenue, c.currency),
          icon: Icons.trending_up,
          caption: '${totals.orders} orders',
        ),
        KpiItem(
          label: 'Net profit',
          value: MoneyFormatter.compact(totals.netProfit, c.currency),
          icon: Icons.savings_outlined,
          tone: totals.netProfit.isNegative ? t.error : t.success,
          caption: '${PercentFormatter.format(totals.margin)} margin',
          tooltip: 'Revenue − product cost − marketing, per product.',
        ),
        KpiItem(
          label: 'Units sold',
          value: '${totals.units}',
          icon: Icons.inventory_outlined,
        ),
        KpiItem(
          label: 'Products selling',
          value: '${totals.sellingCount}',
          icon: Icons.sell_outlined,
          caption: 'of ${totals.count} products',
        ),
        KpiItem(
          label: 'Marketing',
          value: MoneyFormatter.compact(totals.marketingCost, c.currency),
          icon: Icons.campaign_outlined,
          caption: 'Charged to products',
        ),
      ],
      quickFilters: [
        GridQuickFilter<ProductProfit>(
          id: 'selling',
          label: 'With sales',
          test: (p) => p.orderCount > 0,
        ),
        GridQuickFilter<ProductProfit>(
          id: 'unsold',
          label: 'No sales',
          test: (p) => p.orderCount == 0,
        ),
        GridQuickFilter<ProductProfit>(
          id: 'loss',
          label: 'Loss-making',
          test: (p) => p.netProfit.isNegative,
        ),
      ],
      columns: [
        GridColumn<ProductProfit>(
          id: 'product',
          label: 'Product',
          pinned: true,
          flex: 2,
          cardRole: CardRole.title,
          cell: (p) => Text(p.product.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          sortValue: (p) => p.product.name.toLowerCase(),
          exportValue: (p) => p.product.name,
        ),
        GridColumn<ProductProfit>(
          id: 'orders',
          label: 'Orders',
          numeric: true,
          minWidth: 80,
          cardRole: CardRole.meta,
          cell: (p) => Text('${p.orderCount}'),
          sortValue: (p) => p.orderCount,
          exportValue: (p) => '${p.orderCount}',
          footer: (r) => '${_service.productReportTotals(r).orders}',
        ),
        GridColumn<ProductProfit>(
          id: 'units',
          label: 'Units',
          numeric: true,
          minWidth: 80,
          cardRole: CardRole.meta,
          cell: (p) => Text('${p.unitsSold}'),
          sortValue: (p) => p.unitsSold,
          exportValue: (p) => '${p.unitsSold}',
          footer: (r) => '${_service.productReportTotals(r).units}',
        ),
        _money<ProductProfit>(
          id: 'revenue',
          label: 'Revenue',
          role: CardRole.metric,
          ctx: c,
          currencyOf: (p) => c.currencyOf(p.product.businessId),
          value: (p) => p.revenue,
          filter: true,
          footer: (r) => money(_service.productReportTotals(r).revenue),
        ),
        _money<ProductProfit>(
          id: 'cost',
          label: 'Product Cost',
          role: CardRole.meta,
          ctx: c,
          currencyOf: (p) => c.currencyOf(p.product.businessId),
          value: (p) => p.productCost,
          footer: (r) => money(_service.productReportTotals(r).productCost),
        ),
        _money<ProductProfit>(
          id: 'marketing',
          label: 'Marketing',
          role: CardRole.meta,
          ctx: c,
          currencyOf: (p) => c.currencyOf(p.product.businessId),
          value: (p) => p.marketingCost,
          footer: (r) => money(_service.productReportTotals(r).marketingCost),
        ),
        _money<ProductProfit>(
          id: 'gross',
          label: 'Gross Profit',
          visible: false,
          role: CardRole.hidden,
          ctx: c,
          currencyOf: (p) => c.currencyOf(p.product.businessId),
          value: (p) => p.grossProfit,
          tone: true,
        ),
        _money<ProductProfit>(
          id: 'net',
          label: 'Net Profit',
          role: CardRole.metric,
          ctx: c,
          currencyOf: (p) => c.currencyOf(p.product.businessId),
          value: (p) => p.netProfit,
          filter: true,
          tone: true,
          footer: (r) => money(_service.productReportTotals(r).netProfit),
        ),
        GridColumn<ProductProfit>(
          id: 'margin',
          label: 'Margin %',
          numeric: true,
          minWidth: 90,
          cardRole: CardRole.metric,
          cell: (p) => Text(PercentFormatter.format(p.margin)),
          sortValue: (p) => p.margin,
          exportValue: (p) => p.margin.toStringAsFixed(1),
          footer: (r) =>
              PercentFormatter.format(_service.productReportTotals(r).margin),
        ),
      ],
    );
  }

  // ---- Business profitability -----------------------------------------------

  _Report _businessReport(_Ctx c, DataController data, String? bizId) {
    // One row per accessible business (or the single selected one).
    final businesses = bizId == null
        ? data.selectableBusinesses
        : [data.businessById(bizId)].whereType<Business>().toList();

    final rows = [
      for (final b in businesses)
        _BusinessRow(
          business: b,
          summary: _service.summarise(
            orders: data.ordersFor(b.id),
            campaigns: data.campaignsFor(b.id),
            expenses: data.expensesFor(b.id),
            range: c.range,
          ),
        ),
    ];

    // Totals only make sense when every business reports in one currency.
    final currencies = {for (final r in rows) r.business.currency};
    final single = currencies.length <= 1;
    final unit = single && rows.isNotEmpty ? currencies.first : c.currency;
    final totals = _service.sumProfitSummaries([for (final r in rows) r.summary]);
    String money(Money m) => MoneyFormatter.format(m, unit);
    String? sum(List<_BusinessRow> r, Money Function(ProfitSummary s) pick) =>
        single
            ? money(pick(_service.sumProfitSummaries([for (final x in r) x.summary])))
            : null;

    final profitable = rows.where((r) => !r.summary.netProfit.isNegative).length;
    final best = rows.isEmpty
        ? null
        : rows.reduce((a, b) =>
            b.summary.netProfit.minor > a.summary.netProfit.minor ? b : a);
    final t = c.tokens;
    return _TypedReport<_BusinessRow>(
      slug: 'business-profitability',
      controller: _grids[4],
      rows: rows,
      rowKey: (r) => r.business.id,
      title: 'Business Profitability',
      subtitle: '${rows.length} businesses',
      searchHint: 'Search businesses by name or currency…',
      searchText: (r) =>
          '${r.business.id} ${r.business.name} ${r.business.currency.wire}',
      emptyTitle: 'No businesses to report',
      emptyIcon: Icons.storefront_outlined,
      kpis: [
        KpiItem(
          label: 'Businesses',
          value: '${rows.length}',
          icon: Icons.storefront_outlined,
          caption: '$profitable profitable',
        ),
        if (single) ...[
          KpiItem(
            label: 'Revenue',
            value: MoneyFormatter.compact(totals.revenue, unit),
            icon: Icons.trending_up,
            caption: '${totals.orderCount} orders',
          ),
          KpiItem(
            label: 'Net profit',
            value: MoneyFormatter.compact(totals.netProfit, unit),
            icon: Icons.savings_outlined,
            tone: totals.netProfit.isNegative ? t.error : t.success,
            caption: '${PercentFormatter.format(totals.netMargin)} margin',
            tooltip: 'Revenue − product cost − marketing − operating expenses.',
          ),
        ] else
          KpiItem(
            label: 'Currencies',
            value: '${currencies.length}',
            icon: Icons.currency_exchange,
            caption: 'Totals shown per business',
            tooltip: 'These businesses report in different currencies, so '
                'their figures are not added together.',
          ),
        if (best != null)
          KpiItem(
            label: 'Top performer',
            value: best.business.name,
            icon: Icons.emoji_events_outlined,
            caption: MoneyFormatter.compact(
                best.summary.netProfit, best.business.currency),
            tooltip: 'The business with the highest net profit.',
          ),
      ],
      quickFilters: [
        GridQuickFilter<_BusinessRow>(
          id: 'profitable',
          label: 'Profitable',
          test: (r) => !r.summary.netProfit.isNegative,
        ),
        GridQuickFilter<_BusinessRow>(
          id: 'loss',
          label: 'Loss-making',
          test: (r) => r.summary.netProfit.isNegative,
        ),
      ],
      columns: [
        GridColumn<_BusinessRow>(
          id: 'business',
          label: 'Business',
          pinned: true,
          flex: 2,
          cardRole: CardRole.title,
          cell: (r) => Text(r.business.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          sortValue: (r) => r.business.name.toLowerCase(),
          exportValue: (r) => r.business.name,
        ),
        GridColumn<_BusinessRow>(
          id: 'currency',
          label: 'Currency',
          minWidth: 90,
          cardRole: CardRole.subtitle,
          cell: (r) => Text(r.business.currency.wire),
          sortValue: (r) => r.business.currency.wire,
          exportValue: (r) => r.business.currency.wire,
          filter: GridFilter.choice((r) => r.business.currency.wire),
        ),
        _money<_BusinessRow>(
          id: 'revenue',
          label: 'Revenue',
          role: CardRole.metric,
          ctx: c,
          currencyOf: (r) => r.business.currency,
          value: (r) => r.summary.revenue,
          filter: true,
          footer: (r) => sum(r, (s) => s.revenue),
        ),
        _money<_BusinessRow>(
          id: 'cost',
          label: 'Product Cost',
          role: CardRole.meta,
          ctx: c,
          currencyOf: (r) => r.business.currency,
          value: (r) => r.summary.productCost,
          footer: (r) => sum(r, (s) => s.productCost),
        ),
        _money<_BusinessRow>(
          id: 'marketing',
          label: 'Marketing',
          role: CardRole.meta,
          ctx: c,
          currencyOf: (r) => r.business.currency,
          value: (r) => r.summary.marketingCost,
          footer: (r) => sum(r, (s) => s.marketingCost),
        ),
        _money<_BusinessRow>(
          id: 'opex',
          label: 'Operating Expenses',
          role: CardRole.meta,
          ctx: c,
          currencyOf: (r) => r.business.currency,
          value: (r) => r.summary.operatingExpenses,
          footer: (r) => sum(r, (s) => s.operatingExpenses),
        ),
        _money<_BusinessRow>(
          id: 'gross',
          label: 'Gross Profit',
          role: CardRole.metric,
          ctx: c,
          currencyOf: (r) => r.business.currency,
          value: (r) => r.summary.grossProfit,
          footer: (r) => sum(r, (s) => s.grossProfit),
        ),
        _money<_BusinessRow>(
          id: 'net',
          label: 'Net Profit',
          role: CardRole.metric,
          ctx: c,
          currencyOf: (r) => r.business.currency,
          value: (r) => r.summary.netProfit,
          filter: true,
          tone: true,
          footer: (r) => sum(r, (s) => s.netProfit),
        ),
        GridColumn<_BusinessRow>(
          id: 'margin',
          label: 'Net Margin %',
          numeric: true,
          minWidth: 110,
          cardRole: CardRole.badge,
          cell: (r) => Text(PercentFormatter.format(r.summary.netMargin)),
          sortValue: (r) => r.summary.netMargin,
          exportValue: (r) => r.summary.netMargin.toStringAsFixed(1),
          footer: single
              ? (r) => PercentFormatter.format(_service
                  .sumProfitSummaries([for (final x in r) x.summary]).netMargin)
              : null,
        ),
      ],
    );
  }
}

/// What the report builders share: theme, currency and period.
class _Ctx {
  const _Ctx({
    required this.tokens,
    required this.currency,
    required this.currencyOf,
    required this.range,
  });

  final AppTokens tokens;

  /// The page currency: the selected business's, or INR for all.
  final CurrencyCode currency;

  /// A row's currency from its business.
  final CurrencyCode Function(String businessId) currencyOf;
  final DateRange range;
}

/// A money column: formatted in the row's currency, sorted by amount, exported
/// as a plain figure with two decimals.
GridColumn<T> _money<T>({
  required String id,
  required String label,
  required _Ctx ctx,
  required CurrencyCode Function(T row) currencyOf,
  required Money Function(T row) value,
  required CardRole role,
  String? Function(List<T> rows)? footer,
  String? tooltip,
  bool filter = false,
  bool tone = false,
  bool visible = true,
  bool dashWhenZero = false,
}) {
  return GridColumn<T>(
    id: id,
    label: label,
    numeric: true,
    tooltip: tooltip,
    cardRole: role,
    visibleByDefault: visible,
    minWidth: 112,
    cell: (row) {
      final m = value(row);
      if (dashWhenZero && m.isZero) {
        return Text('—', style: TextStyle(color: ctx.tokens.textTertiary));
      }
      return Text(
        MoneyFormatter.format(m, currencyOf(row)),
        style: tone
            ? TextStyle(
                fontWeight: FontWeight.w600,
                color: m.isNegative ? ctx.tokens.error : ctx.tokens.success)
            : null,
      );
    },
    sortValue: (row) => value(row).minor,
    exportValue: (row) => value(row).major.toStringAsFixed(2),
    filter: filter ? GridFilter.numberRange((row) => value(row).major) : null,
    footer: footer == null
        ? null
        : (rows) => footer(rows) ?? '',
  );
}

class _ReportTabs extends StatelessWidget {
  const _ReportTabs({
    required this.controller,
    required this.labels,
    required this.icons,
  });

  final TabController controller;
  final List<String> labels;
  final List<IconData> icons;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        border: Border.all(color: t.border),
      ),
      child: TabBar(
        controller: controller,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: t.primarySurface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm + 2),
        ),
        splashBorderRadius: BorderRadius.circular(AppSpacing.radiusSm + 2),
        labelColor: t.primary,
        unselectedLabelColor: t.textSecondary,
        labelPadding: const EdgeInsets.symmetric(horizontal: 14),
        labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
        unselectedLabelStyle:
            const TextStyle(fontWeight: FontWeight.w500, fontSize: 13.5),
        tabs: [
          for (var i = 0; i < labels.length; i++)
            Tab(
              height: 38,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icons[i], size: 16),
                  const SizedBox(width: 6),
                  Text(labels[i]),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A report: its headline figures, its grid and the CSV of what the grid is
/// currently showing.
abstract class _Report {
  String get slug;

  /// How many rows the report has before any search or filter.
  int get total;
  List<KpiItem> get kpis;
  Widget grid(bool canExport);

  /// A header and one line per row the tab's search and filters let through.
  List<List<String>> csv();
}

class _TypedReport<T> implements _Report {
  _TypedReport({
    required this.slug,
    required this.controller,
    required this.rows,
    required this.rowKey,
    required this.columns,
    required this.title,
    required this.subtitle,
    required this.searchHint,
    required this.searchText,
    required this.emptyTitle,
    required this.emptyIcon,
    required this.kpis,
    this.quickFilters = const [],
  });

  @override
  final String slug;
  @override
  final List<KpiItem> kpis;

  final GridController controller;
  final List<T> rows;
  final Object Function(T row) rowKey;
  final List<GridColumn<T>> columns;
  final String title;
  final String subtitle;
  final String searchHint;
  final String Function(T row) searchText;
  final String emptyTitle;
  final IconData emptyIcon;
  final List<GridQuickFilter<T>> quickFilters;

  @override
  int get total => rows.length;

  @override
  Widget grid(bool canExport) => SliverAppDataGrid<T>(
        // A grid per tab: its layout is remembered under its own id.
        key: ValueKey(slug),
        gridId: 'reports.$slug',
        controller: controller,
        rows: rows,
        rowKey: rowKey,
        columns: columns,
        title: title,
        subtitle: subtitle,
        searchHint: searchHint,
        searchText: searchText,
        quickFilters: quickFilters,
        exportName: canExport ? slug : null,
        emptyTitle: emptyTitle,
        emptyIcon: emptyIcon,
        pageSize: 50,
      );

  @override
  List<List<String>> csv() {
    final shown = controller
        .apply<T>(rows, columns,
            searchText: searchText, quickFilters: quickFilters)
        .all;
    return gridCsv(columns, shown);
  }
}

class _BusinessRow {
  const _BusinessRow({required this.business, required this.summary});
  final Business business;
  final ProfitSummary summary;
}
