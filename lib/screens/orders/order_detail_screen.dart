import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/enums.dart';
import '../../core/permissions.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_x.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/money.dart';
import '../../models/order.dart';
import '../../services/profit_calculation_service.dart';
import '../../state/app_state.dart';
import '../../state/data_controller.dart';
import '../../widgets/common/app_card.dart';
import '../../widgets/common/comment_thread.dart';
import '../../widgets/common/detail_widgets.dart';
import '../../widgets/common/status_badge.dart';
import '../../widgets/layout/detail_page.dart';
import '../../widgets/layout/kpi_strip.dart';
import 'orders_screen.dart';

/// A single order view: headline figures, the pricing breakdown, linked
/// product, business and customer, plus a comment thread. Linked entities
/// resolve through the access-scoped [DataController].
class OrderDetailScreen extends StatelessWidget {
  const OrderDetailScreen({super.key, required this.orderId});

  final String orderId;

  static const _service = ProfitCalculationService();

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataController>();
    final appState = context.watch<AppState>();
    final user = appState.currentUser;
    void back() => context.go(Routes.orders);

    if (data.loading && !data.loaded) {
      return DetailPage.loading(
          title: 'Order', onBack: back, backLabel: 'Orders');
    }

    final order = data.orderById(orderId);
    if (order == null) {
      return DetailPage.notFound(
        title: 'Order',
        onBack: back,
        backLabel: 'Orders',
        message: 'This order may have been removed or is not accessible.',
      );
    }

    final t = context.tokens;
    final business = data.businessById(order.businessId);
    final product = data.productById(order.productId);
    final customer = order.customerReference.isEmpty
        ? null
        : data.customerById(order.customerReference);
    final currency = business?.currency ?? CurrencyCode.inr;
    final canCreate = user?.can(Permission.createOrder) ?? false;
    final canEdit = user?.can(Permission.editOrder) ?? false;
    final canDelete = user?.can(Permission.deleteOrder) ?? false;
    String money(Money m) => MoneyFormatter.format(m, currency);
    final margin = _service.summariseOrders([order]).grossMargin;
    final repo = appState.repository;

    return DetailPage(
      title: 'Order ${order.id}',
      subtitle: product?.name ?? order.productName,
      icon: Icons.receipt_long_outlined,
      status: StatusBadge.order(order.status),
      backLabel: 'Orders',
      onBack: back,
      meta: [
        if (business != null) DetailMeta(Icons.business_outlined, business.name),
        DetailMeta(
          Icons.event_outlined,
          order.orderDate == null ? 'No order date' : AppDate.format(order.orderDate),
          tooltip: 'Order date',
        ),
        if (customer != null)
          DetailMeta(Icons.person_outline, customer.name,
              tooltip: 'Open customer',
              onTap: () => context.go(Routes.customerDetailPath(customer.id)))
        else if (order.customerReference.isNotEmpty)
          DetailMeta(Icons.person_outline, order.customerReference),
      ],
      primaryAction: canEdit
          ? FilledButton.icon(
              onPressed: () =>
                  OrdersScreen.openForm(context, order, order.businessId),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Edit'),
            )
          : null,
      menu: [
        if (canCreate)
          DetailAction(
            label: 'Duplicate',
            icon: Icons.copy_all_outlined,
            onSelected: () => OrderActions.duplicate(context, order),
          ),
        if (canEdit && order.status != OrderStatus.cancelled)
          DetailAction(
            label: 'Cancel order',
            icon: Icons.cancel_outlined,
            onSelected: () => OrderActions.cancel(context, order),
          ),
        if (canEdit && order.status != OrderStatus.returned)
          DetailAction(
            label: 'Return / Refund',
            icon: Icons.assignment_return_outlined,
            onSelected: () => OrderActions.returnRefund(context, order),
          ),
        if (canEdit && !order.status.contributesToRevenue)
          DetailAction(
            label: 'Reinstate order',
            icon: Icons.restart_alt,
            onSelected: () => OrderActions.reinstate(context, order),
          ),
        if (canDelete)
          DetailAction(
            label: 'Delete order',
            icon: Icons.delete_outline,
            destructive: true,
            onSelected: () async {
              if (await OrderActions.delete(context, order) &&
                  context.mounted) {
                back();
              }
            },
          ),
      ],
      kpis: [
        KpiItem(
          label: 'Total revenue',
          value: money(order.recognisedRevenue),
          icon: Icons.trending_up,
          caption: order.isRefunded
              ? 'of ${money(order.totalRevenue)} before refund'
              : order.isRecognised
                  ? null
                  : 'Excluded — order ${order.status.label.toLowerCase()}',
        ),
        KpiItem(
          label: 'Product cost',
          value: money(order.recognisedProductCost),
          icon: Icons.inventory_2_outlined,
        ),
        KpiItem(
          label: 'Gross profit',
          value: money(order.recognisedGrossProfit),
          icon: Icons.savings_outlined,
          tone: order.recognisedGrossProfit.isNegative ? t.error : t.success,
          caption:
              margin == null ? null : '${margin.toStringAsFixed(1)}% margin',
        ),
        KpiItem(
          label: 'Quantity',
          value: '${order.quantity}',
          icon: Icons.shopping_cart_outlined,
          caption: order.quantity == 1 ? 'unit' : 'units',
        ),
        if (order.isRefunded)
          KpiItem(
            label: 'Refund',
            value: money(order.effectiveRefund),
            icon: Icons.assignment_return_outlined,
            tone: t.error,
            caption: order.refundDate == null
                ? null
                : 'on ${AppDate.format(order.refundDate)}',
          ),
      ],
      activity: DetailActivityColumn(
        activityAt: order.lastActivityAt,
        comments: order.comments,
        canComment: canEdit,
        onPost: (comment) async {
          await repo.saveOrder(
            order.copyWith(comments: [...order.comments, comment]),
            isNew: false,
          );
        },
      ),
      children: [
        _PricingCard(order: order, money: money),
        _DetailsCard(
          order: order,
          businessName: business?.name,
          productName: product?.name ?? order.productName,
          productId: product?.id,
          customerName: customer?.name,
          customerId: customer?.id,
        ),
      ],
    );
  }
}

/// Every figure that makes up the order, with the totals set apart.
class _PricingCard extends StatelessWidget {
  const _PricingCard({required this.order, required this.money});

  final Order order;
  final String Function(Money) money;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SectionCard(
      title: 'Pricing',
      subtitle: order.isRecognised
          ? 'How this order adds up'
          : 'This order is ${order.status.label.toLowerCase()}, so it '
              'doesn\'t count towards revenue or profit',
      child: Column(
        children: [
          _Line('Selling cost', money(order.sellingCost)),
          _Line('Discount', money(order.discount)),
          _Line('Shipping revenue', money(order.shippingRevenue)),
          _Line('Other revenue', money(order.otherRevenue)),
          const Divider(height: AppSpacing.xl),
          _Line('Total revenue', money(order.recognisedRevenue), total: true),
          if (order.isRefunded)
            _Line('Refund', money(order.effectiveRefund), tone: t.error),
          _Line('Product cost', money(order.recognisedProductCost)),
          const Divider(height: AppSpacing.xl),
          _Line(
            'Gross profit',
            money(order.recognisedGrossProfit),
            total: true,
            tone: order.recognisedGrossProfit.isNegative ? t.error : t.success,
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value, {this.total = false, this.tone});

  final String label;
  final String value;
  final bool total;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: total ? 14 : 13.5,
                    fontWeight: total ? FontWeight.w600 : FontWeight.w400,
                    color: total ? t.textPrimary : t.textSecondary)),
          ),
          Text(value,
              style: TextStyle(
                  fontSize: total ? 16 : 14,
                  fontWeight: total ? FontWeight.w700 : FontWeight.w500,
                  color: tone ?? t.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ],
      ),
    );
  }
}

class _DetailsCard extends StatelessWidget {
  const _DetailsCard({
    required this.order,
    required this.businessName,
    required this.productName,
    required this.productId,
    required this.customerName,
    required this.customerId,
  });

  final Order order;
  final String? businessName;
  final String productName;
  final String? productId;
  final String? customerName;
  final String? customerId;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final fields = <DetailField>[
      DetailField('Order ID', order.id, Icons.badge_outlined),
      DetailField('Business', businessName ?? '—', Icons.business_outlined),
      DetailField('Product', productName, Icons.inventory_2_outlined),
      DetailField(
          'Order Date',
          order.orderDate == null ? '—' : AppDate.format(order.orderDate),
          Icons.event_outlined),
      DetailField(
          'Customer',
          customerName ??
              (order.customerReference.isEmpty
                  ? '—'
                  : order.customerReference),
          Icons.person_outline),
      if (order.isRefunded)
        DetailField(
            'Refund Date',
            order.refundDate == null ? '—' : AppDate.format(order.refundDate),
            Icons.assignment_return_outlined),
    ];
    final linkStyle = OutlinedButton.styleFrom(
      foregroundColor: t.primary,
      side: BorderSide(color: t.primary),
    );

    return SectionCard(
      title: 'Order details',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DetailGrid(fields: fields),
          if (productId != null || customerId != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.lg),
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  if (productId != null)
                    OutlinedButton.icon(
                      onPressed: () =>
                          context.go(Routes.productDetailPath(productId!)),
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: const Text('View product'),
                      style: linkStyle,
                    ),
                  if (customerId != null)
                    OutlinedButton.icon(
                      onPressed: () =>
                          context.go(Routes.customerDetailPath(customerId!)),
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: const Text('View customer'),
                      style: linkStyle,
                    ),
                ],
              ),
            ),
          if (order.notes.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: t.surfaceAlt,
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Notes',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: t.textSecondary)),
                  const SizedBox(height: 4),
                  Text(order.notes,
                      style: const TextStyle(fontSize: 14, height: 1.4)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
