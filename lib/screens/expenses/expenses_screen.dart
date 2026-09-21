import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/enums.dart';
import '../../core/permissions.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../core/validators.dart';
import '../../data/repository.dart';
import '../../models/business.dart';
import '../../models/expense.dart';
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

/// Lists business operating expenses. Dealer-linked expenses are read-only —
/// they are managed via the Dealers screen.
class ExpensesScreen extends StatelessWidget {
  const ExpensesScreen({super.key});

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
          const PageHeader(title: 'Expenses'),
          const SizedBox(height: 48),
          ErrorView(message: data.error!, onRetry: () => data.refresh()),
        ],
      );
    }

    final bizId = filter.selectedBusinessId;
    final expenses = data.expensesFor(bizId);
    final canManage = user?.can(Permission.createExpense) ?? false;
    final canEdit = user?.can(Permission.editExpense) ?? false;
    final canDelete = user?.can(Permission.deleteExpense) ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: 'Expenses',
          subtitle: 'Track recurring and one-time operating costs',
          actions: [
            if (canManage)
              ElevatedButton.icon(
                onPressed: () => openForm(context, null, bizId),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Expense'),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        AppDataTable<Expense>(
          rows: expenses,
          onRowTap: (e) => context.go(Routes.expenseDetailPath(e.id)),
          searchableText: (e) =>
              '${e.id} ${e.name} ${e.category.label} ${e.vendor}',
          emptyTitle: 'No expenses found',
          emptyMessage: canManage
              ? 'Add your operating costs to see accurate net profit.'
              : 'Expenses will appear here once added.',
          emptyAction: canManage
              ? ElevatedButton.icon(
                  onPressed: () => openForm(context, null, bizId),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Expense'),
                )
              : null,
          columns: [
            AppColumn(
              label: 'Expense',
              cell: (e) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(e.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  if (e.isFromDealer) ...[
                    const SizedBox(width: 6),
                    const Tooltip(
                      message: 'Managed via the linked dealer',
                      child: Icon(Icons.link, size: 14, color: Color(0xFF9CA3AF)),
                    ),
                  ],
                ],
              ),
              sortValue: (e) => e.name.toLowerCase(),
            ),
            AppColumn(
              label: 'Category',
              cell: (e) => Text(e.category.label),
              sortValue: (e) => e.category.label,
            ),
            AppColumn(
              label: 'Amount',
              numeric: true,
              cell: (e) => CurrencyText(e.amount,
                  currency: _currencyFor(data, e.businessId)),
              sortValue: (e) => e.amount.minor,
            ),
            AppColumn(
              label: 'Frequency',
              cell: (e) => Text(e.frequency.label),
              sortValue: (e) => e.frequency.label,
            ),
            AppColumn(
              label: 'Annualised',
              numeric: true,
              cell: (e) => CurrencyText(e.annualisedAmount,
                  currency: _currencyFor(data, e.businessId)),
              sortValue: (e) => e.annualisedAmount.minor,
            ),
            AppColumn(
              label: 'Status',
              cell: (e) => StatusBadge.entity(e.status),
              sortValue: (e) => e.status.label,
            ),
            AppColumn(
              label: '',
              cell: (e) => _RowActions(
                expense: e,
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

  static Future<void> openForm(
      BuildContext context, Expense? existing, String? selectedBizId) async {
    final data = context.read<DataController>();
    final repo = context.read<AppState>().repository;
    final businesses = data.selectableBusinesses;
    if (existing == null && businesses.isEmpty) {
      showErrorSnack(context, 'Create a business before adding expenses.');
      return;
    }
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _ExpenseFormDialog(
        existing: existing,
        repo: repo,
        businesses: businesses,
        preselectBusinessId: selectedBizId,
      ),
    );
    if (saved == true) {
      await data.refresh();
      if (context.mounted) {
        showSuccessSnack(
            context,
            existing == null
                ? 'Expense created successfully'
                : 'Expense updated successfully');
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
          PageHeader(title: 'Expenses'),
          SizedBox(height: 48),
          LoadingView(),
        ],
      );
}

class _RowActions extends StatelessWidget {
  const _RowActions({
    required this.expense,
    required this.canEdit,
    required this.canDelete,
  });

  final Expense expense;
  final bool canEdit;
  final bool canDelete;

  @override
  Widget build(BuildContext context) {
    // Dealer-mirrored expenses are managed via the dealer, not here.
    if (expense.isFromDealer) {
      return const Padding(
        padding: EdgeInsets.only(right: AppSpacing.sm),
        child: Text('Dealer',
            style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
      );
    }
    if (!canEdit && !canDelete) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (canEdit)
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined, size: 18),
            onPressed: () =>
                ExpensesScreen.openForm(context, expense, expense.businessId),
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

  Future<void> _delete(BuildContext context) async {
    final data = context.read<DataController>();
    final repo = context.read<AppState>().repository;
    final ok = await showConfirmDialog(
      context,
      title: 'Delete expense?',
      message: 'Delete "${expense.name}"? This action cannot be easily undone.',
    );
    if (ok != true) return;
    try {
      await repo.deleteExpense(expense.id);
      await data.refresh();
      if (context.mounted) showSuccessSnack(context, 'Expense deleted');
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e);
    }
  }
}

class _ExpenseFormDialog extends StatefulWidget {
  const _ExpenseFormDialog({
    required this.existing,
    required this.repo,
    required this.businesses,
    this.preselectBusinessId,
  });

  final Expense? existing;
  final Repository repo;
  final List<Business> businesses;
  final String? preselectBusinessId;

  @override
  State<_ExpenseFormDialog> createState() => _ExpenseFormDialogState();
}

class _ExpenseFormDialogState extends State<_ExpenseFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _amount;
  late final TextEditingController _vendor;
  late final TextEditingController _description;
  late final TextEditingController _notes;
  late ExpenseCategory _category;
  late RecurrenceFrequency _frequency;
  late EntityStatus _status;
  DateTime? _startDate;
  DateTime? _endDate;
  String? _businessId;

  Expense? get _existing => widget.existing;

  @override
  void initState() {
    super.initState();
    final e = _existing;
    _name = TextEditingController(text: e?.name ?? '');
    _amount = TextEditingController(
        text: e == null || e.amount.isZero ? '' : e.amount.major.toString());
    _vendor = TextEditingController(text: e?.vendor ?? '');
    _description = TextEditingController(text: e?.description ?? '');
    _notes = TextEditingController(text: e?.notes ?? '');
    _category = e?.category ?? ExpenseCategory.software;
    _frequency = e?.frequency ?? RecurrenceFrequency.monthly;
    _status = e?.status ?? EntityStatus.active;
    _startDate = e?.startDate;
    _endDate = e?.endDate;
    _businessId = e?.businessId ??
        widget.preselectBusinessId ??
        (widget.businesses.isNotEmpty ? widget.businesses.first.id : null);
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _vendor.dispose();
    _description.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isNew = _existing == null;
    // The Dealer category is reserved for auto-mirrored dealer expenses.
    final categories = ExpenseCategory.values
        .where((c) => c != ExpenseCategory.dealer)
        .toList();
    return FormDialog(
      title: isNew ? 'Add Expense' : 'Edit Expense',
      onSubmit: _submit,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isNew && widget.businesses.length > 1) ...[
              AppSearchableDropdown<String>(
                label: 'Business',
                isRequired: true,
                value: _businessId,
                items: [for (final b in widget.businesses) b.id],
                itemLabel: (id) =>
                    widget.businesses.firstWhere((b) => b.id == id).name,
                hintText: 'Search businesses…',
                onChanged: (v) => setState(() => _businessId = v),
              ),
              const FormGap(),
            ],
            AppTextField(
              label: 'Expense Name',
              controller: _name,
              isRequired: true,
              validator: (v) => Validators.required(v, field: 'Expense name'),
            ),
            const FormGap(),
            FormRow([
              AppDropdown<ExpenseCategory>(
                label: 'Category',
                isRequired: true,
                value: categories.contains(_category)
                    ? _category
                    : categories.first,
                items: categories,
                itemLabel: (c) => c.label,
                onChanged: (v) => setState(() => _category = v ?? _category),
              ),
              AppDropdown<RecurrenceFrequency>(
                label: 'Frequency',
                isRequired: true,
                value: _frequency,
                items: RecurrenceFrequency.values,
                itemLabel: (f) => f.label,
                onChanged: (v) => setState(() => _frequency = v ?? _frequency),
              ),
            ]),
            const FormGap(),
            FormRow([
              AppMoneyField(
                label: 'Amount (per occurrence)',
                controller: _amount,
                isRequired: true,
                validator: (v) =>
                    Validators.nonNegativeNumber(v, field: 'Amount'),
              ),
              AppTextField(label: 'Vendor', controller: _vendor),
            ]),
            const FormGap(),
            FormRow([
              AppDateField(
                label: 'Start Date',
                value: _startDate,
                onChanged: (v) => setState(() => _startDate = v),
              ),
              AppDateField(
                label: 'End Date',
                value: _endDate,
                helper: 'Leave empty for ongoing.',
                onChanged: (v) => setState(() => _endDate = v),
              ),
            ]),
            const FormGap(),
            AppDropdown<EntityStatus>(
              label: 'Status',
              value: _status,
              items: const [EntityStatus.active, EntityStatus.inactive],
              itemLabel: (s) => s.label,
              onChanged: (v) => setState(() => _status = v ?? _status),
            ),
            const FormGap(),
            AppTextField(label: 'Notes', controller: _notes, maxLines: 2),
          ],
        ),
      ),
    );
  }

  Future<bool> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return false;
    final bizId = _businessId;
    if (bizId == null) {
      showErrorSnack(context, 'Select a business for this expense.');
      return false;
    }
    final isNew = _existing == null;
    final expense = (_existing ??
            Expense(id: '', businessId: bizId, name: _name.text.trim()))
        .copyWith(
      name: _name.text.trim(),
      category: _category,
      description: _description.text.trim(),
      amount: Money.parse(_amount.text),
      frequency: _frequency,
      startDate: _startDate,
      endDate: _endDate,
      vendor: _vendor.text.trim(),
      status: _status,
      notes: _notes.text.trim(),
    );
    try {
      await widget.repo.saveExpense(expense, isNew: isNew);
      return true;
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
      return false;
    }
  }
}
