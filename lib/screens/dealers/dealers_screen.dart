import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:universal_html/html.dart' as html;

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
import '../../models/dealer.dart';
import '../../services/profit_calculation_service.dart';
import '../../services/summaries/dealer_summaries.dart';
import '../../state/app_state.dart';
import '../../state/data_controller.dart';
import '../../state/filter_controller.dart';
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
import '../../widgets/layout/app_page.dart';
import '../../widgets/layout/kpi_strip.dart';

/// Lists dealers/vendors for the selected scope: yearly cost figures, status
/// quick filters, column filters, bulk status changes and deletes, and CSV
/// export. Each dealer's recurring cost is automatically mirrored into
/// Business Expenses by the repository.
class DealersScreen extends StatefulWidget {
  const DealersScreen({super.key});

  /// Opens the create/edit dealer dialog. Static on the public widget class so
  /// the dealer detail screen can invoke it as `DealersScreen.openForm(...)`.
  static Future<void> openForm(
      BuildContext context, Dealer? existing, String? selectedBizId) async {
    final data = context.read<DataController>();
    final repo = context.read<AppState>().repository;
    final businesses = data.selectableBusinesses;
    if (existing == null && businesses.isEmpty) {
      showErrorSnack(context, 'Create a business before adding dealers.');
      return;
    }
    final saved = await showAppForm<bool>(
      context: context,
      builder: (_) => _DealerFormDialog(
        existing: existing,
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
                ? 'Dealer created successfully'
                : 'Dealer updated successfully');
      }
    }
  }

  @override
  State<DealersScreen> createState() => _DealersScreenState();
}

class _DealersScreenState extends State<DealersScreen> {
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
          const PageHeader(title: 'Dealers', icon: Icons.handshake_outlined),
          const SizedBox(height: 48),
          ErrorView(message: data.error!, onRetry: () => data.refresh()),
        ],
      );
    }

    final bizId = filter.selectedBusinessId;
    final dealers = [...data.dealersFor(bizId)]..sort((a, b) {
        if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    final canCreate = user?.can(Permission.createDealer) ?? false;
    final canEdit = user?.can(Permission.editDealer) ?? false;
    final canDelete = user?.can(Permission.deleteDealer) ?? false;
    final repo = appState.repository;

    CurrencyCode currencyOf(Dealer d) =>
        _currencyFor(data, d.businessId);
    String businessOf(Dealer d) => data.businessById(d.businessId)?.name ?? '';
    Money annualOf(Dealer d) => d.costFrequency.isRecurring
        ? d.cost * d.costFrequency.occurrencesPerYear
        : d.cost;
    // Figures are shown in the selected business's currency; INR for all.
    final pageCurrency =
        (bizId == null ? null : data.businessById(bizId))?.currency ??
            CurrencyCode.inr;
    String money(Money m) => MoneyFormatter.compact(m, pageCurrency);

    final summary = _service.summariseDealers(dealers);
    final t = context.tokens;

    final addButton = canCreate
        ? FilledButton.icon(
            onPressed: () => DealersScreen.openForm(context, null, bizId),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Dealer'),
          )
        : null;

    // Website, Edit and Delete (48 px each) plus the cell padding.
    final actionButtons = 1 + [canEdit, canDelete].where((b) => b).length;

    return AppPage.slivers(
      slivers: [
        SliverToBoxAdapter(
          child: PageHeader(
            title: 'Dealers',
            icon: Icons.handshake_outlined,
            count: dealers.length,
            subtitle: 'Manage vendors — their cost flows into expenses',
            actions: [?addButton],
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
        if (dealers.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: KpiStrip(items: [
              KpiItem(
                label: 'Dealers',
                value: '${summary.count}',
                icon: Icons.handshake_outlined,
                caption: '${summary.activeCount} active',
              ),
              KpiItem(
                label: 'Annual cost',
                value: money(summary.annualCost),
                icon: Icons.event_repeat_outlined,
                tooltip: 'What your active dealers cost over a year '
                    '(cost × occurrences per year).',
              ),
              KpiItem(
                label: 'Monthly cost',
                value: money(summary.monthlyCost),
                icon: Icons.calendar_month_outlined,
                tooltip: 'The annual cost ÷ 12.',
              ),
              KpiItem(
                label: 'Inactive',
                value: '${summary.inactiveCount}',
                icon: Icons.pause_circle_outline,
                tone: summary.inactiveCount > 0 ? t.warning : null,
                caption: 'Excluded from costs',
              ),
              KpiItem(
                label: 'With website',
                value: '${summary.withWebsite}',
                icon: Icons.language,
                caption: 'of ${summary.count}',
              ),
            ]),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
        ],
        SliverAppDataGrid<Dealer>(
          gridId: 'dealers',
          rows: dealers,
          rowKey: (d) => d.id,
          exportName: 'dealers',
          searchHint: 'Search by ID, name, contact, frequency or status…',
          searchText: (d) =>
              '${d.id} ${d.name} ${d.contactName} ${d.contactInfo} '
              '${d.costFrequency.label} ${d.status.label}',
          onRowTap: (d) => context.go(Routes.dealerDetailPath(d.id)),
          quickFilters: [
            for (final s in [EntityStatus.active, EntityStatus.inactive])
              GridQuickFilter<Dealer>(
                id: s.wire,
                label: s.label,
                test: (d) => d.status == s,
              ),
            GridQuickFilter<Dealer>(
              id: 'website',
              label: 'Has website',
              icon: Icons.language,
              test: (d) => d.url.trim().isNotEmpty,
            ),
          ],
          bulkActions: [
            if (canEdit)
              GridBulkAction<Dealer>(
                label: 'Change status',
                icon: Icons.swap_horiz,
                children: [
                  for (final s in [EntityStatus.active, EntityStatus.inactive])
                    GridBulkAction<Dealer>(
                      label: s.label,
                      icon: s == EntityStatus.active
                          ? Icons.check_circle_outline
                          : Icons.pause_circle_outline,
                      allowed: (d) => d.status != s,
                      onRun: (context, rows) =>
                          _bulkStatus(context, repo, rows, s),
                    ),
                ],
              ),
            if (canDelete)
              GridBulkAction<Dealer>(
                label: 'Delete',
                icon: Icons.delete_outline,
                destructive: true,
                onRun: (context, rows) => _bulkDelete(context, repo, rows),
              ),
          ],
          emptyTitle: 'No dealers yet',
          emptyIcon: Icons.handshake_outlined,
          emptyMessage: canCreate
              ? 'Add a dealer to track vendor costs automatically.'
              : 'Dealers will appear here once added.',
          emptyAction: addButton,
          columns: [
            GridColumn(
              id: 'id',
              label: 'ID',
              visibleByDefault: false,
              cardRole: CardRole.subtitle,
              minWidth: 110,
              cell: (d) => Text(d.id),
              sortValue: (d) => d.id,
              exportValue: (d) => d.id,
            ),
            GridColumn(
              id: 'name',
              label: 'Dealer',
              flex: 3,
              pinned: true,
              minWidth: 180,
              cardRole: CardRole.title,
              cell: (d) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(d.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (d.contactName.isNotEmpty)
                    Text(d.contactName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12, color: context.tokens.textSecondary)),
                ],
              ),
              sortValue: (d) => d.name.toLowerCase(),
              exportValue: (d) => d.name,
            ),
            GridColumn(
              id: 'contact',
              label: 'Contact',
              flex: 2,
              cardRole: CardRole.meta,
              cell: (d) => Text(d.contactInfo.isEmpty ? '—' : d.contactInfo,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              sortValue: (d) => d.contactInfo.toLowerCase(),
              exportValue: (d) => d.contactInfo,
            ),
            GridColumn(
              id: 'business',
              label: 'Business',
              visibleByDefault: false,
              cardRole: CardRole.meta,
              cell: (d) => Text(businessOf(d),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              sortValue: (d) => businessOf(d).toLowerCase(),
              exportValue: businessOf,
              filter: GridFilter.choice(businessOf),
            ),
            GridColumn(
              id: 'frequency',
              label: 'Frequency',
              cardRole: CardRole.meta,
              minWidth: 110,
              cell: (d) => Text(d.costFrequency.label),
              sortValue: (d) => d.costFrequency.label,
              exportValue: (d) => d.costFrequency.label,
              filter: GridFilter.choice((d) => d.costFrequency.label,
                  options: [
                    for (final f in RecurrenceFrequency.values) f.label
                  ]),
            ),
            GridColumn(
              id: 'start',
              label: 'Start',
              visibleByDefault: false,
              cardRole: CardRole.meta,
              minWidth: 110,
              cell: (d) => Text(
                  d.startDate == null ? '—' : AppDate.format(d.startDate)),
              sortValue: (d) =>
                  (d.startDate ?? _epoch).millisecondsSinceEpoch,
              exportValue: (d) =>
                  d.startDate == null ? '' : AppDate.format(d.startDate),
              filter: GridFilter.dateRange((d) => d.startDate ?? _epoch),
            ),
            GridColumn(
              id: 'cost',
              label: 'Cost',
              numeric: true,
              cardRole: CardRole.metric,
              tooltip: 'Per occurrence',
              cell: (d) => CurrencyText(d.cost, currency: currencyOf(d)),
              sortValue: (d) => d.cost.minor,
              exportValue: (d) => d.cost.major.toStringAsFixed(2),
              filter: GridFilter.numberRange((d) => d.cost.major),
            ),
            GridColumn(
              id: 'annual',
              label: 'Annual cost',
              numeric: true,
              cardRole: CardRole.metric,
              tooltip: 'Cost × occurrences per year (one-time counts once)',
              cell: (d) => CurrencyText(annualOf(d), currency: currencyOf(d)),
              sortValue: (d) => annualOf(d).minor,
              exportValue: (d) => annualOf(d).major.toStringAsFixed(2),
              filter: GridFilter.numberRange((d) => annualOf(d).major),
              footer: (rows) => money(_service.summariseDealers(rows).annualCost),
            ),
            GridColumn(
              id: 'status',
              label: 'Status',
              cardRole: CardRole.badge,
              minWidth: 110,
              cell: (d) => StatusBadge.entity(d.status),
              sortValue: (d) => d.status.label,
              exportValue: (d) => d.status.label,
              filter: GridFilter.choice((d) => d.status.label, options: [
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
              minWidth: 2 * AppSpacing.md + 48 * actionButtons,
              cell: (d) => _RowActions(
                dealer: d,
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

  static String _plural(int n) => n == 1 ? '1 dealer' : '$n dealers';

  static Future<void> _bulkStatus(BuildContext context, Repository repo,
      List<Dealer> rows, EntityStatus status) async {
    if (status != EntityStatus.active) {
      final ok = await showConfirmDialog(
        context,
        title: 'Mark ${_plural(rows.length)} inactive?',
        message: 'Their linked expenses become inactive too, so they stop '
            'counting towards your operating costs.',
        confirmLabel: 'Mark inactive',
      );
      if (!ok || !context.mounted) return;
    }
    await runGridBulk<Dealer>(
      context,
      rows: rows,
      verb: 'Updating',
      noun: 'dealers',
      describe: (d) => d.name,
      task: (d) => repo.saveDealer(d.copyWith(status: status), isNew: false),
    );
  }

  static Future<void> _bulkDelete(
      BuildContext context, Repository repo, List<Dealer> rows) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Delete ${_plural(rows.length)}?',
      message: 'Their linked expenses will also be removed. This removes '
          'them for everyone and cannot be easily undone.',
    );
    if (!ok || !context.mounted) return;
    await runGridBulk<Dealer>(
      context,
      rows: rows,
      verb: 'Deleting',
      noun: 'dealers',
      describe: (d) => d.name,
      task: (d) => repo.deleteDealer(d.id, known: d),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) => const AppPage(
        children: [
          PageHeader(title: 'Dealers', icon: Icons.handshake_outlined),
          SizedBox(height: AppSpacing.lg),
          SkeletonCard(lines: 1, height: 88),
          SizedBox(height: AppSpacing.lg),
          SkeletonCard(lines: 8),
        ],
      );
}

class _RowActions extends StatelessWidget {
  const _RowActions({
    required this.dealer,
    required this.canEdit,
    required this.canDelete,
  });

  final Dealer dealer;
  final bool canEdit;
  final bool canDelete;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (dealer.url.isNotEmpty)
          IconButton(
            tooltip: 'Open website',
            icon: const Icon(Icons.open_in_new, size: 18),
            onPressed: () => DealerActions.openWebsite(dealer.url),
          )
        else
          const SizedBox(width: 48),
        if (canEdit)
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined, size: 18),
            onPressed: () =>
                DealersScreen.openForm(context, dealer, dealer.businessId),
          ),
        if (canDelete)
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: () => DealerActions.delete(context, dealer),
          ),
      ],
    );
  }
}

/// The single-dealer actions, shared by the list rows and the detail page.
class DealerActions {
  DealerActions._();

  static void openWebsite(String url) {
    final normalised = url.startsWith('http://') || url.startsWith('https://')
        ? url
        : 'https://$url';
    html.window.open(normalised, '_blank');
  }

  /// Confirms (warning that the linked expense goes too) and deletes. Returns
  /// true when the dealer was deleted.
  static Future<bool> delete(BuildContext context, Dealer dealer) async {
    final repo = context.read<AppState>().repository;
    final ok = await showConfirmDialog(
      context,
      title: 'Delete dealer?',
      message: 'Delete "${dealer.name}"? Its linked expense will also be '
          'removed. This action cannot be easily undone.',
    );
    if (ok != true) return false;
    try {
      await repo.deleteDealer(dealer.id, known: dealer);
      if (context.mounted) showSuccessSnack(context, 'Dealer deleted');
      return true;
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e);
      return false;
    }
  }

  /// Switches a dealer (and so its linked expense) between active and inactive.
  static Future<void> setStatus(
      BuildContext context, Dealer dealer, EntityStatus status) async {
    final repo = context.read<AppState>().repository;
    try {
      await repo.saveDealer(dealer.copyWith(status: status), isNew: false);
      if (context.mounted) {
        showSuccessSnack(context, 'Dealer marked ${status.label.toLowerCase()}');
      }
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e);
    }
  }
}

class _DealerFormDialog extends StatefulWidget {
  const _DealerFormDialog({
    required this.existing,
    required this.repo,
    required this.businesses,
    this.preselectBusinessId,
  });

  final Dealer? existing;
  final Repository repo;
  final List<Business> businesses;
  final String? preselectBusinessId;

  @override
  State<_DealerFormDialog> createState() => _DealerFormDialogState();
}

class _DealerFormDialogState extends State<_DealerFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _url;
  late final TextEditingController _description;
  late final TextEditingController _cost;
  late final TextEditingController _contactName;
  late final TextEditingController _contactInfo;
  late final TextEditingController _notes;
  late RecurrenceFrequency _frequency;
  late EntityStatus _status;
  DateTime? _startDate;
  DateTime? _endDate;
  String? _businessId;

  Dealer? get _existing => widget.existing;

  /// The chosen business's currency symbol, for the money fields.
  String get _symbol => (widget.businesses
              .where((b) => b.id == _businessId)
              .firstOrNull
              ?.currency ??
          CurrencyCode.inr)
      .symbol;

  @override
  void initState() {
    super.initState();
    final d = _existing;
    _name = TextEditingController(text: d?.name ?? '');
    _url = TextEditingController(text: d?.url ?? '');
    _description = TextEditingController(text: d?.description ?? '');
    _cost = TextEditingController(
        text: d == null || d.cost.isZero ? '' : d.cost.major.toString());
    _contactName = TextEditingController(text: d?.contactName ?? '');
    _contactInfo = TextEditingController(text: d?.contactInfo ?? '');
    _notes = TextEditingController(text: d?.notes ?? '');
    _frequency = d?.costFrequency ?? RecurrenceFrequency.monthly;
    _status = d?.status ?? EntityStatus.active;
    _startDate = d?.startDate;
    _endDate = d?.endDate;
    _businessId = d?.businessId ??
        widget.preselectBusinessId ??
        (widget.businesses.isNotEmpty ? widget.businesses.first.id : null);
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _description.dispose();
    _cost.dispose();
    _contactName.dispose();
    _contactInfo.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isNew = _existing == null;
    final t = context.tokens;
    return FormDialog(
      title: isNew ? 'Add Dealer' : 'Edit Dealer',
      icon: Icons.handshake_outlined,
      draftKey: isNew ? 'dealer.new' : null,
      onSubmit: _submit,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FormSection(
              title: 'Dealer',
              icon: Icons.handshake_outlined,
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
                  label: 'Dealer Name',
                  controller: _name,
                  isRequired: true,
                  validator: (v) =>
                      Validators.required(v, field: 'Dealer name'),
                ),
                const FormGap(),
                AppTextField(
                  label: 'Dealer URL',
                  controller: _url,
                  hintText: 'https://…',
                  helper: 'Adds an "Open website" shortcut.',
                  validator: (v) => Validators.url(v),
                ),
                const FormGap(),
                AppTextField(
                    label: 'Description',
                    controller: _description,
                    maxLines: 2),
              ],
            ),
            FormSection(
              title: 'Contact',
              icon: Icons.contact_page_outlined,
              children: [
                FormRow([
                  AppTextField(
                      label: 'Contact Name', controller: _contactName),
                  AppTextField(
                      label: 'Contact Information', controller: _contactInfo),
                ]),
              ],
            ),
            FormSection(
              title: 'Cost & schedule',
              icon: Icons.event_repeat_outlined,
              children: [
                FormRow([
                  AppMoneyField(
                    symbol: _symbol,
                    label: 'Cost',
                    controller: _cost,
                    isRequired: true,
                    validator: (v) =>
                        Validators.nonNegativeNumber(v, field: 'Cost'),
                  ),
                  AppDropdown<RecurrenceFrequency>(
                    label: 'Cost Frequency',
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
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Icon(Icons.info_outline, size: 14, color: t.info),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'This cost is mirrored automatically into Business '
                        'Expenses under the Dealer category.',
                        style:
                            TextStyle(fontSize: 12, color: t.textSecondary),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            FormSection(
              title: 'Notes',
              icon: Icons.sticky_note_2_outlined,
              children: [
                AppTextField(label: 'Notes', controller: _notes, maxLines: 3),
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
      showErrorSnack(context, 'Select a business for this dealer.');
      return false;
    }
    final isNew = _existing == null;
    final dealer = (_existing ??
            Dealer(id: '', businessId: bizId, name: _name.text.trim()))
        .copyWith(
      name: _name.text.trim(),
      url: _url.text.trim(),
      description: _description.text.trim(),
      cost: Money.parse(_cost.text),
      costFrequency: _frequency,
      startDate: _startDate,
      endDate: _endDate,
      status: _status,
      contactName: _contactName.text.trim(),
      contactInfo: _contactInfo.text.trim(),
      notes: _notes.text.trim(),
    );
    try {
      await widget.repo.saveDealer(dealer, isNew: isNew);
      return true;
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
      return false;
    }
  }
}
