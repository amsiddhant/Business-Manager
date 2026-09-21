import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/enums.dart';
import '../../core/permissions.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/money.dart';
import '../../models/order.dart';
import '../../state/app_state.dart';
import '../../state/data_controller.dart';
import '../../widgets/common/app_card.dart';
import '../../widgets/common/comment_thread.dart';
import '../../widgets/common/detail_widgets.dart';
import '../../widgets/common/page_header.dart';
import '../../widgets/common/state_views.dart';
import '../../widgets/common/status_badge.dart';
import 'orders_screen.dart';

/// A single order view: revenue/cost breakdown, linked product, business and
/// customer, plus a comment thread. Linked entities resolve through the
/// access-scoped [DataController].
class OrderDetailScreen extends StatelessWidget {
  const OrderDetailScreen({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataController>();
    final appState = context.watch<AppState>();
    final user = appState.currentUser;

    if (data.loading && !data.loaded) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(title: 'Order'),
          SizedBox(height: 48),
          LoadingView(),
        ],
      );
    }

    final order = data.orderById(orderId);
    if (order == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(
            title: 'Order',
            actions: [
              OutlinedButton.icon(
                onPressed: () => context.go(Routes.orders),
                icon: const Icon(Icons.arrow_back, size: 18),
                label: const Text('Back to Orders'),
              ),
            ],
          ),
          const SizedBox(height: 48),
          const EmptyView(
            icon: Icons.search_off,
            title: 'Order not found',
            message: 'This order may have been removed or is not accessible.',
          ),
        ],
      );
    }

    final business = data.businessById(order.businessId);
    final product = data.productById(order.productId);
    final customer = order.customerReference.isEmpty
        ? null
        : data.customerById(order.customerReference);
    final currency = business?.currency ?? CurrencyCode.inr;
    final canEdit = user?.can(Permission.editOrder) ?? false;

    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SummaryCard(
          order: order,
          currency: currency,
          businessName: business?.name,
          productName: product?.name ?? order.productName,
          productId: product?.id,
          customerName: customer?.name,
          customerId: customer?.id,
        ),
      ],
    );

    final repo = appState.repository;
    final right = DetailActivityColumn(
      activityAt: order.lastActivityAt,
      comments: order.comments,
      canComment: canEdit,
      onPost: (comment) async {
        await repo.saveOrder(
          order.copyWith(comments: [...order.comments, comment]),
          isNew: false,
        );
        await data.refresh();
      },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: 'Order ${order.id}',
          subtitle: order.productName,
          actions: [
            OutlinedButton.icon(
              onPressed: () => context.go(Routes.orders),
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('Back'),
            ),
            if (canEdit)
              ElevatedButton.icon(
                onPressed: () =>
                    OrdersScreen.openForm(context, order, order.businessId),
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
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.order,
    required this.currency,
    required this.businessName,
    required this.productName,
    required this.productId,
    required this.customerName,
    required this.customerId,
  });

  final Order order;
  final CurrencyCode currency;
  final String? businessName;
  final String productName;
  final String? productId;
  final String? customerName;
  final String? customerId;

  @override
  Widget build(BuildContext context) {
    final metrics = <_Metric>[
      _Metric('Quantity', '${order.quantity}'),
      _Metric('Selling Cost',
          MoneyFormatter.format(order.sellingCost, currency)),
      _Metric('Discount', MoneyFormatter.format(order.discount, currency)),
      _Metric('Shipping Rev.',
          MoneyFormatter.format(order.shippingRevenue, currency)),
      _Metric('Other Rev.',
          MoneyFormatter.format(order.otherRevenue, currency)),
      _Metric('Total Revenue',
          MoneyFormatter.format(order.recognisedRevenue, currency)),
      _Metric('Product Cost',
          MoneyFormatter.format(order.recognisedProductCost, currency)),
      _Metric('Gross Profit',
          MoneyFormatter.format(order.recognisedGrossProfit, currency),
          tone: order.recognisedGrossProfit.isNegative
              ? AppColors.error
              : AppColors.success),
    ];
    if (order.isRefunded) {
      metrics.add(_Metric(
          'Refund', MoneyFormatter.format(order.effectiveRefund, currency),
          tone: AppColors.error));
    }

    final fields = <DetailField>[
      DetailField('Order ID', order.id, Icons.badge_outlined),
      DetailField('Business', businessName ?? '—', Icons.business_outlined),
      DetailField('Product', productName, Icons.inventory_2_outlined),
      DetailField(
          'Order Date',
          order.orderDate == null ? '—' : AppDate.format(order.orderDate),
          Icons.event_outlined),
      DetailField('Customer',
          customerName ?? (order.customerReference.isEmpty ? '—' : order.customerReference),
          Icons.person_outline),
      if (order.isRefunded)
        DetailField(
            'Refund Date',
            order.refundDate == null ? '—' : AppDate.format(order.refundDate),
            Icons.assignment_return_outlined),
    ];

    return SectionCard(
      title: 'Order Summary',
      trailing: StatusBadge.order(order.status),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = MediaQuery.sizeOf(context).width < 700 ? 2 : 4;
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
          const SizedBox(height: AppSpacing.lg),
          DetailGrid(fields: fields),
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
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
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                    ),
                  ),
                if (customerId != null)
                  OutlinedButton.icon(
                    onPressed: () =>
                        context.go(Routes.customerDetailPath(customerId!)),
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('View customer'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                    ),
                  ),
              ],
            ),
          ),
          if (order.notes.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            const Text('Notes',
                style:
                    TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 2),
            Text(order.notes,
                style: const TextStyle(fontSize: 14, height: 1.4)),
          ],
        ],
      ),
    );
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
          Text(metric.value,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: metric.tone ?? AppColors.textPrimary)),
        ],
      ),
    );
  }
}
