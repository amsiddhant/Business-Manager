import 'package:flutter/material.dart';

import '../../../core/enums.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_x.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/money.dart';
import '../../../models/order.dart';
import '../../../services/profit_calculation_service.dart';
import '../../../widgets/common/app_card.dart';
import '../../../widgets/common/currency_display.dart';
import '../../../widgets/common/data_table_card.dart';
import '../../../widgets/common/search_field.dart';
import '../../../widgets/common/state_views.dart';
import '../../../widgets/common/status_badge.dart';

/// How many rows a dashboard table shows.
const kDashboardTableRows = 10;

/// The rows a dashboard table shows: [rows] (already in the table's default
/// order) narrowed by [query] *before* taking the first [limit], so a search
/// finds rows outside the top ten too.
List<T> dashboardRows<T>(
  List<T> rows,
  String query,
  String Function(T row) searchable, {
  int limit = kDashboardTableRows,
}) {
  final q = query.trim().toLowerCase();
  final matches = q.isEmpty
      ? rows
      : [
          for (final r in rows)
            if (searchable(r).toLowerCase().contains(q)) r,
        ];
  return matches.take(limit).toList();
}

class TopProductsTable extends StatelessWidget {
  const TopProductsTable({
    super.key,
    required this.rows,
    required this.currency,
    this.onRowTap,
    this.onViewAll,
  });

  final List<ProductProfit> rows;
  final CurrencyCode currency;
  final ValueChanged<ProductProfit>? onRowTap;
  final VoidCallback? onViewAll;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final sorted = [...rows]
      ..sort((a, b) => b.revenue.minor.compareTo(a.revenue.minor));
    return _DashboardTable<ProductProfit>(
      icon: Icons.inventory_2_outlined,
      title: 'Top Products',
      subtitle: 'Ranked by revenue in the selected period',
      hintText: 'Search products by name…',
      rows: sorted,
      searchable: (p) => p.product.name,
      emptyTitle: 'No product activity',
      emptyMessage: 'Recognised orders will populate this table.',
      onRowTap: onRowTap,
      onViewAll: onViewAll,
      compact: (p) => _CompactRow(
        title: p.product.name,
        subtitle: '${p.orderCount} ${p.orderCount == 1 ? 'order' : 'orders'}'
            ' · Margin ${PercentFormatter.format(p.margin)}',
        value: CurrencyText(p.revenue,
            currency: currency,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        detail: Text(
            'Net ${MoneyFormatter.format(p.netProfit, currency)}',
            style: TextStyle(
                fontSize: 12,
                color: p.netProfit.isNegative ? t.error : t.textTertiary)),
      ),
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
    );
  }
}

class RecentOrdersTable extends StatelessWidget {
  const RecentOrdersTable({
    super.key,
    required this.orders,
    required this.range,
    required this.currency,
    this.onRowTap,
    this.onViewAll,
  });

  final List<Order> orders;
  final DateRange range;
  final CurrencyCode currency;
  final ValueChanged<Order>? onRowTap;
  final VoidCallback? onViewAll;

  static final _epoch = DateTime.fromMillisecondsSinceEpoch(0);
  static DateTime dateOf(Order o) => o.orderDate ?? o.audit.createdAt ?? _epoch;

  @override
  Widget build(BuildContext context) {
    final inRange = orders.where((o) => range.contains(dateOf(o))).toList()
      ..sort((a, b) => dateOf(b).compareTo(dateOf(a)));
    return _DashboardTable<Order>(
      icon: Icons.receipt_long_outlined,
      title: 'Recent Orders',
      subtitle: 'Latest activity in the selected period',
      hintText: 'Search orders by ID, product or status…',
      rows: inRange,
      searchable: (o) => '${o.id} ${o.productName} ${o.status.label}',
      emptyTitle: 'No orders yet',
      emptyMessage: 'Orders in the selected period will appear here.',
      onRowTap: onRowTap,
      onViewAll: onViewAll,
      compact: (o) => _CompactRow(
        title: o.productName,
        subtitle: '${o.id} · ${AppDate.short(dateOf(o))}',
        value: CurrencyText(o.recognisedRevenue,
            currency: currency,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        detail: StatusBadge.order(o.status),
      ),
      columns: [
        AppColumn(
          label: 'Order ID',
          cell: (o) =>
              Text(o.id, style: const TextStyle(fontWeight: FontWeight.w600)),
          sortValue: (o) => o.id,
        ),
        AppColumn(
          label: 'Product',
          cell: (o) => Text(o.productName),
          sortValue: (o) => o.productName.toLowerCase(),
        ),
        AppColumn(
          label: 'Date',
          cell: (o) => Text(AppDate.short(dateOf(o))),
          sortValue: (o) => dateOf(o).millisecondsSinceEpoch,
        ),
        AppColumn(
          label: 'Revenue',
          numeric: true,
          cell: (o) => CurrencyText(o.recognisedRevenue, currency: currency),
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
    );
  }
}

class CampaignPerformanceTable extends StatelessWidget {
  const CampaignPerformanceTable({
    super.key,
    required this.rows,
    required this.currency,
    this.onRowTap,
    this.onViewAll,
  });

  final List<CampaignPerformance> rows;
  final CurrencyCode currency;
  final ValueChanged<CampaignPerformance>? onRowTap;
  final VoidCallback? onViewAll;

  @override
  Widget build(BuildContext context) {
    final sorted = [...rows]
      ..sort((a, b) => b.spend.minor.compareTo(a.spend.minor));
    return _DashboardTable<CampaignPerformance>(
      icon: Icons.campaign_outlined,
      title: 'Campaign Performance',
      subtitle: 'Spend and return by campaign',
      hintText: 'Search campaigns by name or platform…',
      rows: sorted,
      searchable: (c) => '${c.campaign.name} ${c.campaign.platform.label}',
      emptyTitle: 'No campaign activity',
      emptyMessage: 'Campaigns with spend will appear here.',
      onRowTap: onRowTap,
      onViewAll: onViewAll,
      compact: (c) => _CompactRow(
        title: c.campaign.name,
        subtitle: '${c.campaign.platform.label} · ROAS '
            '${PercentFormatter.roas(c.roas)}',
        value: CurrencyText(c.spend,
            currency: currency,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        detail: Text(
            'Revenue ${MoneyFormatter.format(c.attributedRevenue, currency)}',
            style:
                TextStyle(fontSize: 12, color: context.tokens.textTertiary)),
      ),
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
          cell: (c) => CurrencyText(c.attributedRevenue, currency: currency),
          sortValue: (c) => c.attributedRevenue.minor,
        ),
        AppColumn(
          label: 'ROI',
          numeric: true,
          cell: (c) => Text(
              c.roi == null ? 'N/A' : PercentFormatter.format(c.roi!)),
          sortValue: (c) => c.roi ?? -1,
        ),
        AppColumn(
          label: 'ROAS',
          numeric: true,
          cell: (c) => Text(PercentFormatter.roas(c.roas)),
          sortValue: (c) => c.roas ?? -1,
        ),
      ],
    );
  }
}

/// A dashboard table card: header with "View all", search, then the table —
/// or, on phones, a compact list of the same rows.
class _DashboardTable<T> extends StatefulWidget {
  const _DashboardTable({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.hintText,
    required this.rows,
    required this.searchable,
    required this.columns,
    required this.compact,
    required this.emptyTitle,
    required this.emptyMessage,
    this.onRowTap,
    this.onViewAll,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String hintText;

  /// Every row, in the table's default order.
  final List<T> rows;
  final String Function(T row) searchable;
  final List<AppColumn<T>> columns;
  final Widget Function(T row) compact;
  final String emptyTitle;
  final String emptyMessage;
  final ValueChanged<T>? onRowTap;
  final VoidCallback? onViewAll;

  @override
  State<_DashboardTable<T>> createState() => _DashboardTableState<T>();
}

class _DashboardTableState<T> extends State<_DashboardTable<T>> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final shown = dashboardRows(widget.rows, _query, widget.searchable);
    final searching = _query.trim().isNotEmpty;
    final total = searching
        ? dashboardRows(widget.rows, _query, widget.searchable,
                limit: widget.rows.length)
            .length
        : widget.rows.length;

    return AppCard(
      padding: EdgeInsets.zero,
      child: LayoutBuilder(builder: (context, c) {
        final compact = c.maxWidth < 640;
        final pad = compact ? AppSpacing.lg : AppSpacing.xl;
        final header = Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: t.primarySurface,
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: Icon(widget.icon, size: 18, color: t.primary),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.title,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(widget.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: 12.5, color: t.textSecondary)),
                ],
              ),
            ),
            if (widget.onViewAll != null)
              TextButton.icon(
                onPressed: widget.onViewAll,
                iconAlignment: IconAlignment.end,
                icon: const Icon(Icons.arrow_forward, size: 16),
                label: const Text('View all'),
              ),
          ],
        );
        final search = SearchField(
          hintText: widget.hintText,
          width: compact ? null : 320,
          onChanged: (v) => setState(() => _query = v),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(pad, pad, pad, AppSpacing.md),
              child: compact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        header,
                        const SizedBox(height: AppSpacing.md),
                        search,
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(child: header),
                        const SizedBox(width: AppSpacing.lg),
                        search,
                      ],
                    ),
            ),
            if (searching && total > shown.length)
              Padding(
                padding: EdgeInsets.fromLTRB(pad, 0, pad, AppSpacing.sm),
                child: Text(
                    'Showing the first ${shown.length} of $total matches',
                    style: TextStyle(fontSize: 12, color: t.textTertiary)),
              ),
            if (compact)
              _compactList(context, shown, pad)
            else
              AppDataTable<T>(
                rows: shown,
                rowsPerPage: kDashboardTableRows,
                searchText: '',
                searchableText: widget.searchable,
                emptyTitle: widget.emptyTitle,
                emptyMessage: widget.emptyMessage,
                onRowTap: widget.onRowTap,
                columns: widget.columns,
              ),
          ],
        );
      }),
    );
  }

  Widget _compactList(BuildContext context, List<T> rows, double pad) {
    final t = context.tokens;
    if (rows.isEmpty) {
      return Padding(
        padding: EdgeInsets.fromLTRB(pad, AppSpacing.md, pad, pad),
        child: EmptyView(
          icon: widget.icon,
          title: widget.emptyTitle,
          message: widget.emptyMessage,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, indent: pad, color: t.border),
            InkWell(
              onTap: widget.onRowTap == null
                  ? null
                  : () => widget.onRowTap!(rows[i]),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: pad, vertical: 10),
                child: widget.compact(rows[i]),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One row of a dashboard table on a phone.
class _CompactRow extends StatelessWidget {
  const _CompactRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.detail,
  });

  final String title;
  final String subtitle;
  final Widget value;
  final Widget detail;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: t.textPrimary)),
              const SizedBox(height: 2),
              Text(subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: t.textTertiary)),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [value, const SizedBox(height: 4), detail],
        ),
      ],
    );
  }
}
