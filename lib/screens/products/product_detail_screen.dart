import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/enums.dart';
import '../../core/permissions.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/theme_x.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/money.dart';
import '../../models/campaign.dart';
import '../../models/order.dart';
import '../../services/profit_calculation_service.dart';
import '../../state/app_state.dart';
import '../../state/data_controller.dart';
import '../../state/filter_controller.dart';
import '../../widgets/common/app_card.dart';
import '../../widgets/common/comment_thread.dart';
import '../../widgets/common/currency_display.dart';
import '../../widgets/common/detail_widgets.dart';
import '../../widgets/common/status_badge.dart';
import '../../widgets/data/app_data_grid.dart';
import '../../widgets/layout/detail_page.dart';
import '../../widgets/layout/kpi_strip.dart';
import 'products_screen.dart';

/// A single-product view: summary metrics, associated campaigns and orders.
class ProductDetailScreen extends StatelessWidget {
  const ProductDetailScreen({super.key, required this.productId});

  final String productId;

  static const _service = ProfitCalculationService();
  static final _epoch = DateTime.fromMillisecondsSinceEpoch(0);
  static DateTime _dateOf(Order o) =>
      o.orderDate ?? o.audit.createdAt ?? _epoch;

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataController>();
    final filter = context.watch<FilterController>();
    final appState = context.watch<AppState>();
    final user = appState.currentUser;
    void back() => context.go(Routes.products);

    if (data.loading && !data.loaded) {
      return DetailPage.loading(
          title: 'Product', onBack: back, backLabel: 'Products');
    }

    final product = data.productById(productId);
    if (product == null) {
      return DetailPage.notFound(
        title: 'Product',
        onBack: back,
        backLabel: 'Products',
        message: 'This product may have been removed or is not accessible.',
      );
    }

    final t = context.tokens;
    final business = data.businessById(product.businessId);
    final currency = business?.currency ?? CurrencyCode.inr;
    final orders = data.ordersForProduct(product.id);
    final campaigns = data.campaignsForProduct(product.id);
    final profit = _service
        .productProfitability(
          products: [product],
          orders: orders,
          campaigns: campaigns,
          range: filter.range,
        )
        .firstOrNull;

    final canCreate = user?.can(Permission.createProduct) ?? false;
    final canEdit = user?.can(Permission.editProduct) ?? false;
    final canDelete = user?.can(Permission.deleteProduct) ?? false;
    final repo = appState.repository;
    String money(Money m) => MoneyFormatter.format(m, currency);
    Color toneOf(Money m) => m.isNegative ? t.error : t.success;
    final gross = profit?.grossProfit ?? Money.zero;
    final net = profit?.netProfit ?? Money.zero;
    final period = filter.periodLabel;
    final sortedOrders = [...orders]
      ..sort((a, b) => _dateOf(b).compareTo(_dateOf(a)));

    return DetailPage(
      title: product.name,
      subtitle: product.id +
          (product.category.isEmpty ? '' : ' · ${product.category}'),
      icon: Icons.inventory_2_outlined,
      status: StatusBadge.entity(product.status),
      backLabel: 'Products',
      onBack: back,
      meta: [
        if (business != null)
          DetailMeta(Icons.business_outlined, business.name,
              tooltip: 'Open business',
              onTap: () => context.go(Routes.businessDetailPath(business.id))),
        if (product.sku.isNotEmpty)
          DetailMeta(Icons.qr_code_2, product.sku, tooltip: 'SKU'),
        if (product.url.isNotEmpty)
          DetailMeta(Icons.open_in_new, 'Product page',
              tooltip: 'Open product page',
              onTap: () => openExternalUrl(product.url)),
      ],
      primaryAction: canEdit
          ? FilledButton.icon(
              onPressed: () =>
                  ProductsScreen.openForm(context, product, product.businessId),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Edit'),
            )
          : null,
      menu: [
        if (canCreate)
          DetailAction(
            label: 'Duplicate',
            icon: Icons.copy_all_outlined,
            onSelected: () => ProductActions.duplicate(context, product),
          ),
        if (canEdit && product.status != EntityStatus.active)
          DetailAction(
            label: 'Mark active',
            icon: Icons.check_circle_outline,
            onSelected: () =>
                ProductActions.setStatus(context, product, EntityStatus.active),
          ),
        if (canEdit && product.status == EntityStatus.active)
          DetailAction(
            label: 'Mark inactive',
            icon: Icons.pause_circle_outline,
            onSelected: () => ProductActions.setStatus(
                context, product, EntityStatus.inactive),
          ),
        if (canDelete)
          DetailAction(
            label: 'Delete product',
            icon: Icons.delete_outline,
            destructive: true,
            onSelected: () async {
              if (await ProductActions.delete(context, product) &&
                  context.mounted) {
                back();
              }
            },
          ),
      ],
      kpis: [
        KpiItem(
          label: 'Buying Price',
          value: money(product.buyingPrice),
          icon: Icons.shopping_bag_outlined,
          caption: 'Default per unit',
        ),
        KpiItem(
          label: 'Selling Price',
          value: money(product.sellingPrice),
          icon: Icons.sell_outlined,
          caption: 'Default per unit',
        ),
        KpiItem(
          label: 'Total Orders',
          value: '${profit?.orderCount ?? 0}',
          icon: Icons.receipt_long_outlined,
          caption: period,
        ),
        KpiItem(
          label: 'Units Sold',
          value: '${profit?.unitsSold ?? 0}',
          icon: Icons.shopping_cart_outlined,
          caption: period,
        ),
        KpiItem(
          label: 'Revenue',
          value: money(profit?.revenue ?? Money.zero),
          icon: Icons.trending_up,
          caption: period,
        ),
        KpiItem(
          label: 'Product Cost',
          value: money(profit?.productCost ?? Money.zero),
          icon: Icons.inventory_2_outlined,
        ),
        KpiItem(
          label: 'Marketing Cost',
          value: money(profit?.marketingCost ?? Money.zero),
          icon: Icons.campaign_outlined,
        ),
        KpiItem(
          label: 'Gross Profit',
          value: money(gross),
          icon: Icons.savings_outlined,
          tone: toneOf(gross),
          tooltip: 'Revenue minus product cost.',
        ),
        KpiItem(
          label: 'Net Profit',
          value: money(net),
          icon: Icons.account_balance_wallet_outlined,
          tone: toneOf(net),
          tooltip: 'Revenue minus product and marketing cost.',
        ),
        KpiItem(
          label: 'Margin',
          value: PercentFormatter.format(profit?.margin ?? double.nan),
          icon: Icons.percent,
          tone: toneOf(net),
          tooltip: 'Net profit as a share of revenue.',
        ),
      ],
      activity: DetailActivityColumn(
        activityAt: product.lastActivityAt,
        comments: product.comments,
        canComment: canEdit,
        onPost: (comment) async {
          await repo.saveProduct(
            product.copyWith(comments: [...product.comments, comment]),
            isNew: false,
          );
        },
      ),
      children: [
        SectionCard(
          title: 'Product details',
          subtitle: 'Figures above are for $period',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DetailGrid(fields: [
                DetailField('Product ID', product.id, Icons.badge_outlined),
                DetailField(
                    'Business', business?.name ?? '—', Icons.business_outlined),
                DetailField('SKU', product.sku, Icons.qr_code_2),
                DetailField(
                    'Category', product.category, Icons.category_outlined),
                DetailField('Product page', product.url, Icons.link,
                    isLink: true),
              ]),
              if (product.url.isNotEmpty) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () => openExternalUrl(product.url),
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('Open product page'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: t.primary,
                      side: BorderSide(color: t.primary),
                    ),
                  ),
                ),
              ],
              if (product.description.trim().isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: t.surfaceAlt,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Description',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: t.textSecondary)),
                      const SizedBox(height: 4),
                      Text(product.description,
                          style: const TextStyle(fontSize: 14, height: 1.4)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        AppDataGrid<Campaign>(
          gridId: 'product.campaigns',
          title: 'Product Campaigns',
          subtitle: '${campaigns.length} associated',
          rows: campaigns,
          rowKey: (c) => c.id,
          pageSize: 5,
          exportName: 'product-campaigns',
          searchHint: 'Search campaigns by name, platform or status…',
          searchText: (c) =>
              '${c.id} ${c.name} ${c.platform.label} ${c.status.label}',
          onRowTap: (c) => context.go(Routes.campaignDetailPath(c.id)),
          emptyTitle: 'No campaigns',
          emptyIcon: Icons.campaign_outlined,
          emptyMessage: 'Campaigns for this product will appear here.',
          columns: [
            GridColumn<Campaign>(
              id: 'name',
              label: 'Campaign',
              pinned: true,
              flex: 2,
              cardRole: CardRole.title,
              cell: (c) => Text(c.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              sortValue: (c) => c.name.toLowerCase(),
              exportValue: (c) => c.name,
            ),
            GridColumn<Campaign>(
              id: 'platform',
              label: 'Platform',
              cardRole: CardRole.meta,
              cell: (c) =>
                  StatusBadge(label: c.platform.label, tone: BadgeTone.info),
              sortValue: (c) => c.platform.label,
              exportValue: (c) => c.platform.label,
            ),
            GridColumn<Campaign>(
              id: 'spend',
              label: 'Spend',
              numeric: true,
              cardRole: CardRole.metric,
              cell: (c) => CurrencyText(c.amountInvested, currency: currency),
              sortValue: (c) => c.amountInvested.minor,
              exportValue: (c) => c.amountInvested.major.toStringAsFixed(2),
            ),
            GridColumn<Campaign>(
              id: 'clicks',
              label: 'Clicks',
              numeric: true,
              cardRole: CardRole.metric,
              cell: (c) => Text('${c.clicks}'),
              sortValue: (c) => c.clicks,
              exportValue: (c) => '${c.clicks}',
            ),
            GridColumn<Campaign>(
              id: 'conversions',
              label: 'Conversions',
              numeric: true,
              cardRole: CardRole.metric,
              cell: (c) => Text('${c.conversions}'),
              sortValue: (c) => c.conversions,
              exportValue: (c) => '${c.conversions}',
            ),
            GridColumn<Campaign>(
              id: 'status',
              label: 'Status',
              cardRole: CardRole.badge,
              minWidth: 120,
              cell: (c) => StatusBadge.campaign(c.status),
              sortValue: (c) => c.status.label,
              exportValue: (c) => c.status.label,
              filter: GridFilter.choice((c) => c.status.label),
            ),
          ],
        ),
        AppDataGrid<Order>(
          gridId: 'product.orders',
          title: 'Product Orders',
          subtitle: '${orders.length} total',
          rows: sortedOrders,
          rowKey: (o) => o.id,
          pageSize: 10,
          exportName: 'product-orders',
          searchHint: 'Search orders by ID, date, status or customer…',
          searchText: (o) => '${o.id} ${AppDate.short(_dateOf(o))} '
              '${o.status.label} ${o.customerReference}',
          onRowTap: (o) => context.go(Routes.orderDetailPath(o.id)),
          emptyTitle: 'No orders',
          emptyIcon: Icons.receipt_long_outlined,
          emptyMessage: 'Orders for this product will appear here.',
          columns: [
            GridColumn<Order>(
              id: 'id',
              label: 'Order ID',
              pinned: true,
              cardRole: CardRole.title,
              minWidth: 110,
              cell: (o) => Text(o.id,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              sortValue: (o) => o.id,
              exportValue: (o) => o.id,
            ),
            GridColumn<Order>(
              id: 'date',
              label: 'Date',
              cardRole: CardRole.subtitle,
              minWidth: 110,
              cell: (o) => Text(AppDate.short(_dateOf(o))),
              sortValue: (o) => _dateOf(o).millisecondsSinceEpoch,
              exportValue: (o) => AppDate.short(_dateOf(o)),
            ),
            GridColumn<Order>(
              id: 'qty',
              label: 'Qty',
              numeric: true,
              minWidth: 64,
              cardRole: CardRole.meta,
              cell: (o) => Text('${o.quantity}'),
              sortValue: (o) => o.quantity,
              exportValue: (o) => '${o.quantity}',
            ),
            GridColumn<Order>(
              id: 'revenue',
              label: 'Revenue',
              numeric: true,
              cardRole: CardRole.metric,
              cell: (o) => CurrencyText(o.recognisedRevenue, currency: currency),
              sortValue: (o) => o.recognisedRevenue.minor,
              exportValue: (o) => o.recognisedRevenue.major.toStringAsFixed(2),
            ),
            GridColumn<Order>(
              id: 'cost',
              label: 'Cost',
              numeric: true,
              cardRole: CardRole.metric,
              cell: (o) =>
                  CurrencyText(o.recognisedProductCost, currency: currency),
              sortValue: (o) => o.recognisedProductCost.minor,
              exportValue: (o) =>
                  o.recognisedProductCost.major.toStringAsFixed(2),
            ),
            GridColumn<Order>(
              id: 'profit',
              label: 'Profit',
              numeric: true,
              cardRole: CardRole.metric,
              cell: (o) =>
                  CurrencyText(o.recognisedGrossProfit, currency: currency),
              sortValue: (o) => o.recognisedGrossProfit.minor,
              exportValue: (o) =>
                  o.recognisedGrossProfit.major.toStringAsFixed(2),
            ),
            GridColumn<Order>(
              id: 'status',
              label: 'Status',
              cardRole: CardRole.badge,
              minWidth: 120,
              cell: (o) => StatusBadge.order(o.status),
              sortValue: (o) => o.status.label,
              exportValue: (o) => o.status.label,
              filter: GridFilter.choice((o) => o.status.label,
                  options: [for (final s in OrderStatus.values) s.label]),
            ),
          ],
        ),
      ],
    );
  }
}
