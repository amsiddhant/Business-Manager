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
import '../../core/validators.dart';
import '../../data/repository.dart';
import '../../models/customer.dart';
import '../../models/order.dart';
import '../../models/product.dart';
import '../../state/app_state.dart';
import '../../state/data_controller.dart';
import '../../state/filter_controller.dart';
import '../../state/org_settings.dart';
import '../../widgets/common/confirm_dialog.dart';
import '../../widgets/common/currency_display.dart';
import '../../widgets/common/page_header.dart';
import '../../widgets/common/state_views.dart';
import '../../widgets/common/status_badge.dart';
import '../../widgets/forms/app_form.dart';
import '../../widgets/forms/form_dialog.dart';
import '../../widgets/forms/form_fields.dart';
import '../../widgets/forms/form_section.dart';
import '../../widgets/forms/suggestion_chips.dart';
import '../../services/profit_calculation_service.dart';
import '../../services/smart/suggestion_service.dart';
import '../../widgets/data/app_data_grid.dart';
import '../../widgets/layout/app_page.dart';
import '../../widgets/layout/kpi_strip.dart';

/// Lists orders for the selected scope with full CRUD gated by permission:
/// headline figures, status quick filters, column filters, saved views,
/// bulk status changes and deletes, and CSV export of the view.
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();

  /// Opens the order form: [existing] to edit, or a new order — prefilled
  /// from [duplicateOf] when given.
  static Future<void> openForm(
      BuildContext context, Order? existing, String? selectedBizId,
      {Order? duplicateOf}) async {
    final data = context.read<DataController>();
    final repo = context.read<AppState>().repository;
    if (existing == null && data.products.isEmpty) {
      showErrorSnack(context, 'Create a product before adding orders.');
      return;
    }
    final saved = await showAppForm<bool>(
      context: context,
      builder: (_) => _OrderFormDialog(
        existing: existing,
        template: duplicateOf,
        repo: repo,
        allProducts: data.products,
        allCustomers: data.customers,
        preselectBusinessId: selectedBizId,
      ),
    );
    if (saved == true) {
      if (context.mounted) {
        showSuccessSnack(
            context,
            existing == null
                ? 'Order created successfully'
                : 'Order updated successfully');
      }
    }
  }
}

class _OrdersScreenState extends State<OrdersScreen> {
  static final _epoch = DateTime.fromMillisecondsSinceEpoch(0);
  static DateTime _dateOf(Order o) =>
      o.orderDate ?? o.audit.createdAt ?? _epoch;

  static const _service = ProfitCalculationService();

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataController>();
    final filter = context.watch<FilterController>();
    final appState = context.watch<AppState>();
    final user = appState.currentUser;

    if (data.loading && !data.loaded) {
      return const _Loading();
    }
    if (data.error != null && !data.loaded) {
      return AppPage(
        children: [
          const PageHeader(title: 'Orders', icon: Icons.receipt_long_outlined),
          const SizedBox(height: 48),
          ErrorView(message: data.error!, onRetry: () => data.refresh()),
        ],
      );
    }

    final bizId = filter.selectedBusinessId;
    final orders = [...data.ordersFor(bizId)]
      ..sort((a, b) => _dateOf(b).compareTo(_dateOf(a)));
    final canCreate = user?.can(Permission.createOrder) ?? false;
    final canEdit = user?.can(Permission.editOrder) ?? false;
    final canDelete = user?.can(Permission.deleteOrder) ?? false;
    final repo = appState.repository;

    CurrencyCode currencyOf(Order o) => _currencyFor(data, o.businessId);
    String customerOf(Order o) => o.customerReference.isEmpty
        ? ''
        : data.customerById(o.customerReference)?.name ?? o.customerReference;
    String businessOf(Order o) => data.businessById(o.businessId)?.name ?? '';
    // Figures are shown in the selected business's currency; INR for all.
    final pageCurrency =
        (bizId == null ? null : data.businessById(bizId))?.currency ??
            CurrencyCode.inr;
    String money(Money m) => MoneyFormatter.compact(m, pageCurrency);

    final summary = _service.summariseOrders(orders);
    final t = context.tokens;
    final margin = summary.grossMargin;

    final addButton = canCreate
        ? FilledButton.icon(
            onPressed: () => OrdersScreen.openForm(context, null, bizId),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Order'),
          )
        : null;

    return AppPage.slivers(
      slivers: [
        SliverToBoxAdapter(
          child: PageHeader(
            title: 'Orders',
            icon: Icons.receipt_long_outlined,
            count: orders.length,
            subtitle: 'Record sales and track order revenue',
            actions: [?addButton],
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
        if (orders.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: KpiStrip(items: [
              KpiItem(
                label: 'Revenue',
                value: money(summary.revenue),
                icon: Icons.trending_up,
                caption: 'Net of refunds',
                tooltip: 'Recognised revenue of these orders: cancelled '
                    'orders excluded, refunds subtracted.',
              ),
              KpiItem(
                label: 'Gross profit',
                value: money(summary.grossProfit),
                icon: Icons.savings_outlined,
                tone: summary.grossProfit.isNegative ? t.error : t.success,
                caption: margin == null
                    ? null
                    : '${margin.toStringAsFixed(1)}% margin',
                tooltip: 'Revenue minus product cost, for recognised orders.',
              ),
              KpiItem(
                label: 'Orders',
                value: '${summary.count}',
                icon: Icons.receipt_long_outlined,
                caption: summary.cancelledCount == 0
                    ? '${summary.units} units sold'
                    : '${summary.cancelledCount} cancelled',
              ),
              KpiItem(
                label: 'Avg. order value',
                value: money(summary.averageOrderValue),
                icon: Icons.shopping_bag_outlined,
                tooltip: 'Revenue ÷ orders that count towards revenue.',
              ),
              KpiItem(
                label: 'Refunds',
                value: money(summary.refunds),
                icon: Icons.assignment_return_outlined,
                tone: summary.refunds.isPositive ? t.warning : null,
                caption: '${summary.refundedCount} returned',
              ),
            ]),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
        ],
        SliverAppDataGrid<Order>(
          gridId: 'orders',
          rows: orders,
          rowKey: (o) => o.id,
          exportName: 'orders',
          searchHint: 'Search by ID, product, customer or status…',
          searchText: (o) => '${o.id} ${o.productName} ${o.customerReference} '
              '${customerOf(o)} ${o.status.label}',
          onRowTap: (o) => context.go(Routes.orderDetailPath(o.id)),
          quickFilters: [
            for (final s in OrderStatus.values)
              GridQuickFilter<Order>(
                id: s.wire,
                label: s.label,
                test: (o) => o.status == s,
              ),
          ],
          bulkActions: [
            if (canEdit)
              GridBulkAction<Order>(
                label: 'Change status',
                icon: Icons.swap_horiz,
                children: [
                  for (final s in OrderStatus.values)
                    if (s != OrderStatus.returned)
                      GridBulkAction<Order>(
                        label: s.label,
                        icon: s.contributesToRevenue
                            ? Icons.check_circle_outline
                            : Icons.cancel_outlined,
                        allowed: (o) => o.status != s,
                        onRun: (context, rows) =>
                            _bulkStatus(context, repo, rows, s),
                      ),
                ],
              ),
            if (canDelete)
              GridBulkAction<Order>(
                label: 'Delete',
                icon: Icons.delete_outline,
                destructive: true,
                onRun: (context, rows) => _bulkDelete(context, repo, rows),
              ),
          ],
          emptyTitle: 'No orders yet',
          emptyIcon: Icons.receipt_long_outlined,
          emptyMessage: canCreate
              ? 'Record your first order to start tracking revenue.'
              : 'Orders will appear here once added.',
          emptyAction: addButton,
          columns: [
            GridColumn(
              id: 'id',
              label: 'Order ID',
              pinned: true,
              cardRole: CardRole.subtitle,
              minWidth: 110,
              cell: (o) => Text(o.id,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              sortValue: (o) => o.id,
              exportValue: (o) => o.id,
            ),
            GridColumn(
              id: 'product',
              label: 'Product',
              flex: 2,
              cardRole: CardRole.title,
              cell: (o) => Text(o.productName,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              sortValue: (o) => o.productName.toLowerCase(),
              exportValue: (o) => o.productName,
              filter: GridFilter.choice((o) => o.productName),
            ),
            GridColumn(
              id: 'customer',
              label: 'Customer',
              flex: 2,
              cardRole: CardRole.meta,
              cell: (o) {
                final name = customerOf(o);
                return Text(name.isEmpty ? '—' : name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: name.isEmpty
                        ? TextStyle(color: context.tokens.textTertiary)
                        : null);
              },
              sortValue: (o) => customerOf(o).toLowerCase(),
              exportValue: customerOf,
              filter: GridFilter.choice(
                  (o) => customerOf(o).isEmpty ? 'No customer' : customerOf(o)),
            ),
            GridColumn(
              id: 'business',
              label: 'Business',
              visibleByDefault: false,
              cardRole: CardRole.meta,
              cell: (o) => Text(businessOf(o),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              sortValue: (o) => businessOf(o).toLowerCase(),
              exportValue: businessOf,
              filter: GridFilter.choice(businessOf),
            ),
            GridColumn(
              id: 'date',
              label: 'Date',
              cardRole: CardRole.meta,
              minWidth: 110,
              cell: (o) => Text(AppDate.format(_dateOf(o))),
              sortValue: (o) => _dateOf(o).millisecondsSinceEpoch,
              exportValue: (o) => AppDate.format(_dateOf(o)),
              filter: GridFilter.dateRange((o) => _dateOf(o)),
            ),
            GridColumn(
              id: 'qty',
              label: 'Qty',
              numeric: true,
              minWidth: 64,
              cardRole: CardRole.meta,
              cell: (o) => Text('${o.quantity}'),
              sortValue: (o) => o.quantity,
              exportValue: (o) => '${o.quantity}',
              footer: (rows) => '${rows.fold<int>(0, (n, o) => n + o.quantity)}',
            ),
            GridColumn(
              id: 'revenue',
              label: 'Revenue',
              numeric: true,
              cardRole: CardRole.metric,
              tooltip: 'Recognised revenue, net of any refund',
              cell: (o) => _RevenueCell(order: o, currency: currencyOf(o)),
              sortValue: (o) => o.recognisedRevenue.minor,
              exportValue: (o) => o.recognisedRevenue.major.toStringAsFixed(2),
              filter: GridFilter.numberRange((o) => o.recognisedRevenue.major),
              footer: (rows) =>
                  money(_service.summariseOrders(rows).revenue),
            ),
            GridColumn(
              id: 'cost',
              label: 'Cost',
              numeric: true,
              cardRole: CardRole.metric,
              cell: (o) => CurrencyText(o.recognisedProductCost,
                  currency: currencyOf(o)),
              sortValue: (o) => o.recognisedProductCost.minor,
              exportValue: (o) =>
                  o.recognisedProductCost.major.toStringAsFixed(2),
            ),
            GridColumn(
              id: 'profit',
              label: 'Profit',
              numeric: true,
              cardRole: CardRole.metric,
              cell: (o) => CurrencyText(o.recognisedGrossProfit,
                  currency: currencyOf(o)),
              sortValue: (o) => o.recognisedGrossProfit.minor,
              exportValue: (o) =>
                  o.recognisedGrossProfit.major.toStringAsFixed(2),
              filter: GridFilter.numberRange(
                  (o) => o.recognisedGrossProfit.major),
              footer: (rows) =>
                  money(_service.summariseOrders(rows).grossProfit),
            ),
            GridColumn(
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
            GridColumn(
              id: 'actions',
              label: '',
              pinned: true,
              cardRole: CardRole.actions,
              // Edit, More and Delete (48 px each) plus the cell padding.
              minWidth: 2 * AppSpacing.md +
                  48 * [canEdit, canEdit || canCreate, canDelete].where((b) => b).length,
              cell: (o) => _RowActions(
                order: o,
                canCreate: canCreate,
                canEdit: canEdit,
                canDelete: canDelete,
              ),
            ),
          ],
        ),
      ],
    );
  }

  static CurrencyCode _currencyFor(DataController data, String businessId) =>
      data.businessById(businessId)?.currency ?? CurrencyCode.inr;

  static Future<void> _bulkStatus(BuildContext context, Repository repo,
      List<Order> rows, OrderStatus status) async {
    if (!status.contributesToRevenue) {
      final ok = await showConfirmDialog(
        context,
        title: 'Cancel ${_plural(rows.length)}?',
        message: 'Their revenue and product cost will be excluded from all '
            'profit calculations.',
        confirmLabel: 'Cancel orders',
      );
      if (!ok || !context.mounted) return;
    }
    await runGridBulk<Order>(
      context,
      rows: rows,
      verb: 'Updating',
      noun: 'orders',
      describe: (o) => o.id,
      task: (o) {
        var updated = o.copyWith(status: status);
        // A returned order moved to another status loses its refund.
        if (o.isRefunded) updated = _withoutRefund(updated);
        return repo.saveOrder(updated, isNew: false);
      },
    );
  }

  static Future<void> _bulkDelete(
      BuildContext context, Repository repo, List<Order> rows) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Delete ${_plural(rows.length)}?',
      message: 'This removes them for everyone and cannot be easily undone.',
    );
    if (!ok || !context.mounted) return;
    await runGridBulk<Order>(
      context,
      rows: rows,
      verb: 'Deleting',
      noun: 'orders',
      describe: (o) => o.id,
      task: (o) => repo.deleteOrder(o.id, known: o),
    );
  }

  static String _plural(int n) => n == 1 ? '1 order' : '$n orders';
}

/// [order] without its recorded refund (copyWith can't null a field).
Order _withoutRefund(Order order) => Order(
      id: order.id,
      businessId: order.businessId,
      productId: order.productId,
      productName: order.productName,
      orderDate: order.orderDate,
      quantity: order.quantity,
      sellingCost: order.sellingCost,
      discount: order.discount,
      shippingRevenue: order.shippingRevenue,
      otherRevenue: order.otherRevenue,
      buyingCost: order.buyingCost,
      marketingAllocation: order.marketingAllocation,
      status: order.status,
      customerReference: order.customerReference,
      notes: order.notes,
      comments: order.comments,
      audit: order.audit,
    );

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) => const AppPage(
        children: [
          PageHeader(title: 'Orders', icon: Icons.receipt_long_outlined),
          SizedBox(height: AppSpacing.lg),
          SkeletonCard(lines: 1, height: 88),
          SizedBox(height: AppSpacing.lg),
          SkeletonCard(lines: 8),
        ],
      );
}

class _RowActions extends StatelessWidget {
  const _RowActions({
    required this.order,
    required this.canCreate,
    required this.canEdit,
    required this.canDelete,
  });

  final Order order;
  final bool canCreate;
  final bool canEdit;
  final bool canDelete;

  @override
  Widget build(BuildContext context) {
    if (!canEdit && !canDelete && !canCreate) return const SizedBox.shrink();
    // Statuses that remove the order from recognised revenue/cost.
    final canCancel = canEdit && order.status != OrderStatus.cancelled;
    final canReturn = canEdit && order.status != OrderStatus.returned;
    final canReinstate = canEdit && !order.status.contributesToRevenue;
    final hasMenu = canCreate || canCancel || canReturn || canReinstate;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (canEdit)
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined, size: 18),
            onPressed: () =>
                OrdersScreen.openForm(context, order, order.businessId),
          ),
        if (hasMenu)
          PopupMenuButton<_OrderAction>(
            tooltip: 'More actions',
            icon: const Icon(Icons.more_vert, size: 18),
            onSelected: (action) => _runAction(context, action),
            itemBuilder: (_) => [
              if (canCreate)
                const PopupMenuItem(
                  value: _OrderAction.duplicate,
                  child: _ActionRow(
                      icon: Icons.copy_all_outlined, label: 'Duplicate'),
                ),
              if (canCancel)
                const PopupMenuItem(
                  value: _OrderAction.cancel,
                  child: _ActionRow(
                      icon: Icons.cancel_outlined, label: 'Cancel order'),
                ),
              if (canReturn)
                const PopupMenuItem(
                  value: _OrderAction.returnRefund,
                  child: _ActionRow(
                      icon: Icons.assignment_return_outlined,
                      label: 'Return / Refund'),
                ),
              if (canReinstate)
                const PopupMenuItem(
                  value: _OrderAction.reinstate,
                  child: _ActionRow(
                      icon: Icons.restart_alt, label: 'Reinstate order'),
                ),
            ],
          ),
        if (canDelete)
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: () => _delete(context),
          ),
      ],
    );
  }

  Future<void> _runAction(BuildContext context, _OrderAction action) async {
    switch (action) {
      case _OrderAction.duplicate:
        await OrderActions.duplicate(context, order);
      case _OrderAction.cancel:
        await OrderActions.cancel(context, order);
      case _OrderAction.returnRefund:
        await OrderActions.returnRefund(context, order);
      case _OrderAction.reinstate:
        await OrderActions.reinstate(context, order);
    }
  }

  Future<void> _delete(BuildContext context) =>
      OrderActions.delete(context, order);
}

/// The single-order actions, shared by the list rows and the detail page.
/// Each asks for confirmation, saves, and reports the outcome in a snack.
class OrderActions {
  OrderActions._();

  static Future<void> duplicate(BuildContext context, Order order) =>
      OrdersScreen.openForm(context, null, order.businessId,
          duplicateOf: order);

  static Future<void> cancel(BuildContext context, Order order) =>
      _changeStatus(
        context,
        order,
        OrderStatus.cancelled,
        title: 'Cancel order?',
        message: 'Cancel order ${order.id}? Its revenue and product cost '
            'will be excluded from all profit calculations.',
        success: 'Order cancelled — excluded from revenue',
      );

  /// Clears any recorded refund so reinstated revenue/cost count in full.
  static Future<void> reinstate(BuildContext context, Order order) =>
      _changeStatus(
        context,
        order,
        OrderStatus.confirmed,
        title: 'Reinstate order?',
        message: 'Reinstate order ${order.id} as confirmed? Its revenue and '
            'product cost will count towards profit calculations again.',
        success: 'Order reinstated — counted in revenue',
        clearRefund: true,
      );

  /// Opens the refund dialog and, if confirmed, marks the order returned with
  /// the captured refund amount and date.
  static Future<void> returnRefund(BuildContext context, Order order) async {
    final data = context.read<DataController>();
    final repo = context.read<AppState>().repository;
    final currency =
        data.businessById(order.businessId)?.currency ?? CurrencyCode.inr;
    final result = await showDialog<_RefundResult>(
      context: context,
      builder: (_) => _RefundDialog(order: order, currency: currency),
    );
    if (result == null) return;
    try {
      await repo.saveOrder(
        order.copyWith(
          status: OrderStatus.returned,
          refundAmount: result.amount,
          refundDate: result.date,
        ),
        isNew: false,
      );
      if (context.mounted) {
        final full = result.amount >= order.totalRevenue;
        showSuccessSnack(
            context,
            full
                ? 'Order fully refunded — revenue reversed'
                : 'Order partially refunded — recognised revenue reduced');
      }
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e);
    }
  }

  static Future<void> _changeStatus(
    BuildContext context,
    Order order,
    OrderStatus status, {
    required String title,
    required String message,
    required String success,
    bool clearRefund = false,
  }) async {
    final repo = context.read<AppState>().repository;
    final ok = await showConfirmDialog(
      context,
      title: title,
      message: message,
      confirmLabel: 'Confirm',
      destructive: !status.contributesToRevenue,
    );
    if (ok != true) return;
    try {
      var updated = order.copyWith(status: status);
      if (clearRefund) updated = _withoutRefund(updated);
      await repo.saveOrder(updated, isNew: false);
      if (context.mounted) showSuccessSnack(context, success);
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e);
    }
  }

  /// Returns true when the order was deleted.
  static Future<bool> delete(BuildContext context, Order order) async {
    final repo = context.read<AppState>().repository;
    final ok = await showConfirmDialog(
      context,
      title: 'Delete order?',
      message: 'Delete order ${order.id}? This action cannot be easily undone.',
    );
    if (ok != true) return false;
    try {
      await repo.deleteOrder(order.id, known: order);
      if (context.mounted) showSuccessSnack(context, 'Order deleted');
      return true;
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e);
      return false;
    }
  }
}

/// Quick status changes available from the orders row overflow menu.
enum _OrderAction { duplicate, cancel, returnRefund, reinstate }

/// A leading-icon + label row used inside the order actions popup menu.
class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: AppSpacing.sm),
        Text(label),
      ],
    );
  }
}

/// Revenue table cell that shows the recognised (net-of-refund) revenue and,
/// for refunded orders, the original gross amount struck through as a tooltip.
class _RevenueCell extends StatelessWidget {
  const _RevenueCell({required this.order, required this.currency});

  final Order order;
  final CurrencyCode currency;

  @override
  Widget build(BuildContext context) {
    final net = CurrencyText(order.recognisedRevenue, currency: currency);
    if (!order.isRefunded) return net;
    return Tooltip(
      message: 'Refunded ${MoneyFormatter.format(order.effectiveRefund, currency)}'
          ' of ${MoneyFormatter.format(order.totalRevenue, currency)}',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          net,
          const SizedBox(width: 4),
          Icon(Icons.info_outline,
              size: 13, color: context.tokens.textTertiary),
        ],
      ),
    );
  }
}

/// The captured result of the refund dialog.
class _RefundResult {
  const _RefundResult(this.amount, this.date);
  final Money amount;
  final DateTime date;
}

/// Dialog to record a full or partial refund against an order. Prefills the
/// full order revenue; the user can reduce it for a partial refund.
class _RefundDialog extends StatefulWidget {
  const _RefundDialog({required this.order, required this.currency});

  final Order order;
  final CurrencyCode currency;

  @override
  State<_RefundDialog> createState() => _RefundDialogState();
}

class _RefundDialogState extends State<_RefundDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late DateTime _date;

  Money get _total => widget.order.totalRevenue;

  @override
  void initState() {
    super.initState();
    // Prefill with any existing refund, otherwise the full order revenue.
    final initial =
        widget.order.refundAmount.isPositive ? widget.order.refundAmount : _total;
    _amount = TextEditingController(text: initial.major.toString());
    _date = widget.order.refundDate ?? DateTime.now();
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Money get _entered => Money.parse(_amount.text);

  @override
  Widget build(BuildContext context) {
    final c = widget.currency;
    final entered = _entered;
    final retained = _total - entered;
    final isFull = entered >= _total;
    return FormDialog(
      title: 'Return / Refund',
      submitLabel: 'Record refund',
      onSubmit: _submit,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Order ${widget.order.id} · ${widget.order.productName}',
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13.5)),
            const SizedBox(height: 4),
            Text('Order revenue: ${MoneyFormatter.format(_total, c)}',
                style: TextStyle(color: context.tokens.textSecondary)),
            const FormGap(),
            FormRow([
              AppMoneyField(
                symbol: c.symbol,
                label: 'Refund Amount',
                controller: _amount,
                isRequired: true,
                onChanged: (_) => setState(() {}),
                validator: (v) {
                  final base = Validators.nonNegativeNumber(v, field: 'Refund');
                  if (base != null) return base;
                  if (Money.parse(v ?? '') > _total) {
                    return 'Cannot exceed order revenue';
                  }
                  return null;
                },
                helper: 'Full or partial. Max ${MoneyFormatter.format(_total, c)}.',
              ),
              AppDateField(
                label: 'Refund Date',
                value: _date,
                onChanged: (v) => setState(() => _date = v ?? _date),
              ),
            ]),
            const FormGap(),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: context.tokens.background,
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                border: Border.all(color: context.tokens.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isFull ? 'Full refund' : 'Partial refund',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Recognised revenue after refund: '
                    '${MoneyFormatter.format(retained.isNegative ? Money.zero : retained, c)}. '
                    'Returned units are treated as restocked, so product cost '
                    'is reversed proportionally.',
                    style: TextStyle(
                        color: context.tokens.textSecondary, fontSize: 12.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return false;
    var amount = _entered;
    if (amount > _total) amount = _total;
    // This dialog returns a payload (not a bool), so it pops itself with the
    // result. Return false so FormDialog does NOT pop a second time — a double
    // pop would tear down the page beneath and leave a blank screen.
    Navigator.of(context).pop(_RefundResult(amount, _date));
    return false;
  }
}

class _OrderFormDialog extends StatefulWidget {
  const _OrderFormDialog({
    required this.existing,
    this.template,
    required this.repo,
    required this.allProducts,
    required this.allCustomers,
    this.preselectBusinessId,
  });

  final Order? existing;

  /// A new order copies this one's product, figures, customer and notes.
  final Order? template;
  final Repository repo;
  final List<Product> allProducts;
  final List<Customer> allCustomers;
  final String? preselectBusinessId;

  @override
  State<_OrderFormDialog> createState() => _OrderFormDialogState();
}

class _OrderFormDialogState extends State<_OrderFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _quantity;
  late final TextEditingController _selling;
  late final TextEditingController _discount;
  late final TextEditingController _shipping;
  late final TextEditingController _other;
  late final TextEditingController _buying;
  late final TextEditingController _notes;
  late OrderStatus _status;
  DateTime? _orderDate;
  String? _productId;
  // The picked customer's id (stored into Order.customerReference). Legacy
  // free-text references that don't resolve to a known customer are preserved
  // in [_rawCustomerRef] so editing an order never silently wipes them.
  String? _customerId;
  String _rawCustomerRef = '';

  Order? get _existing => widget.existing;

  static const _suggest = DartSuggestionProvider();

  @override
  void initState() {
    super.initState();
    final o = _existing ?? widget.template;
    _quantity = TextEditingController(text: '${o?.quantity ?? 1}');
    _selling = TextEditingController(
        text: o == null || o.sellingCost.isZero
            ? ''
            : o.sellingCost.major.toString());
    _discount = TextEditingController(
        text: o == null || o.discount.isZero
            ? ''
            : o.discount.major.toString());
    _shipping = TextEditingController(
        text: o == null || o.shippingRevenue.isZero
            ? ''
            : o.shippingRevenue.major.toString());
    _other = TextEditingController(
        text: o == null || o.otherRevenue.isZero
            ? ''
            : o.otherRevenue.major.toString());
    _buying = TextEditingController(
        text: o == null || o.buyingCost.isZero
            ? ''
            : o.buyingCost.major.toString());
    _notes = TextEditingController(text: o?.notes ?? '');
    // A new order starts with the organisation's default status, if it has one.
    _status = _existing?.status ??
        context.readOrgSettings().defaults.orderStatus ??
        OrderStatus.confirmed;
    _orderDate = _existing == null
        ? (widget.template == null ? null : DateTime.now())
        : _existing!.orderDate ?? _existing!.audit.createdAt;
    _productId = o?.productId ?? _initialProductId();
    // Resolve the stored customer reference against known customers. If it
    // matches a customer id, preselect it; otherwise keep it as raw text so a
    // legacy free-text reference survives an edit round-trip.
    final ref = o?.customerReference.trim() ?? '';
    if (ref.isNotEmpty &&
        widget.allCustomers.any((c) => c.id == ref)) {
      _customerId = ref;
    } else {
      _rawCustomerRef = ref;
    }
    // Prefill prices from the selected product for a new order.
    if (o == null && _productId != null) {
      _applyProductDefaults(_productId!);
    }
  }

  /// The business of the currently selected product (drives customer scoping).
  String? get _selectedBusinessId =>
      widget.allProducts.where((p) => p.id == _productId).firstOrNull?.businessId;

  /// Customers tagged to the selected product's business, for the picker.
  List<Customer> get _scopedCustomers {
    final bizId = _selectedBusinessId;
    if (bizId == null) return const [];
    return widget.allCustomers
        .where((c) => c.businessIds.contains(bizId))
        .toList();
  }

  /// Label for a customer picker entry. Empty id is the "no customer" option.
  String _customerLabel(String id) {
    if (id.isEmpty) return 'No customer';
    return widget.allCustomers.where((c) => c.id == id).firstOrNull?.name ?? id;
  }

  /// Contextual helper text under the customer picker.
  String? _customerHelper() {
    if (_selectedBusinessId == null) {
      return 'Select a product first to choose a customer.';
    }
    if (_scopedCustomers.isEmpty) {
      return 'No customers for this business yet. Optional.';
    }
    if (_rawCustomerRef.isNotEmpty && _customerId == null) {
      return 'Existing reference "$_rawCustomerRef" will be kept unless changed.';
    }
    return 'Optional — links this order to a customer.';
  }

  /// The value written to Order.customerReference: the picked customer id, or
  /// the preserved legacy free-text reference, or empty.
  String get _customerReference => _customerId ?? _rawCustomerRef;

  String? _initialProductId() {
    final scoped = _scopedProducts();
    return scoped.isNotEmpty ? scoped.first.id : null;
  }

  List<Product> _scopedProducts() {
    final bizId = widget.preselectBusinessId;
    return bizId == null
        ? widget.allProducts
        : widget.allProducts.where((p) => p.businessId == bizId).toList();
  }

  void _applyProductDefaults(String productId) {
    final product =
        widget.allProducts.where((p) => p.id == productId).firstOrNull;
    if (product == null) return;
    if (_selling.text.isEmpty && product.sellingPrice.isPositive) {
      _selling.text = product.sellingPrice.major.toString();
    }
    if (_buying.text.isEmpty && product.buyingPrice.isPositive) {
      _buying.text = product.buyingPrice.major.toString();
    }
  }

  @override
  void dispose() {
    _quantity.dispose();
    _selling.dispose();
    _discount.dispose();
    _shipping.dispose();
    _other.dispose();
    _buying.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isNew = _existing == null;
    final bizId = _selectedBusinessId;
    final currency = context.select<DataController, CurrencyCode>((d) =>
        (bizId == null ? null : d.businessById(bizId))?.currency ??
        CurrencyCode.inr);
    final symbol = currency.symbol;
    final orders =
        context.select<DataController, List<Order>>((d) => d.ordersFor(null));
    final productId = _productId;
    final prices = isNew && productId != null
        ? _suggest.orderPrice(productId: productId, history: orders)
        : const <Suggestion<Money>>[];
    return FormDialog(
      title: isNew
          ? (widget.template == null ? 'Add Order' : 'Duplicate Order')
          : 'Edit Order',
      subtitle: widget.template == null
          ? null
          : 'A new order, copied from ${widget.template!.id}',
      icon: Icons.receipt_long_outlined,
      draftKey: isNew && widget.template == null ? 'order.new' : null,
      onSubmit: _submit,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FormSection(
              title: 'Product & customer',
              icon: Icons.inventory_2_outlined,
              first: true,
              children: [
                AppSearchableDropdown<String>(
                  label: 'Product',
                  isRequired: true,
                  value: _productId,
                  items: [for (final p in _scopedProducts()) p.id],
                  itemLabel: (id) => widget.allProducts
                      .firstWhere((p) => p.id == id)
                      .name,
                  helper: isNew ? 'Prices are prefilled from the product.' : null,
                  onChanged: (v) {
                    setState(() {
                      final prevBiz = _selectedBusinessId;
                      _productId = v;
                      // The product's business drives customer scoping — if it
                      // changed, a previously picked customer may no longer belong.
                      if (_selectedBusinessId != prevBiz &&
                          _customerId != null &&
                          !_scopedCustomers.any((c) => c.id == _customerId)) {
                        _customerId = null;
                      }
                      if (isNew && v != null) {
                        // Reset prefilled prices, then apply the new product's.
                        _selling.clear();
                        _buying.clear();
                        _applyProductDefaults(v);
                      }
                    });
                  },
                ),
                const FormGap(),
                AppSearchableDropdown<String>(
                  label: 'Customer Reference',
                  // Optional — empty sentinel maps to "no customer".
                  value: _customerId ?? '',
                  items: ['', for (final c in _scopedCustomers) c.id],
                  itemLabel: _customerLabel,
                  onChanged: (v) => setState(
                      () => _customerId = (v == null || v.isEmpty) ? null : v),
                  helper: _customerHelper(),
                ),
              ],
            ),
            FormSection(
              title: 'Pricing',
              icon: Icons.payments_outlined,
              children: [
                FormRow([
                  AppTextField(
                    label: 'Quantity',
                    controller: _quantity,
                    isRequired: true,
                    keyboardType: TextInputType.number,
                    validator: (v) => Validators.positiveInteger(v),
                  ),
                  AppMoneyField(
                    symbol: symbol,
                    label: 'Selling Cost (per unit)',
                    controller: _selling,
                    isRequired: true,
                    validator: (v) =>
                        Validators.nonNegativeNumber(v, field: 'Selling cost'),
                  ),
                ]),
                if (prices.isNotEmpty)
                  ListenableBuilder(
                    listenable: _selling,
                    builder: (context, _) => SuggestionChips<Money>(
                      suggestions: prices,
                      labelOf: (m) => MoneyFormatter.format(m, currency),
                      current: Money.parse(_selling.text),
                      onSelected: (m) => _selling.text = m.major.toString(),
                    ),
                  ),
                const FormGap(),
                FormRow([
                  AppMoneyField(
                    symbol: symbol,
                    label: 'Buying Cost (per unit)',
                    controller: _buying,
                    validator: (v) => Validators.optionalNonNegativeNumber(v),
                    helper: 'Captured at time of order for accurate history.',
                  ),
                  AppMoneyField(
                    symbol: symbol,
                    label: 'Discount',
                    controller: _discount,
                    validator: (v) => Validators.optionalNonNegativeNumber(v),
                  ),
                ]),
                const FormGap(),
                FormRow([
                  AppMoneyField(
                    symbol: symbol,
                    label: 'Shipping Revenue',
                    controller: _shipping,
                    validator: (v) => Validators.optionalNonNegativeNumber(v),
                  ),
                  AppMoneyField(
                    symbol: symbol,
                    label: 'Other Revenue',
                    controller: _other,
                    validator: (v) => Validators.optionalNonNegativeNumber(v),
                  ),
                ]),
                const FormGap(),
                _LiveTotals(
                  listenable: Listenable.merge(
                      [_quantity, _selling, _buying, _discount, _shipping, _other]),
                  preview: _preview,
                  currency: currency,
                ),
              ],
            ),
            FormSection(
              title: 'Status & date',
              icon: Icons.flag_outlined,
              children: [
                FormRow([
                  AppDropdown<OrderStatus>(
                    label: 'Status',
                    value: _status,
                    items: OrderStatus.values,
                    itemLabel: (s) => s.label,
                    onChanged: (v) => setState(() => _status = v ?? _status),
                  ),
                  AppDateField(
                    label: 'Order Date',
                    value: _orderDate,
                    onChanged: (v) => setState(() => _orderDate = v),
                  ),
                ]),
              ],
            ),
            FormSection(
              title: 'Notes',
              icon: Icons.notes_outlined,
              children: [
                AppTextField(label: 'Notes', controller: _notes, maxLines: 3),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// The order as currently typed, for the live totals (status aside: the
  /// preview shows what the order is worth when it counts).
  Order _preview() => Order(
        id: '',
        businessId: '',
        productId: '',
        productName: '',
        quantity: int.tryParse(_quantity.text.trim()) ?? 0,
        sellingCost: Money.parse(_selling.text),
        discount: Money.parse(_discount.text),
        shippingRevenue: Money.parse(_shipping.text),
        otherRevenue: Money.parse(_other.text),
        buyingCost: Money.parse(_buying.text),
        status: OrderStatus.confirmed,
      );

  Future<bool> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return false;
    final productId = _productId;
    if (productId == null) {
      showErrorSnack(context, 'Select a product for this order.');
      return false;
    }
    final product = widget.allProducts.firstWhere((p) => p.id == productId);
    final isNew = _existing == null;
    final order = (_existing ??
            Order(
              id: '',
              businessId: product.businessId,
              productId: productId,
              productName: product.name,
            ))
        .copyWith(
      productId: productId,
      productName: product.name,
      orderDate: _orderDate ?? DateTime.now(),
      quantity: int.tryParse(_quantity.text.trim()) ?? 1,
      sellingCost: Money.parse(_selling.text),
      discount: Money.parse(_discount.text),
      shippingRevenue: Money.parse(_shipping.text),
      otherRevenue: Money.parse(_other.text),
      buyingCost: Money.parse(_buying.text),
      status: _status,
      customerReference: _customerReference,
      notes: _notes.text.trim(),
    );
    try {
      await widget.repo.saveOrder(order, isNew: isNew);
      return true;
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
      return false;
    }
  }
}

/// Revenue, cost and profit of the order being typed, updated as you type.
class _LiveTotals extends StatelessWidget {
  const _LiveTotals({
    required this.listenable,
    required this.preview,
    required this.currency,
  });

  final Listenable listenable;
  final Order Function() preview;
  final CurrencyCode currency;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ListenableBuilder(
      listenable: listenable,
      builder: (context, _) {
        final o = preview();
        String fmt(Money m) => MoneyFormatter.format(m, currency);
        Widget figure(String label, Money value, {Color? tone}) => Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(fontSize: 11.5, color: t.textSecondary)),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(fmt(value),
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: tone ?? t.textPrimary,
                            fontFeatures: const [
                              FontFeature.tabularFigures()
                            ])),
                  ),
                ],
              ),
            );
        return Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: t.primarySurface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            border: Border.all(color: t.primary.withValues(alpha: 0.15)),
          ),
          child: Row(
            children: [
              figure('Total revenue', o.recognisedRevenue),
              figure('Product cost', o.recognisedProductCost),
              figure('Gross profit', o.recognisedGrossProfit,
                  tone: o.recognisedGrossProfit.isNegative
                      ? t.error
                      : t.success),
            ],
          ),
        );
      },
    );
  }
}
