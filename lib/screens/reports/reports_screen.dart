import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/enums.dart';
import '../../core/permissions.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/csv_export.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/money.dart';
import '../../models/business.dart';
import '../../models/campaign.dart';
import '../../models/expense.dart';
import '../../models/order.dart';
import '../../models/product.dart';
import '../../services/profit_calculation_service.dart';
import '../../state/app_state.dart';
import '../../state/data_controller.dart';
import '../../state/filter_controller.dart';
import '../../widgets/common/app_card.dart';
import '../../widgets/common/confirm_dialog.dart';
import '../../widgets/common/data_table_card.dart';
import '../../widgets/common/page_header.dart';
import '../../widgets/common/state_views.dart';
import '../../widgets/common/status_badge.dart';

/// Reporting hub. Presents five tabular reports (Sales, Expenses, Marketing,
/// Product Profitability, Business Profitability) scoped to the global business
/// and period filters, each exportable to CSV when the user has [exportData].
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen>
    with SingleTickerProviderStateMixin {
  static const _service = ProfitCalculationService();
  late final TabController _tabs;

  static const _reports = [
    'Sales',
    'Expenses',
    'Marketing',
    'Product Profitability',
    'Business Profitability',
  ];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _reports.length, vsync: this);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataController>();
    final filter = context.watch<FilterController>();
    final appState = context.watch<AppState>();
    final user = appState.currentUser;

    if (data.loading && !data.loaded) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(title: 'Reports'),
          SizedBox(height: 48),
          LoadingView(),
        ],
      );
    }
    if (data.error != null && !data.loaded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PageHeader(title: 'Reports'),
          const SizedBox(height: 48),
          ErrorView(message: data.error!, onRetry: () => data.refresh()),
        ],
      );
    }

    final bizId = filter.selectedBusinessId;
    final range = filter.range;
    final canExport = user?.can(Permission.exportData) ?? false;

    final orders = data.ordersFor(bizId);
    final campaigns = data.campaignsFor(bizId);
    final expenses = data.expensesFor(bizId);
    final products = data.productsFor(bizId);
    final currency =
        data.businessById(bizId ?? '')?.currency ?? CurrencyCode.inr;

    final active = _tabs.index;
    final report = _buildReport(
      index: active,
      data: data,
      range: range,
      bizId: bizId,
      orders: orders,
      campaigns: campaigns,
      expenses: expenses,
      products: products,
      currency: currency,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: 'Reports',
          subtitle: '${_reports[active]} · ${filter.periodLabel}',
          actions: [
            OutlinedButton.icon(
              onPressed: canExport && report.csvRows.isNotEmpty
                  ? () => _export(report)
                  : null,
              icon: const Icon(Icons.download, size: 18),
              label: const Text('Export CSV'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        _ReportTabs(controller: _tabs, labels: _reports),
        const SizedBox(height: AppSpacing.lg),
        report.body,
      ],
    );
  }

  void _export(_Report report) {
    final period = context.read<FilterController>().periodLabel;
    final safePeriod = period.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-');
    CsvExport.download(
      filename: '${report.slug}-$safePeriod',
      header: report.csvHeader,
      rows: report.csvRows,
    );
    showSuccessSnack(context, 'Report exported');
  }

  _Report _buildReport({
    required int index,
    required DataController data,
    required DateRange range,
    required String? bizId,
    required List<Order> orders,
    required List<Campaign> campaigns,
    required List<Expense> expenses,
    required List<Product> products,
    required CurrencyCode currency,
  }) {
    switch (index) {
      case 0:
        return _salesReport(orders, range, currency);
      case 1:
        return _expenseReport(expenses, range, currency);
      case 2:
        return _marketingReport(campaigns, orders, range, currency);
      case 3:
        return _productReport(
            products, orders, campaigns, range, currency);
      case 4:
      default:
        return _businessReport(data, bizId, orders, campaigns, expenses, range);
    }
  }

  // ---- Sales ----------------------------------------------------------------

  _Report _salesReport(
      List<Order> orders, DateRange range, CurrencyCode currency) {
    final rows = _service.recognisedOrdersIn(orders, range)
      ..sort((a, b) => (b.orderDate ?? range.start)
          .compareTo(a.orderDate ?? range.start));
    return _Report(
      slug: 'sales-report',
      csvHeader: const [
        'Order ID',
        'Date',
        'Product',
        'Quantity',
        'Gross Revenue',
        'Refund',
        'Net Revenue',
        'Product Cost',
        'Gross Profit',
        'Status',
      ],
      csvRows: [
        for (final o in rows)
          [
            o.id,
            AppDate.format(o.orderDate),
            o.productName,
            o.quantity,
            o.totalRevenue.major,
            o.effectiveRefund.major,
            o.recognisedRevenue.major,
            o.recognisedProductCost.major,
            o.recognisedGrossProfit.major,
            o.status.label,
          ],
      ],
      body: SectionCard(
        title: 'Sales Report',
        subtitle: '${rows.length} recognised orders',
        padding: EdgeInsets.zero,
        child: AppDataTable<Order>(
          rows: rows,
          searchableText: (o) => '${o.id} ${o.productName}',
          emptyTitle: 'No sales in this period',
          columns: [
            AppColumn(
                label: 'Order ID',
                cell: (o) => Text(o.id,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                sortValue: (o) => o.id),
            AppColumn(
                label: 'Date',
                cell: (o) => Text(AppDate.format(o.orderDate)),
                sortValue: (o) =>
                    o.orderDate?.millisecondsSinceEpoch ?? 0),
            AppColumn(
                label: 'Product',
                cell: (o) => Text(o.productName),
                sortValue: (o) => o.productName.toLowerCase()),
            AppColumn(
                label: 'Qty',
                numeric: true,
                cell: (o) => Text('${o.quantity}'),
                sortValue: (o) => o.quantity),
            AppColumn(
                label: 'Revenue',
                numeric: true,
                cell: (o) =>
                    Text(MoneyFormatter.format(o.recognisedRevenue, currency)),
                sortValue: (o) => o.recognisedRevenue.minor),
            AppColumn(
                label: 'Refund',
                numeric: true,
                cell: (o) => Text(o.effectiveRefund.isZero
                    ? '—'
                    : MoneyFormatter.format(o.effectiveRefund, currency)),
                sortValue: (o) => o.effectiveRefund.minor),
            AppColumn(
                label: 'Cost',
                numeric: true,
                cell: (o) => Text(
                    MoneyFormatter.format(o.recognisedProductCost, currency)),
                sortValue: (o) => o.recognisedProductCost.minor),
            AppColumn(
                label: 'Gross Profit',
                numeric: true,
                cell: (o) => Text(
                    MoneyFormatter.format(o.recognisedGrossProfit, currency)),
                sortValue: (o) => o.recognisedGrossProfit.minor),
            AppColumn(
                label: 'Status',
                cell: (o) => StatusBadge.order(o.status),
                sortValue: (o) => o.status.label),
          ],
        ),
      ),
    );
  }

  // ---- Expenses -------------------------------------------------------------

  _Report _expenseReport(
      List<Expense> expenses, DateRange range, CurrencyCode currency) {
    final rows = [...expenses]
      ..sort((a, b) => b.annualisedAmount.minor.compareTo(a.annualisedAmount.minor));
    return _Report(
      slug: 'expense-report',
      csvHeader: const [
        'Expense',
        'Category',
        'Frequency',
        'Amount',
        'Annualised',
        'In-Period',
        'Status',
      ],
      csvRows: [
        for (final e in rows)
          [
            e.name,
            e.category.label,
            e.frequency.label,
            e.amount.major,
            e.annualisedAmount.major,
            _service.proratedExpense(e, range).major,
            e.status.label,
          ],
      ],
      body: SectionCard(
        title: 'Expense Report',
        subtitle: '${rows.length} expenses · prorated to period',
        padding: EdgeInsets.zero,
        child: AppDataTable<Expense>(
          rows: rows,
          searchableText: (e) => '${e.name} ${e.category.label}',
          emptyTitle: 'No expenses in this period',
          columns: [
            AppColumn(
                label: 'Expense',
                cell: (e) => Text(e.name,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                sortValue: (e) => e.name.toLowerCase()),
            AppColumn(
                label: 'Category',
                cell: (e) => Text(e.category.label),
                sortValue: (e) => e.category.label),
            AppColumn(
                label: 'Frequency',
                cell: (e) => Text(e.frequency.label),
                sortValue: (e) => e.frequency.label),
            AppColumn(
                label: 'Amount',
                numeric: true,
                cell: (e) => Text(MoneyFormatter.format(e.amount, currency)),
                sortValue: (e) => e.amount.minor),
            AppColumn(
                label: 'Annualised',
                numeric: true,
                cell: (e) =>
                    Text(MoneyFormatter.format(e.annualisedAmount, currency)),
                sortValue: (e) => e.annualisedAmount.minor),
            AppColumn(
                label: 'In-Period',
                numeric: true,
                cell: (e) => Text(MoneyFormatter.format(
                    _service.proratedExpense(e, range), currency)),
                sortValue: (e) => _service.proratedExpense(e, range).minor),
            AppColumn(
                label: 'Status',
                cell: (e) => StatusBadge.entity(e.status),
                sortValue: (e) => e.status.label),
          ],
        ),
      ),
    );
  }

  // ---- Marketing ------------------------------------------------------------

  _Report _marketingReport(List<Campaign> campaigns, List<Order> orders,
      DateRange range, CurrencyCode currency) {
    final perf = _service.campaignPerformance(
      campaigns: campaigns,
      orders: orders,
      range: range,
    )..sort((a, b) => b.spend.minor.compareTo(a.spend.minor));
    return _Report(
      slug: 'marketing-report',
      csvHeader: const [
        'Campaign',
        'Platform',
        'Spend',
        'Clicks',
        'Conversions',
        'Attributed Revenue',
        'ROI %',
        'ROAS',
      ],
      csvRows: [
        for (final p in perf)
          [
            p.campaign.name,
            p.campaign.platform.label,
            p.spend.major,
            p.campaign.clicks,
            p.campaign.conversions,
            p.attributedRevenue.major,
            p.roi == null ? 'N/A' : p.roi!.toStringAsFixed(1),
            p.roas == null ? 'N/A' : p.roas!.toStringAsFixed(2),
          ],
      ],
      body: SectionCard(
        title: 'Marketing Report',
        subtitle: '${perf.length} campaigns',
        padding: EdgeInsets.zero,
        child: AppDataTable<CampaignPerformance>(
          rows: perf,
          searchableText: (p) => '${p.campaign.name} ${p.campaign.platform.label}',
          emptyTitle: 'No campaigns in this period',
          columns: [
            AppColumn(
                label: 'Campaign',
                cell: (p) => Text(p.campaign.name,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                sortValue: (p) => p.campaign.name.toLowerCase()),
            AppColumn(
                label: 'Platform',
                cell: (p) => StatusBadge(
                    label: p.campaign.platform.label, tone: BadgeTone.info),
                sortValue: (p) => p.campaign.platform.label),
            AppColumn(
                label: 'Spend',
                numeric: true,
                cell: (p) => Text(MoneyFormatter.format(p.spend, currency)),
                sortValue: (p) => p.spend.minor),
            AppColumn(
                label: 'Clicks',
                numeric: true,
                cell: (p) => Text('${p.campaign.clicks}'),
                sortValue: (p) => p.campaign.clicks),
            AppColumn(
                label: 'Conv.',
                numeric: true,
                cell: (p) => Text('${p.campaign.conversions}'),
                sortValue: (p) => p.campaign.conversions),
            AppColumn(
                label: 'Attr. Revenue',
                numeric: true,
                cell: (p) =>
                    Text(MoneyFormatter.format(p.attributedRevenue, currency)),
                sortValue: (p) => p.attributedRevenue.minor),
            AppColumn(
                label: 'ROI',
                numeric: true,
                cell: (p) => Text(PercentFormatter.format(p.roi ?? double.nan)),
                sortValue: (p) => p.roi ?? -1e9),
            AppColumn(
                label: 'ROAS',
                numeric: true,
                cell: (p) => Text(PercentFormatter.roas(p.roas)),
                sortValue: (p) => p.roas ?? -1),
          ],
        ),
      ),
    );
  }

  // ---- Product profitability ------------------------------------------------

  _Report _productReport(List<Product> products, List<Order> orders,
      List<Campaign> campaigns, DateRange range, CurrencyCode currency) {
    final rows = _service.productProfitability(
      products: products,
      orders: orders,
      campaigns: campaigns,
      range: range,
    )..sort((a, b) => b.revenue.minor.compareTo(a.revenue.minor));
    return _Report(
      slug: 'product-profitability',
      csvHeader: const [
        'Product',
        'Orders',
        'Units',
        'Revenue',
        'Product Cost',
        'Marketing',
        'Gross Profit',
        'Net Profit',
        'Margin %',
      ],
      csvRows: [
        for (final p in rows)
          [
            p.product.name,
            p.orderCount,
            p.unitsSold,
            p.revenue.major,
            p.productCost.major,
            p.marketingCost.major,
            p.grossProfit.major,
            p.netProfit.major,
            p.margin.toStringAsFixed(1),
          ],
      ],
      body: SectionCard(
        title: 'Product Profitability',
        subtitle: '${rows.length} products',
        padding: EdgeInsets.zero,
        child: AppDataTable<ProductProfit>(
          rows: rows,
          searchableText: (p) => p.product.name,
          emptyTitle: 'No products to report',
          columns: [
            AppColumn(
                label: 'Product',
                cell: (p) => Text(p.product.name,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                sortValue: (p) => p.product.name.toLowerCase()),
            AppColumn(
                label: 'Orders',
                numeric: true,
                cell: (p) => Text('${p.orderCount}'),
                sortValue: (p) => p.orderCount),
            AppColumn(
                label: 'Units',
                numeric: true,
                cell: (p) => Text('${p.unitsSold}'),
                sortValue: (p) => p.unitsSold),
            AppColumn(
                label: 'Revenue',
                numeric: true,
                cell: (p) => Text(MoneyFormatter.format(p.revenue, currency)),
                sortValue: (p) => p.revenue.minor),
            AppColumn(
                label: 'Cost',
                numeric: true,
                cell: (p) => Text(MoneyFormatter.format(p.productCost, currency)),
                sortValue: (p) => p.productCost.minor),
            AppColumn(
                label: 'Marketing',
                numeric: true,
                cell: (p) =>
                    Text(MoneyFormatter.format(p.marketingCost, currency)),
                sortValue: (p) => p.marketingCost.minor),
            AppColumn(
                label: 'Net Profit',
                numeric: true,
                cell: (p) => Text(
                  MoneyFormatter.format(p.netProfit, currency),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: p.netProfit.isNegative
                        ? AppColors.error
                        : AppColors.success,
                  ),
                ),
                sortValue: (p) => p.netProfit.minor),
            AppColumn(
                label: 'Margin',
                numeric: true,
                cell: (p) => Text(PercentFormatter.format(p.margin)),
                sortValue: (p) => p.margin),
          ],
        ),
      ),
    );
  }

  // ---- Business profitability -----------------------------------------------

  _Report _businessReport(
    DataController data,
    String? bizId,
    List<Order> orders,
    List<Campaign> campaigns,
    List<Expense> expenses,
    DateRange range,
  ) {
    // One row per accessible business (or the single selected one).
    final businesses = bizId == null
        ? data.selectableBusinesses
        : [data.businessById(bizId)].whereType<Business>().toList();

    final rows = <_BusinessRow>[];
    for (final b in businesses) {
      final summary = _service.summarise(
        orders: data.ordersFor(b.id),
        campaigns: data.campaignsFor(b.id),
        expenses: data.expensesFor(b.id),
        range: range,
      );
      rows.add(_BusinessRow(business: b, summary: summary));
    }
    rows.sort((a, b) => b.summary.revenue.minor.compareTo(a.summary.revenue.minor));

    return _Report(
      slug: 'business-profitability',
      csvHeader: const [
        'Business',
        'Currency',
        'Revenue',
        'Product Cost',
        'Marketing',
        'Operating Expenses',
        'Gross Profit',
        'Net Profit',
        'Net Margin %',
      ],
      csvRows: [
        for (final r in rows)
          [
            r.business.name,
            r.business.currency.wire,
            r.summary.revenue.major,
            r.summary.productCost.major,
            r.summary.marketingCost.major,
            r.summary.operatingExpenses.major,
            r.summary.grossProfit.major,
            r.summary.netProfit.major,
            r.summary.netMargin.toStringAsFixed(1),
          ],
      ],
      body: SectionCard(
        title: 'Business Profitability',
        subtitle: '${rows.length} businesses',
        padding: EdgeInsets.zero,
        child: AppDataTable<_BusinessRow>(
          rows: rows,
          searchableText: (r) => r.business.name,
          emptyTitle: 'No businesses to report',
          columns: [
            AppColumn(
                label: 'Business',
                cell: (r) => Text(r.business.name,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                sortValue: (r) => r.business.name.toLowerCase()),
            AppColumn(
                label: 'Revenue',
                numeric: true,
                cell: (r) => Text(MoneyFormatter.format(
                    r.summary.revenue, r.business.currency)),
                sortValue: (r) => r.summary.revenue.minor),
            AppColumn(
                label: 'Product Cost',
                numeric: true,
                cell: (r) => Text(MoneyFormatter.format(
                    r.summary.productCost, r.business.currency)),
                sortValue: (r) => r.summary.productCost.minor),
            AppColumn(
                label: 'Marketing',
                numeric: true,
                cell: (r) => Text(MoneyFormatter.format(
                    r.summary.marketingCost, r.business.currency)),
                sortValue: (r) => r.summary.marketingCost.minor),
            AppColumn(
                label: 'Op. Expenses',
                numeric: true,
                cell: (r) => Text(MoneyFormatter.format(
                    r.summary.operatingExpenses, r.business.currency)),
                sortValue: (r) => r.summary.operatingExpenses.minor),
            AppColumn(
                label: 'Gross Profit',
                numeric: true,
                cell: (r) => Text(MoneyFormatter.format(
                    r.summary.grossProfit, r.business.currency)),
                sortValue: (r) => r.summary.grossProfit.minor),
            AppColumn(
                label: 'Net Profit',
                numeric: true,
                cell: (r) => Text(
                  MoneyFormatter.format(
                      r.summary.netProfit, r.business.currency),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: r.summary.netProfit.isNegative
                        ? AppColors.error
                        : AppColors.success,
                  ),
                ),
                sortValue: (r) => r.summary.netProfit.minor),
            AppColumn(
                label: 'Net Margin',
                numeric: true,
                cell: (r) => Text(PercentFormatter.format(r.summary.netMargin)),
                sortValue: (r) => r.summary.netMargin),
          ],
        ),
      ),
    );
  }
}

class _ReportTabs extends StatelessWidget {
  const _ReportTabs({required this.controller, required this.labels});

  final TabController controller;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: TabBar(
        controller: controller,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.textSecondary,
        indicatorColor: AppColors.primary,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        tabs: [for (final l in labels) Tab(text: l)],
      ),
    );
  }
}

/// Bundles a report's visible table with its CSV projection.
class _Report {
  const _Report({
    required this.slug,
    required this.csvHeader,
    required this.csvRows,
    required this.body,
  });

  final String slug;
  final List<String> csvHeader;
  final List<List<Object?>> csvRows;
  final Widget body;
}

class _BusinessRow {
  const _BusinessRow({required this.business, required this.summary});
  final Business business;
  final ProfitSummary summary;
}
