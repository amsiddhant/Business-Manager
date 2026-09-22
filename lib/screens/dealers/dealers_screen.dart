import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:universal_html/html.dart' as html;

import '../../core/enums.dart';
import '../../core/permissions.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../core/validators.dart';
import '../../data/repository.dart';
import '../../models/business.dart';
import '../../models/dealer.dart';
import '../../state/app_state.dart';
import '../../state/data_controller.dart';
import '../../state/filter_controller.dart';
import '../../widgets/common/confirm_dialog.dart';
import '../../widgets/common/currency_display.dart';
import '../../widgets/common/data_table_card.dart';
import '../../widgets/common/page_header.dart';
import '../../widgets/common/search_field.dart';
import '../../widgets/common/state_views.dart';
import '../../widgets/common/status_badge.dart';
import '../../widgets/forms/form_dialog.dart';
import '../../widgets/forms/form_fields.dart';

/// Lists dealers/vendors for the selected scope. Each dealer's recurring cost
/// is automatically mirrored into Business Expenses by the repository.
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
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _DealerFormDialog(
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
                ? 'Dealer created successfully'
                : 'Dealer updated successfully');
      }
    }
  }

  @override
  State<DealersScreen> createState() => _DealersScreenState();
}

class _DealersScreenState extends State<DealersScreen> {
  String _search = '';

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
          const PageHeader(title: 'Dealers'),
          const SizedBox(height: 48),
          ErrorView(message: data.error!, onRetry: () => data.refresh()),
        ],
      );
    }

    final bizId = filter.selectedBusinessId;
    final dealers = data.dealersFor(bizId);
    final canCreate = user?.can(Permission.createDealer) ?? false;
    final canEdit = user?.can(Permission.editDealer) ?? false;
    final canDelete = user?.can(Permission.deleteDealer) ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: 'Dealers',
          subtitle: 'Manage vendors — their cost flows into expenses',
          actions: [
            if (canCreate)
              ElevatedButton.icon(
                onPressed: () => DealersScreen.openForm(context, null, bizId),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Dealer'),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        SearchField(
          hintText: 'Search dealers by ID, name, contact, frequency or status…',
          onChanged: (v) => setState(() => _search = v),
        ),
        const SizedBox(height: AppSpacing.md),
        AppDataTable<Dealer>(
          rows: dealers,
          searchText: _search,
          onRowTap: (d) => context.go(Routes.dealerDetailPath(d.id)),
          searchableText: (d) =>
              '${d.id} ${d.name} ${d.contactName} ${d.contactInfo} '
              '${d.costFrequency.label} ${d.status.label}',
          emptyTitle: 'No dealers found',
          emptyMessage: canCreate
              ? 'Add a dealer to track vendor costs automatically.'
              : 'Dealers will appear here once added.',
          emptyAction: canCreate
              ? ElevatedButton.icon(
                  onPressed: () =>
                      DealersScreen.openForm(context, null, bizId),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Dealer'),
                )
              : null,
          columns: [
            AppColumn(
              label: 'Dealer',
              cell: (d) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(d.name,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (d.contactName.isNotEmpty)
                    Text(d.contactName,
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF6B7280))),
                ],
              ),
              sortValue: (d) => d.name.toLowerCase(),
            ),
            AppColumn(
              label: 'Cost',
              numeric: true,
              cell: (d) => CurrencyText(d.cost,
                  currency: _currencyFor(data, d.businessId)),
              sortValue: (d) => d.cost.minor,
            ),
            AppColumn(
              label: 'Frequency',
              cell: (d) => Text(d.costFrequency.label),
              sortValue: (d) => d.costFrequency.label,
            ),
            AppColumn(
              label: 'Contact',
              cell: (d) => Text(d.contactInfo.isEmpty ? '—' : d.contactInfo),
              sortValue: (d) => d.contactInfo,
            ),
            AppColumn(
              label: 'Status',
              cell: (d) => StatusBadge.entity(d.status),
              sortValue: (d) => d.status.label,
            ),
            AppColumn(
              label: '',
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
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) => const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(title: 'Dealers'),
          SizedBox(height: 48),
          LoadingView(),
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
            onPressed: () => _openUrl(dealer.url),
          ),
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
            onPressed: () => _delete(context),
          ),
      ],
    );
  }

  void _openUrl(String url) {
    final normalised = url.startsWith('http://') || url.startsWith('https://')
        ? url
        : 'https://$url';
    html.window.open(normalised, '_blank');
  }

  Future<void> _delete(BuildContext context) async {
    final data = context.read<DataController>();
    final repo = context.read<AppState>().repository;
    final ok = await showConfirmDialog(
      context,
      title: 'Delete dealer?',
      message: 'Delete "${dealer.name}"? Its linked expense will also be '
          'removed. This action cannot be easily undone.',
    );
    if (ok != true) return;
    try {
      await repo.deleteDealer(dealer.id);
      await data.refresh();
      if (context.mounted) showSuccessSnack(context, 'Dealer deleted');
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
    return FormDialog(
      title: isNew ? 'Add Dealer' : 'Edit Dealer',
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
              label: 'Dealer Name',
              controller: _name,
              isRequired: true,
              validator: (v) => Validators.required(v, field: 'Dealer name'),
            ),
            const FormGap(),
            FormRow([
              AppMoneyField(
                label: 'Cost',
                controller: _cost,
                isRequired: true,
                validator: (v) => Validators.nonNegativeNumber(v, field: 'Cost'),
              ),
              AppDropdown<RecurrenceFrequency>(
                label: 'Cost Frequency',
                isRequired: true,
                value: _frequency,
                items: RecurrenceFrequency.values,
                itemLabel: (f) => f.label,
                onChanged: (v) => setState(() => _frequency = v ?? _frequency),
              ),
            ]),
            const FormGap(),
            AppTextField(
              label: 'Dealer URL',
              controller: _url,
              hintText: 'https://…',
              validator: (v) => Validators.url(v),
            ),
            const FormGap(),
            FormRow([
              AppTextField(label: 'Contact Name', controller: _contactName),
              AppTextField(
                  label: 'Contact Information', controller: _contactInfo),
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
            AppTextField(
                label: 'Description', controller: _description, maxLines: 2),
            const FormGap(),
            AppTextField(label: 'Notes', controller: _notes, maxLines: 2),
            const SizedBox(height: AppSpacing.sm),
            const Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: AppColors.info),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'This cost is mirrored automatically into Business '
                    'Expenses under the Dealer category.',
                    style:
                        TextStyle(fontSize: 12, color: AppColors.textSecondary),
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
