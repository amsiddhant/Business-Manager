import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:universal_html/html.dart' as html;

import '../../core/enums.dart';
import '../../core/permissions.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/money.dart';
import '../../models/campaign.dart';
import '../../models/order.dart';
import '../../models/product.dart';
import '../../services/profit_calculation_service.dart';
import '../../state/app_state.dart';
import '../../state/data_controller.dart';
import '../../state/filter_controller.dart';
import '../../widgets/common/app_card.dart';
import '../../widgets/common/comment_thread.dart';
import '../../widgets/common/confirm_dialog.dart';
import '../../widgets/common/currency_display.dart';
import '../../widgets/common/data_table_card.dart';
import '../../widgets/common/detail_widgets.dart';
import '../../widgets/common/page_header.dart';
import '../../widgets/common/responsive.dart';
import '../../widgets/common/state_views.dart';
import '../../widgets/common/status_badge.dart';
import 'products_screen.dart';

/// A single-product view: summary metrics, associated campaigns and orders.
class ProductDetailScreen extends StatelessWidget {
  const ProductDetailScreen({super.key, required this.productId});

  final String productId;

  static const _service = ProfitCalculationService();

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
          PageHeader(title: 'Product'),
          SizedBox(height: 48),
          LoadingView(),
        ],
      );
    }

    final product = data.productById(productId);
    if (product == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(
            title: 'Product',
            actions: [
              OutlinedButton.icon(
                onPressed: () => context.go(Routes.products),
                icon: const Icon(Icons.arrow_back, size: 18),
                label: const Text('Back to Products'),
              ),
            ],
          ),
          const SizedBox(height: 48),
          const EmptyView(
            icon: Icons.search_off,
            title: 'Product not found',
            message: 'This product may have been removed or is not accessible.',
          ),
        ],
      );
    }

    final currency =
        data.businessById(product.businessId)?.currency ?? CurrencyCode.inr;
    final range = filter.range;
    final orders = data.ordersForProduct(product.id);
    final campaigns = data.campaignsForProduct(product.id);

    final profit = _service
        .productProfitability(
          products: [product],
          orders: orders,
          campaigns: campaigns,
          range: range,
        )
        .firstOrNull;

    final canEdit = user?.can(Permission.editProduct) ?? false;

    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SummaryCard(
          product: product,
          profit: profit,
          currency: currency,
          period: filter.periodLabel,
        ),
        const SizedBox(height: AppSpacing.lg),
        _CampaignsCard(campaigns: campaigns, currency: currency),
        const SizedBox(height: AppSpacing.lg),
        _OrdersCard(orders: orders, currency: currency),
      ],
    );

    final repo = appState.repository;
    final right = DetailActivityColumn(
      activityAt: product.lastActivityAt,
      comments: product.comments,
      canComment: canEdit,
      onPost: (comment) async {
        await repo.saveProduct(
          product.copyWith(comments: [...product.comments, comment]),
          isNew: false,
        );
        await data.refresh();
      },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: product.name,
          subtitle: '${product.id}'
              '${product.category.isEmpty ? '' : ' · ${product.category}'}',
          actions: [
            OutlinedButton.icon(
              onPressed: () => context.go(Routes.products),
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('Back'),
            ),
            if (canEdit)
              ElevatedButton.icon(
                onPressed: () => _edit(context, product, data),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit'),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        DetailTwoColumn(left: left, right: right),
      ],
    );
  }

  Future<void> _edit(
      BuildContext context, Product product, DataController data) async {
    final repo = context.read<AppState>().repository;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => ProductFormDialog(
        existing: product,
        repo: repo,
        businesses: data.selectableBusinesses,
      ),
    );
    if (saved == true) {
      await data.refresh();
      if (context.mounted) {
        showSuccessSnack(context, 'Product updated successfully');
      }
    }
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.product,
    required this.profit,
    required this.currency,
    required this.period,
  });

  final Product product;
  final ProductProfit? profit;
  final CurrencyCode currency;
  final String period;

  @override
  Widget build(BuildContext context) {
    final metrics = <_Metric>[
      _Metric('Buying Price', MoneyFormatter.format(product.buyingPrice, currency)),
      _Metric('Selling Price',
          MoneyFormatter.format(product.sellingPrice, currency)),
      _Metric('Total Orders', '${profit?.orderCount ?? 0}'),
      _Metric('Units Sold', '${profit?.unitsSold ?? 0}'),
      _Metric('Revenue',
          MoneyFormatter.format(profit?.revenue ?? Money.zero, currency)),
      _Metric('Product Cost',
          MoneyFormatter.format(profit?.productCost ?? Money.zero, currency)),
      _Metric('Marketing Cost',
          MoneyFormatter.format(profit?.marketingCost ?? Money.zero, currency)),
      _Metric('Gross Profit',
          MoneyFormatter.format(profit?.grossProfit ?? Money.zero, currency),
          tone: (profit?.grossProfit ?? Money.zero).isNegative
              ? AppColors.error
              : AppColors.success),
      _Metric('Net Profit',
          MoneyFormatter.format(profit?.netProfit ?? Money.zero, currency),
          tone: (profit?.netProfit ?? Money.zero).isNegative
              ? AppColors.error
              : AppColors.success),
      _Metric('Margin',
          PercentFormatter.format(profit?.margin ?? double.nan)),
    ];

    return SectionCard(
      title: 'Product Summary',
      subtitle: 'For $period',
      trailing: StatusBadge.entity(product.status),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (product.url.isNotEmpty) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => _openUrl(product.url),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Open product page'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          if (product.description.isNotEmpty) ...[
            Text(product.description,
                style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: AppSpacing.lg),
          ],
          LayoutBuilder(
            builder: (context, constraints) {
              final screen = Responsive.of(context);
              final columns = switch (screen) {
                ScreenType.mobile => 2,
                ScreenType.tablet => 3,
                ScreenType.desktop => 5,
              };
              const gap = AppSpacing.md;
              final tileWidth =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final m in metrics)
                    SizedBox(width: tileWidth, child: _MetricTile(metric: m)),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  void _openUrl(String url) {
    final normalised =
        url.startsWith('http://') || url.startsWith('https://')
            ? url
            : 'https://$url';
    html.window.open(normalised, '_blank');
  }
}

class _Metric {
  const _Metric(this.label, this.value, {this.tone});
  final String label;
  final String value;
  final Color? tone;
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.metric});
  final _Metric metric;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(metric.label,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Text(
            metric.value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: metric.tone ?? AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _CampaignsCard extends StatelessWidget {
  const _CampaignsCard({required this.campaigns, required this.currency});

  final List<Campaign> campaigns;
  final CurrencyCode currency;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Product Campaigns',
      subtitle: '${campaigns.length} associated',
      padding: EdgeInsets.zero,
      child: AppDataTable<Campaign>(
        rows: campaigns,
        rowsPerPage: 5,
        onRowTap: (c) => context.go(Routes.campaignDetailPath(c.id)),
        emptyTitle: 'No campaigns',
        emptyMessage: 'Campaigns for this product will appear here.',
        columns: [
          AppColumn(
            label: 'Campaign',
            cell: (c) => Text(c.name,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            sortValue: (c) => c.name.toLowerCase(),
          ),
          AppColumn(
            label: 'Platform',
            cell: (c) =>
                StatusBadge(label: c.platform.label, tone: BadgeTone.info),
            sortValue: (c) => c.platform.label,
          ),
          AppColumn(
            label: 'Spend',
            numeric: true,
            cell: (c) => CurrencyText(c.amountInvested, currency: currency),
            sortValue: (c) => c.amountInvested.minor,
          ),
          AppColumn(
            label: 'Clicks',
            numeric: true,
            cell: (c) => Text('${c.clicks}'),
            sortValue: (c) => c.clicks,
          ),
          AppColumn(
            label: 'Conversions',
            numeric: true,
            cell: (c) => Text('${c.conversions}'),
            sortValue: (c) => c.conversions,
          ),
          AppColumn(
            label: 'Status',
            cell: (c) => StatusBadge.campaign(c.status),
            sortValue: (c) => c.status.label,
          ),
        ],
      ),
    );
  }
}

class _OrdersCard extends StatelessWidget {
  const _OrdersCard({required this.orders, required this.currency});

  final List<Order> orders;
  final CurrencyCode currency;

  static final _epoch = DateTime.fromMillisecondsSinceEpoch(0);
  static DateTime _dateOf(Order o) =>
      o.orderDate ?? o.audit.createdAt ?? _epoch;

  @override
  Widget build(BuildContext context) {
    final sorted = [...orders]
      ..sort((a, b) => _dateOf(b).compareTo(_dateOf(a)));
    return SectionCard(
      title: 'Product Orders',
      subtitle: '${orders.length} total',
      padding: EdgeInsets.zero,
      child: AppDataTable<Order>(
        rows: sorted,
        rowsPerPage: 10,
        onRowTap: (o) => context.go(Routes.orderDetailPath(o.id)),
        emptyTitle: 'No orders',
        emptyMessage: 'Orders for this product will appear here.',
        columns: [
          AppColumn(
            label: 'Order ID',
            cell: (o) => Text(o.id,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            sortValue: (o) => o.id,
          ),
          AppColumn(
            label: 'Date',
            cell: (o) => Text(AppDate.short(_dateOf(o))),
            sortValue: (o) => _dateOf(o).millisecondsSinceEpoch,
          ),
          AppColumn(
            label: 'Qty',
            numeric: true,
            cell: (o) => Text('${o.quantity}'),
            sortValue: (o) => o.quantity,
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
    );
  }
}
