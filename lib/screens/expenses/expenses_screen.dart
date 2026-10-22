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
import '../../models/business.dart';
import '../../models/expense.dart';
import '../../services/profit_calculation_service.dart';
import '../../services/smart/suggestion_service.dart';
import '../../services/summaries/expense_summaries.dart';
import '../../state/app_state.dart';
import '../../state/data_controller.dart';
import '../../state/filter_controller.dart';
import '../../state/smart_insights_controller.dart';
import '../../widgets/common/confirm_dialog.dart';
import '../../widgets/common/currency_display.dart';
import '../../widgets/common/page_header.dart';
import '../../widgets/common/state_views.dart';
import '../../widgets/common/status_badge.dart';
import '../../widgets/data/app_data_grid.dart';
import '../../widgets/forms/app_form.dart';
import '../../widgets/forms/form_dialog.dart';
import '../../widgets/forms/form_fields.dart';
import '../../widgets/forms/form_section.dart';
import '../../widgets/forms/suggestion_chips.dart';
import '../../widgets/layout/app_page.dart';
import '../../widgets/layout/kpi_strip.dart';

/// Lists business operating expenses: headline run-rate figures, category and
/// recurrence quick filters, column filters, bulk delete and CSV export.
/// Dealer-linked expenses are read-only — they are managed via the Dealers
/// screen.
class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();

  static CurrencyCode _currencyFor(DataController data, String businessId) =>
      data.businessById(businessId)?.currency ?? CurrencyCode.inr;

  /// Opens the expense form: [existing] to edit, or a new expense — prefilled
  /// from [duplicateOf] when given.
  static Future<void> openForm(
      BuildContext context, Expense? existing, String? selectedBizId,
      {Expense? duplicateOf}) async {
    final data = context.read<DataController>();
    final repo = context.read<AppState>().repository;
    final businesses = data.selectableBusinesses;
    if (existing == null && businesses.isEmpty) {
      showErrorSnack(context, 'Create a business before adding expenses.');
      return;
    }
    final saved = await showAppForm<bool>(
      context: context,
      builder: (_) => _ExpenseFormDialog(
        existing: existing,
        template: duplicateOf,
        repo: repo,
        businesses: businesses,
        preselectBusinessId: selectedBizId,
      ),
    );
    if (saved == true) {
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

class _ExpensesScreenState extends State<ExpensesScreen> {
  static const _service = ProfitCalculationService();
  static final _epoch = DateTime.fromMillisecondsSinceEpoch(0);

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
          const PageHeader(
              title: 'Expenses', icon: Icons.account_balance_wallet_outlined),
          const SizedBox(height: 48),
          ErrorView(message: data.error!, onRetry: () => data.refresh()),
        ],
      );
    }

    final bizId = filter.selectedBusinessId;
    final expenses = [...data.expensesFor(bizId)]..sort((a, b) {
        // Active first, then biggest annual cost.
        if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
        return b.annualisedAmount.minor.compareTo(a.annualisedAmount.minor);
      });
    final canManage = user?.can(Permission.createExpense) ?? false;
    final canEdit = user?.can(Permission.editExpense) ?? false;
    final canDelete = user?.can(Permission.deleteExpense) ?? false;
    final canViewDealer = user?.can(Permission.viewDealer) ?? false;
    final repo = appState.repository;

    CurrencyCode currencyOf(Expense e) =>
        ExpensesScreen._currencyFor(data, e.businessId);
    String businessOf(Expense e) =>
        data.businessById(e.businessId)?.name ?? '';
    String dealerOf(Expense e) => e.sourceDealerId == null
        ? ''
        : data.dealerById(e.sourceDealerId!)?.name ?? e.vendor;
    // Figures are shown in the selected business's currency; INR for all.
    final pageCurrency =
        (bizId == null ? null : data.businessById(bizId))?.currency ??
            CurrencyCode.inr;
    String money(Money m) => MoneyFormatter.compact(m, pageCurrency);

    final summary = _service.summariseExpenses(expenses);
    final categories = {for (final e in expenses) e.category}.toList()
      ..sort((a, b) => a.label.compareTo(b.label));
    final t = context.tokens;

    final addButton = canManage
        ? FilledButton.icon(
            onPressed: () => ExpensesScreen.openForm(context, null, bizId),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Expense'),
          )
        : null;

    final actionButtons =
        [canEdit, canManage, canDelete].where((b) => b).length;

    return AppPage.slivers(
      slivers: [
        SliverToBoxAdapter(
          child: PageHeader(
            title: 'Expenses',
            icon: Icons.account_balance_wallet_outlined,
            count: expenses.length,
            subtitle: 'Track recurring and one-time operating costs',
            actions: [?addButton],
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
        if (expenses.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: KpiStrip(items: [
              KpiItem(
                label: 'Annual run-rate',
                value: money(summary.annualRunRate),
                icon: Icons.event_repeat_outlined,
                caption: '${summary.recurringCount} recurring',
                tooltip: 'What your active recurring expenses cost over a '
                    'year (amount × occurrences per year).',
              ),
              KpiItem(
                label: 'Monthly run-rate',
                value: money(summary.monthlyRunRate),
                icon: Icons.calendar_month_outlined,
                tooltip: 'The annual run-rate ÷ 12.',
              ),
              KpiItem(
                label: 'This month',
                value: money(summary.proratedInRange),
                icon: Icons.timelapse_outlined,
                caption: 'Prorated',
                tooltip: 'Active expenses prorated to the current month: '
                    'recurring costs by days active, one-time costs when '
                    'they fall in the month.',
              ),
              KpiItem(
                label: 'One-time',
                value: money(summary.oneTimeTotal),
                icon: Icons.looks_one_outlined,
                tooltip: 'The full amount of active one-time expenses.',
              ),
              KpiItem(
                label: 'Dealer-managed',
                value: money(summary.dealerAnnual),
                icon: Icons.handshake_outlined,
                tone: summary.dealerCount > 0 ? t.info : null,
                caption: '${summary.dealerCount} from dealers · per year',
                tooltip: 'Yearly cost of expenses mirrored from dealers. '
                    'Edit them on the dealer.',
              ),
            ]),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
        ],
        SliverAppDataGrid<Expense>(
          gridId: 'expenses',
          rows: expenses,
          rowKey: (e) => e.id,
          exportName: 'expenses',
          searchHint: 'Search by name, ID, category, vendor or status…',
          searchText: (e) => '${e.id} ${e.name} ${e.category.label} '
              '${e.vendor} ${e.frequency.label} ${e.status.label} '
              '${dealerOf(e)}',
          onRowTap: (e) => context.go(Routes.expenseDetailPath(e.id)),
          quickFilters: [
            GridQuickFilter<Expense>(
              id: 'recurring',
              label: 'Recurring',
              icon: Icons.repeat,
              test: (e) => e.frequency.isRecurring,
            ),
            GridQuickFilter<Expense>(
              id: 'one-time',
              label: 'One-time',
              test: (e) => !e.frequency.isRecurring,
            ),
            GridQuickFilter<Expense>(
              id: 'dealer-managed',
              label: 'Dealer-managed',
              icon: Icons.link,
              test: (e) => e.isFromDealer,
            ),
            for (final c in categories)
              GridQuickFilter<Expense>(
                id: 'cat-${c.wire}',
                label: c.label,
                test: (e) => e.category == c,
              ),
          ],
          bulkActions: [
            if (canDelete)
              GridBulkAction<Expense>(
                label: 'Delete',
                icon: Icons.delete_outline,
                destructive: true,
                // Dealer-mirrored rows are removed by deleting the dealer.
                allowed: (e) => !e.isFromDealer,
                onRun: (context, rows) => _bulkDelete(context, repo, rows),
              ),
          ],
          emptyTitle: 'No expenses yet',
          emptyIcon: Icons.account_balance_wallet_outlined,
          emptyMessage: canManage
              ? 'Add your operating costs to see accurate net profit.'
              : 'Expenses will appear here once added.',
          emptyAction: addButton,
          columns: [
            GridColumn(
              id: 'id',
              label: 'ID',
              visibleByDefault: false,
              cardRole: CardRole.subtitle,
              minWidth: 110,
              cell: (e) => Text(e.id,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              sortValue: (e) => e.id,
              exportValue: (e) => e.id,
            ),
            GridColumn(
              id: 'name',
              label: 'Expense',
              flex: 3,
              pinned: true,
              cardRole: CardRole.title,
              minWidth: 180,
              cell: (e) => _NameCell(
                expense: e,
                dealerName: dealerOf(e),
                canOpenDealer: canViewDealer,
              ),
              sortValue: (e) => e.name.toLowerCase(),
              exportValue: (e) => e.name,
            ),
            GridColumn(
              id: 'category',
              label: 'Category',
              flex: 1,
              cardRole: CardRole.meta,
              cell: (e) => Text(e.category.label,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              sortValue: (e) => e.category.label,
              exportValue: (e) => e.category.label,
              filter: GridFilter.choice((e) => e.category.label, options: [
                for (final c in ExpenseCategory.values) c.label
              ]),
            ),
            GridColumn(
              id: 'vendor',
              label: 'Vendor',
              visibleByDefault: false,
              cardRole: CardRole.meta,
              cell: (e) => Text(e.vendor.isEmpty ? '—' : e.vendor,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              sortValue: (e) => e.vendor.toLowerCase(),
              exportValue: (e) => e.vendor,
              filter: GridFilter.choice(
                  (e) => e.vendor.isEmpty ? 'No vendor' : e.vendor),
            ),
            GridColumn(
              id: 'business',
              label: 'Business',
              visibleByDefault: false,
              cardRole: CardRole.meta,
              cell: (e) => Text(businessOf(e),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              sortValue: (e) => businessOf(e).toLowerCase(),
              exportValue: businessOf,
              filter: GridFilter.choice(businessOf),
            ),
            GridColumn(
              id: 'frequency',
              label: 'Frequency',
              cardRole: CardRole.meta,
              minWidth: 110,
              cell: (e) => Text(e.frequency.label),
              sortValue: (e) => e.frequency.label,
              exportValue: (e) => e.frequency.label,
              filter: GridFilter.choice((e) => e.frequency.label, options: [
                for (final f in RecurrenceFrequency.values) f.label
              ]),
            ),
            GridColumn(
              id: 'start',
              label: 'Start',
              visibleByDefault: false,
              cardRole: CardRole.meta,
              minWidth: 110,
              cell: (e) => Text(
                  e.startDate == null ? '—' : AppDate.format(e.startDate)),
              sortValue: (e) =>
                  (e.startDate ?? _epoch).millisecondsSinceEpoch,
              exportValue: (e) =>
                  e.startDate == null ? '' : AppDate.format(e.startDate),
              filter: GridFilter.dateRange((e) => e.startDate ?? _epoch),
            ),
            GridColumn(
              id: 'amount',
              label: 'Amount',
              numeric: true,
              cardRole: CardRole.metric,
              tooltip: 'Per occurrence',
              cell: (e) => CurrencyText(e.amount, currency: currencyOf(e)),
              sortValue: (e) => e.amount.minor,
              exportValue: (e) => e.amount.major.toStringAsFixed(2),
              filter: GridFilter.numberRange((e) => e.amount.major),
            ),
            GridColumn(
              id: 'annualised',
              label: 'Annualised',
              numeric: true,
              cardRole: CardRole.metric,
              tooltip: 'Amount × occurrences per year (one-time counts once)',
              cell: (e) =>
                  CurrencyText(e.annualisedAmount, currency: currencyOf(e)),
              sortValue: (e) => e.annualisedAmount.minor,
              exportValue: (e) => e.annualisedAmount.major.toStringAsFixed(2),
              filter: GridFilter.numberRange((e) => e.annualisedAmount.major),
              footer: (rows) => money(rows
                  .where((e) => e.isActive)
                  .fold(Money.zero, (m, e) => m + e.annualisedAmount)),
            ),
            GridColumn(
              id: 'status',
              label: 'Status',
              cardRole: CardRole.badge,
              minWidth: 110,
              cell: (e) => StatusBadge.entity(e.status),
              sortValue: (e) => e.status.label,
              exportValue: (e) => e.status.label,
              filter: GridFilter.choice((e) => e.status.label, options: [
                EntityStatus.active.label,
                EntityStatus.inactive.label,
                EntityStatus.archived.label,
              ]),
            ),
            GridColumn(
              id: 'actions',
              label: '',
              pinned: true,
              cardRole: CardRole.actions,
              // Edit, Duplicate and Delete (48 px each) plus the cell
              // padding; dealer rows show a single "open dealer" button.
              minWidth: 2 * AppSpacing.md +
                  48 * (actionButtons == 0 ? 1 : actionButtons),
              cell: (e) => _RowActions(
                expense: e,
                canCreate: canManage,
                canEdit: canEdit,
                canDelete: canDelete,
                canOpenDealer: canViewDealer,
              ),
            ),
          ],
        ),
      ],
    );
  }

  static Future<void> _bulkDelete(
      BuildContext context, Repository repo, List<Expense> rows) async {
    final ok = await showConfirmDialog(
      context,
      title:
          'Delete ${rows.length == 1 ? '1 expense' : '${rows.length} expenses'}?',
      message: 'This removes them for everyone and cannot be easily undone.',
    );
    if (!ok || !context.mounted) return;
    await runGridBulk<Expense>(
      context,
      rows: rows,
      verb: 'Deleting',
      noun: 'expenses',
      describe: (e) => e.name,
      task: (e) => repo.deleteExpense(e.id, known: e),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) => const AppPage(
        children: [
          PageHeader(
              title: 'Expenses', icon: Icons.account_balance_wallet_outlined),
          SizedBox(height: AppSpacing.lg),
          SkeletonCard(lines: 1, height: 88),
          SizedBox(height: AppSpacing.lg),
          SkeletonCard(lines: 8),
        ],
      );
}

/// The expense name, with a "Managed by dealer" link for mirrored rows.
class _NameCell extends StatelessWidget {
  const _NameCell({
    required this.expense,
    required this.dealerName,
    required this.canOpenDealer,
  });

  final Expense expense;
  final String dealerName;
  final bool canOpenDealer;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final name = Text(expense.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600));
    if (!expense.isFromDealer) return name;
    final label = Text(
      dealerName.isEmpty ? 'Managed by dealer' : 'Managed by $dealerName',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
          fontSize: 12, color: canOpenDealer ? t.primary : t.textSecondary),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        name,
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.link, size: 12, color: t.textTertiary),
            const SizedBox(width: 4),
            Flexible(
              child: canOpenDealer
                  ? InkWell(
                      onTap: () => context.go(
                          Routes.dealerDetailPath(expense.sourceDealerId!)),
                      child: label,
                    )
                  : label,
            ),
          ],
        ),
      ],
    );
  }
}

class _RowActions extends StatelessWidget {
  const _RowActions({
    required this.expense,
    required this.canCreate,
    required this.canEdit,
    required this.canDelete,
    required this.canOpenDealer,
  });

  final Expense expense;
  final bool canCreate;
  final bool canEdit;
  final bool canDelete;
  final bool canOpenDealer;

  @override
  Widget build(BuildContext context) {
    // Dealer-mirrored expenses are managed via the dealer, not here.
    if (expense.isFromDealer) {
      if (!canOpenDealer) {
        return Padding(
          padding: const EdgeInsets.only(right: AppSpacing.sm),
          child: Text('Dealer',
              style:
                  TextStyle(fontSize: 12, color: context.tokens.textTertiary)),
        );
      }
      return IconButton(
        tooltip: 'Open dealer',
        icon: const Icon(Icons.open_in_new, size: 18),
        onPressed: () =>
            context.go(Routes.dealerDetailPath(expense.sourceDealerId!)),
      );
    }
    if (!canEdit && !canDelete && !canCreate) return const SizedBox.shrink();
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
        if (canCreate)
          IconButton(
            tooltip: 'Duplicate',
            icon: const Icon(Icons.copy_all_outlined, size: 18),
            onPressed: () => ExpenseActions.duplicate(context, expense),
          ),
        if (canDelete)
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: () => ExpenseActions.delete(context, expense),
          ),
      ],
    );
  }
}

/// The single-expense actions, shared by the list rows and the detail page.
class ExpenseActions {
  ExpenseActions._();

  static Future<void> duplicate(BuildContext context, Expense expense) =>
      ExpensesScreen.openForm(context, null, expense.businessId,
          duplicateOf: expense);

  /// Returns true when the expense was deleted.
  static Future<bool> delete(BuildContext context, Expense expense) async {
    final repo = context.read<AppState>().repository;
    final ok = await showConfirmDialog(
      context,
      title: 'Delete expense?',
      message: 'Delete "${expense.name}"? This action cannot be easily undone.',
    );
    if (ok != true) return false;
    try {
      await repo.deleteExpense(expense.id, known: expense);
      if (context.mounted) showSuccessSnack(context, 'Expense deleted');
      return true;
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e);
      return false;
    }
  }

  /// Switches an expense between active and inactive.
  static Future<void> setStatus(
      BuildContext context, Expense expense, EntityStatus status) async {
    final repo = context.read<AppState>().repository;
    try {
      await repo.saveExpense(expense.copyWith(status: status), isNew: false);
      if (context.mounted) {
        showSuccessSnack(
            context, 'Expense marked ${status.label.toLowerCase()}');
      }
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e);
    }
  }
}

class _ExpenseFormDialog extends StatefulWidget {
  const _ExpenseFormDialog({
    required this.existing,
    this.template,
    required this.repo,
    required this.businesses,
    this.preselectBusinessId,
  });

  final Expense? existing;

  /// A new expense copies this one's fields.
  final Expense? template;
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

  /// The on-device classifiers where they beat the rules (chips refresh when
  /// their predictions arrive), the built-in rules otherwise.
  SuggestionProvider get _suggest =>
      smartOf(context)?.suggestions ?? const DartSuggestionProvider();

  /// The chosen business's currency.
  CurrencyCode get _currency =>
      widget.businesses
          .where((b) => b.id == _businessId)
          .firstOrNull
          ?.currency ??
      CurrencyCode.inr;

  /// The chosen business's currency symbol, for the money fields.
  String get _symbol => _currency.symbol;

  @override
  void initState() {
    super.initState();
    smartOf(context, listen: false)?.suggestionsWanted();
    final e = _existing ?? widget.template;
    _name = TextEditingController(
        text: e == null
            ? ''
            : (_existing == null ? '${e.name} (copy)' : e.name));
    _amount = TextEditingController(
        text: e == null || e.amount.isZero ? '' : e.amount.major.toString());
    _vendor = TextEditingController(text: e?.vendor ?? '');
    _description = TextEditingController(text: e?.description ?? '');
    _notes = TextEditingController(text: e?.notes ?? '');
    _category = e?.category ?? ExpenseCategory.software;
    _frequency = e?.frequency ?? RecurrenceFrequency.monthly;
    _status = _existing?.status ?? EntityStatus.active;
    _startDate = e?.startDate;
    _endDate = e?.endDate;
    _businessId = _existing?.businessId ??
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
    final t = context.tokens;
    // The Dealer category is reserved for auto-mirrored dealer expenses.
    final categories = ExpenseCategory.values
        .where((c) => c != ExpenseCategory.dealer)
        .toList();
    final annual = Expense(
      id: '',
      businessId: '',
      name: '',
      amount: Money.parse(_amount.text),
      frequency: _frequency,
    ).annualisedAmount;
    final history = context
        .select<DataController, List<Expense>>((d) => d.expensesFor(null));
    return FormDialog(
      title: isNew
          ? (widget.template == null ? 'Add Expense' : 'Duplicate Expense')
          : 'Edit Expense',
      subtitle: widget.template == null
          ? null
          : 'A new expense, copied from ${widget.template!.id}',
      icon: Icons.account_balance_wallet_outlined,
      draftKey: isNew && widget.template == null ? 'expense.new' : null,
      onSubmit: _submit,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FormSection(
              title: 'Details & description',
              icon: Icons.notes_outlined,
              first: true,
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
                  validator: (v) =>
                      Validators.required(v, field: 'Expense name'),
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
                    onChanged: (v) =>
                        setState(() => _category = v ?? _category),
                  ),
                  AppTextField(label: 'Vendor', controller: _vendor),
                ]),
                if (isNew)
                  ListenableBuilder(
                    listenable: Listenable.merge([_name, _vendor]),
                    builder: (context, _) => SuggestionChips<ExpenseCategory>(
                      suggestions: [
                        for (final s in _suggest.expenseCategory(
                          name: _name.text,
                          vendor: _vendor.text,
                          history: history,
                          businessId: _businessId,
                        ))
                          if (categories.contains(s.value)) s,
                      ],
                      labelOf: (c) => c.label,
                      current: _category,
                      onSelected: (c) => setState(() => _category = c),
                    ),
                  ),
                const FormGap(),
                AppTextField(
                  label: 'Description',
                  controller: _description,
                  maxLines: 2,
                  helper: 'What this cost covers.',
                ),
                const FormGap(),
                AppTextField(label: 'Notes', controller: _notes, maxLines: 2),
              ],
            ),
            FormSection(
              title: 'Amount & recurrence',
              icon: Icons.event_repeat_outlined,
              children: [
                FormRow([
                  AppMoneyField(
                    symbol: _symbol,
                    label: 'Amount (per occurrence)',
                    controller: _amount,
                    isRequired: true,
                    onChanged: (_) => setState(() {}),
                    validator: (v) =>
                        Validators.nonNegativeNumber(v, field: 'Amount'),
                  ),
                  AppDropdown<RecurrenceFrequency>(
                    label: 'Frequency',
                    isRequired: true,
                    value: _frequency,
                    items: RecurrenceFrequency.values,
                    itemLabel: (f) => f.label,
                    onChanged: (v) =>
                        setState(() => _frequency = v ?? _frequency),
                  ),
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
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: t.surfaceAlt,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.functions, size: 16, color: t.textSecondary),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          _frequency.isRecurring
                              ? 'Annualised: ${MoneyFormatter.format(annual, _currency)} per year'
                              : 'One-time: counted once, on its start date',
                          style:
                              TextStyle(fontSize: 13, color: t.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
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
