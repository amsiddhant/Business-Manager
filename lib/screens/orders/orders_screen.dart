import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/enums.dart';
import '../../core/permissions.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/money.dart';
import '../../core/validators.dart';
import '../../data/repository.dart';
import '../../models/order.dart';
import '../../models/product.dart';
import '../../state/app_state.dart';
import '../../state/data_controller.dart';
import '../../state/filter_controller.dart';
import '../../widgets/common/confirm_dialog.dart';
import '../../widgets/common/currency_display.dart';
import '../../widgets/common/data_table_card.dart';
import '../../widgets/common/page_header.dart';
import '../../widgets/common/state_views.dart';
import '../../widgets/common/status_badge.dart';
import '../../widgets/forms/form_dialog.dart';
import '../../widgets/forms/form_fields.dart';

/// Lists orders for the selected scope with full CRUD gated by permission.
class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key});

  static final _epoch = DateTime.fromMillisecondsSinceEpoch(0);
  static DateTime _dateOf(Order o) =>
      o.orderDate ?? o.audit.createdAt ?? _epoch;

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
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PageHeader(title: 'Orders'),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: 'Orders',
          subtitle: 'Record sales and track order revenue',
          actions: [
            if (canCreate)
              ElevatedButton.icon(
                onPressed: () => _openForm(context, null, bizId),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Order'),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        AppDataTable<Order>(
          rows: orders,
          searchableText: (o) =>
              '${o.id} ${o.productName} ${o.customerReference}',
          emptyTitle: 'No orders found',
          emptyMessage: canCreate
              ? 'Record your first order to start tracking revenue.'
              : 'Orders will appear here once added.',
          emptyAction: canCreate
              ? ElevatedButton.icon(
                  onPressed: () => _openForm(context, null, bizId),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Order'),
                )
              : null,
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
              label: 'Qty',
              numeric: true,
              cell: (o) => Text('${o.quantity}'),
              sortValue: (o) => o.quantity,
            ),
            AppColumn(
              label: 'Revenue',
              numeric: true,
              cell: (o) => _RevenueCell(
                  order: o, currency: _currencyFor(data, o.businessId)),
              sortValue: (o) => o.recognisedRevenue.minor,
            ),
            AppColumn(
              label: 'Cost',
              numeric: true,
              cell: (o) => CurrencyText(o.recognisedProductCost,
                  currency: _currencyFor(data, o.businessId)),
              sortValue: (o) => o.recognisedProductCost.minor,
            ),
            AppColumn(
              label: 'Profit',
              numeric: true,
              cell: (o) => CurrencyText(o.recognisedGrossProfit,
                  currency: _currencyFor(data, o.businessId)),
              sortValue: (o) => o.recognisedGrossProfit.minor,
            ),
            AppColumn(
              label: 'Status',
              cell: (o) => StatusBadge.order(o.status),
              sortValue: (o) => o.status.label,
            ),
            AppColumn(
              label: '',
              cell: (o) => _RowActions(
                order: o,
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

  static Future<void> _openForm(
      BuildContext context, Order? existing, String? selectedBizId) async {
    final data = context.read<DataController>();
    final repo = context.read<AppState>().repository;
    if (existing == null && data.products.isEmpty) {
      showErrorSnack(context, 'Create a product before adding orders.');
      return;
    }
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _OrderFormDialog(
        existing: existing,
        repo: repo,
        allProducts: data.products,
        preselectBusinessId: selectedBizId,
      ),
    );
    if (saved == true) {
      await data.refresh();
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

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) => const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(title: 'Orders'),
          SizedBox(height: 48),
          LoadingView(),
        ],
      );
}

class _RowActions extends StatelessWidget {
  const _RowActions({
    required this.order,
    required this.canEdit,
    required this.canDelete,
  });

  final Order order;
  final bool canEdit;
  final bool canDelete;

  @override
  Widget build(BuildContext context) {
    if (!canEdit && !canDelete) return const SizedBox.shrink();
    // Statuses that remove the order from recognised revenue/cost.
    final canCancel = canEdit && order.status != OrderStatus.cancelled;
    final canReturn = canEdit && order.status != OrderStatus.returned;
    final canReinstate = canEdit && !order.status.contributesToRevenue;
    final hasMenu = canCancel || canReturn || canReinstate;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (canEdit)
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined, size: 18),
            onPressed: () =>
                OrdersScreen._openForm(context, order, order.businessId),
          ),
        if (hasMenu)
          PopupMenuButton<_OrderAction>(
            tooltip: 'More actions',
            icon: const Icon(Icons.more_vert, size: 18),
            onSelected: (action) => _runAction(context, action),
            itemBuilder: (_) => [
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
      case _OrderAction.cancel:
        await _changeStatus(
          context,
          OrderStatus.cancelled,
          title: 'Cancel order?',
          message: 'Cancel order ${order.id}? Its revenue and product cost '
              'will be excluded from all profit calculations.',
          success: 'Order cancelled — excluded from revenue',
        );
      case _OrderAction.returnRefund:
        await _returnRefund(context);
      case _OrderAction.reinstate:
        // Clear any recorded refund so reinstated revenue/cost count in full.
        await _changeStatus(
          context,
          OrderStatus.confirmed,
          title: 'Reinstate order?',
          message: 'Reinstate order ${order.id} as confirmed? Its revenue and '
              'product cost will count towards profit calculations again.',
          success: 'Order reinstated — counted in revenue',
          clearRefund: true,
        );
    }
  }

  /// Opens the refund dialog and, if confirmed, marks the order returned with
  /// the captured refund amount and date.
  Future<void> _returnRefund(BuildContext context) async {
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
      await data.refresh();
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

  Future<void> _changeStatus(
    BuildContext context,
    OrderStatus status, {
    required String title,
    required String message,
    required String success,
    bool clearRefund = false,
  }) async {
    final data = context.read<DataController>();
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
      if (clearRefund) {
        // copyWith can't null a field, so rebuild without the refund.
        updated = Order(
          id: updated.id,
          businessId: updated.businessId,
          productId: updated.productId,
          productName: updated.productName,
          orderDate: updated.orderDate,
          quantity: updated.quantity,
          sellingCost: updated.sellingCost,
          discount: updated.discount,
          shippingRevenue: updated.shippingRevenue,
          otherRevenue: updated.otherRevenue,
          buyingCost: updated.buyingCost,
          marketingAllocation: updated.marketingAllocation,
          status: updated.status,
          customerReference: updated.customerReference,
          notes: updated.notes,
          audit: updated.audit,
        );
      }
      await repo.saveOrder(updated, isNew: false);
      await data.refresh();
      if (context.mounted) showSuccessSnack(context, success);
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e);
    }
  }

  Future<void> _delete(BuildContext context) async {
    final data = context.read<DataController>();
    final repo = context.read<AppState>().repository;
    final ok = await showConfirmDialog(
      context,
      title: 'Delete order?',
      message: 'Delete order ${order.id}? This action cannot be easily undone.',
    );
    if (ok != true) return;
    try {
      await repo.deleteOrder(order.id);
      await data.refresh();
      if (context.mounted) showSuccessSnack(context, 'Order deleted');
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e);
    }
  }
}

/// Quick status changes available from the orders row overflow menu.
enum _OrderAction { cancel, returnRefund, reinstate }

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
          const Icon(Icons.info_outline,
              size: 13, color: AppColors.textTertiary),
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
                style: const TextStyle(color: AppColors.textSecondary)),
            const FormGap(),
            FormRow([
              AppMoneyField(
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
                color: AppColors.background,
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                border: Border.all(color: AppColors.border),
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
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12.5),
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
    Navigator.of(context).pop(_RefundResult(amount, _date));
    return true;
  }
}

class _OrderFormDialog extends StatefulWidget {
  const _OrderFormDialog({
    required this.existing,
    required this.repo,
    required this.allProducts,
    this.preselectBusinessId,
  });

  final Order? existing;
  final Repository repo;
  final List<Product> allProducts;
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
  late final TextEditingController _customer;
  late final TextEditingController _notes;
  late OrderStatus _status;
  DateTime? _orderDate;
  String? _productId;

  Order? get _existing => widget.existing;

  @override
  void initState() {
    super.initState();
    final o = _existing;
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
    _customer = TextEditingController(text: o?.customerReference ?? '');
    _notes = TextEditingController(text: o?.notes ?? '');
    _status = o?.status ?? OrderStatus.confirmed;
    _orderDate = o?.orderDate ?? _existing?.audit.createdAt;
    _productId = o?.productId ?? _initialProductId();
    // Prefill prices from the selected product for a new order.
    if (o == null && _productId != null) {
      _applyProductDefaults(_productId!);
    }
  }

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
    _customer.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isNew = _existing == null;
    return FormDialog(
      title: isNew ? 'Add Order' : 'Edit Order',
      onSubmit: _submit,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppDropdown<String>(
              label: 'Product',
              isRequired: true,
              value: _productId,
              items: [for (final p in widget.allProducts) p.id],
              itemLabel: (id) => widget.allProducts
                  .firstWhere((p) => p.id == id)
                  .name,
              onChanged: (v) {
                setState(() {
                  _productId = v;
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
            FormRow([
              AppTextField(
                label: 'Quantity',
                controller: _quantity,
                isRequired: true,
                keyboardType: TextInputType.number,
                validator: (v) => Validators.positiveInteger(v),
              ),
              AppDateField(
                label: 'Order Date',
                value: _orderDate,
                onChanged: (v) => setState(() => _orderDate = v),
              ),
            ]),
            const FormGap(),
            FormRow([
              AppMoneyField(
                label: 'Selling Cost (per unit)',
                controller: _selling,
                isRequired: true,
                validator: (v) =>
                    Validators.nonNegativeNumber(v, field: 'Selling cost'),
              ),
              AppMoneyField(
                label: 'Buying Cost (per unit)',
                controller: _buying,
                validator: (v) => Validators.optionalNonNegativeNumber(v),
                helper: 'Captured at time of order for accurate history.',
              ),
            ]),
            const FormGap(),
            FormRow([
              AppMoneyField(
                label: 'Discount',
                controller: _discount,
                validator: (v) => Validators.optionalNonNegativeNumber(v),
              ),
              AppMoneyField(
                label: 'Shipping Revenue',
                controller: _shipping,
                validator: (v) => Validators.optionalNonNegativeNumber(v),
              ),
              AppMoneyField(
                label: 'Other Revenue',
                controller: _other,
                validator: (v) => Validators.optionalNonNegativeNumber(v),
              ),
            ]),
            const FormGap(),
            FormRow([
              AppDropdown<OrderStatus>(
                label: 'Status',
                value: _status,
                items: OrderStatus.values,
                itemLabel: (s) => s.label,
                onChanged: (v) => setState(() => _status = v ?? _status),
              ),
              AppTextField(
                label: 'Customer Reference',
                controller: _customer,
              ),
            ]),
            const FormGap(),
            AppTextField(label: 'Notes', controller: _notes, maxLines: 2),
          ],
        ),
      ),
    );
  }

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
      customerReference: _customer.text.trim(),
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
