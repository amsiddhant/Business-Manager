import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/enums.dart';
import '../../core/permissions.dart';
import '../../core/theme/app_theme.dart';
import '../../core/validators.dart';
import '../../data/repository.dart';
import '../../models/business.dart';
import '../../state/app_state.dart';
import '../../state/data_controller.dart';
import '../../widgets/common/confirm_dialog.dart';
import '../../widgets/common/data_table_card.dart';
import '../../widgets/common/page_header.dart';
import '../../widgets/common/state_views.dart';
import '../../widgets/common/status_badge.dart';
import '../../widgets/forms/form_dialog.dart';
import '../../widgets/forms/form_fields.dart';

/// Lists all businesses the current user can access, with create / edit /
/// archive actions gated by permission.
class BusinessesScreen extends StatelessWidget {
  const BusinessesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataController>();
    final appState = context.watch<AppState>();
    final user = appState.currentUser;

    if (data.loading && !data.loaded) {
      return const _Loading();
    }
    if (data.error != null && !data.loaded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PageHeader(title: 'Businesses'),
          const SizedBox(height: 48),
          ErrorView(message: data.error!, onRetry: () => data.refresh()),
        ],
      );
    }

    final canCreate = user?.can(Permission.createBusiness) ?? false;
    final canEdit = user?.can(Permission.editBusiness) ?? false;
    final canArchive = user?.can(Permission.deleteBusiness) ?? false;

    final businesses = data.businesses;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: 'Businesses',
          subtitle: 'Manage the businesses in your portfolio',
          actions: [
            if (canCreate)
              ElevatedButton.icon(
                onPressed: () => _openForm(context, null),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Business'),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        AppDataTable<Business>(
          rows: businesses,
          searchableText: (b) => '${b.name} ${b.type} ${b.country}',
          emptyTitle: 'No businesses yet',
          emptyMessage: canCreate
              ? 'Create your first business to start tracking profitability.'
              : 'No businesses have been assigned to you.',
          emptyAction: canCreate
              ? ElevatedButton.icon(
                  onPressed: () => _openForm(context, null),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Business'),
                )
              : null,
          columns: [
            AppColumn(
              label: 'Business',
              cell: (b) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(b.name,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (b.type.isNotEmpty)
                    Text(b.type,
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF6B7280))),
                ],
              ),
              sortValue: (b) => b.name.toLowerCase(),
            ),
            AppColumn(
              label: 'Country',
              cell: (b) => Text(b.country),
              sortValue: (b) => b.country,
            ),
            AppColumn(
              label: 'Currency',
              cell: (b) => Text(b.currency.name.toUpperCase()),
              sortValue: (b) => b.currency.name,
            ),
            AppColumn(
              label: 'Status',
              cell: (b) => StatusBadge.entity(b.status),
              sortValue: (b) => b.status.label,
            ),
            AppColumn(
              label: '',
              cell: (b) => _RowActions(
                business: b,
                canEdit: canEdit,
                canArchive: canArchive,
              ),
            ),
          ],
        ),
      ],
    );
  }

  static Future<void> _openForm(BuildContext context, Business? existing) async {
    final data = context.read<DataController>();
    final repo = context.read<AppState>().repository;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _BusinessFormDialog(existing: existing, repo: repo),
    );
    if (saved == true) {
      await data.refresh();
      if (context.mounted) {
        showSuccessSnack(
            context,
            existing == null
                ? 'Business created successfully'
                : 'Business updated successfully');
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
          PageHeader(title: 'Businesses'),
          SizedBox(height: 48),
          LoadingView(),
        ],
      );
}

class _RowActions extends StatelessWidget {
  const _RowActions({
    required this.business,
    required this.canEdit,
    required this.canArchive,
  });

  final Business business;
  final bool canEdit;
  final bool canArchive;

  @override
  Widget build(BuildContext context) {
    if (!canEdit && !canArchive) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (canEdit)
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined, size: 18),
            onPressed: () => BusinessesScreen._openForm(context, business),
          ),
        if (canArchive && business.status != EntityStatus.archived)
          IconButton(
            tooltip: 'Archive',
            icon: const Icon(Icons.archive_outlined, size: 18),
            onPressed: () => _archive(context),
          ),
      ],
    );
  }

  Future<void> _archive(BuildContext context) async {
    final data = context.read<DataController>();
    final repo = context.read<AppState>().repository;
    final ok = await showConfirmDialog(
      context,
      title: 'Archive business?',
      message:
          'Archiving "${business.name}" hides it and its data from active '
          'views. Financial records are preserved and can be restored.',
      confirmLabel: 'Archive',
    );
    if (ok != true) return;
    try {
      await repo.archiveBusiness(business.id);
      await data.refresh();
      if (context.mounted) {
        showSuccessSnack(context, 'Business archived');
      }
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e);
    }
  }
}

class _BusinessFormDialog extends StatefulWidget {
  const _BusinessFormDialog({required this.existing, required this.repo});

  final Business? existing;
  final Repository repo;

  @override
  State<_BusinessFormDialog> createState() => _BusinessFormDialogState();
}

class _BusinessFormDialogState extends State<_BusinessFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _type;
  late final TextEditingController _website;
  late final TextEditingController _country;
  late CurrencyCode _currency;
  late EntityStatus _status;

  Business? get _existing => widget.existing;

  @override
  void initState() {
    super.initState();
    final b = _existing;
    _name = TextEditingController(text: b?.name ?? '');
    _description = TextEditingController(text: b?.description ?? '');
    _type = TextEditingController(text: b?.type ?? '');
    _website = TextEditingController(text: b?.website ?? '');
    _country = TextEditingController(text: b?.country ?? 'India');
    _currency = b?.currency ?? CurrencyCode.inr;
    _status = b?.status ?? EntityStatus.active;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _type.dispose();
    _website.dispose();
    _country.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FormDialog(
      title: _existing == null ? 'Add Business' : 'Edit Business',
      onSubmit: _submit,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppTextField(
              label: 'Business Name',
              controller: _name,
              isRequired: true,
              validator: (v) => Validators.required(v, field: 'Business name'),
            ),
            const FormGap(),
            FormRow([
              AppTextField(label: 'Business Type', controller: _type),
              AppTextField(label: 'Country', controller: _country),
            ]),
            const FormGap(),
            FormRow([
              AppDropdown<CurrencyCode>(
                label: 'Currency',
                value: _currency,
                items: CurrencyCode.values,
                itemLabel: (c) => '${c.name.toUpperCase()} (${c.symbol})',
                onChanged: (v) => setState(() => _currency = v ?? _currency),
              ),
              AppDropdown<EntityStatus>(
                label: 'Status',
                value: _status,
                items: const [EntityStatus.active, EntityStatus.inactive],
                itemLabel: (s) => s.label,
                onChanged: (v) => setState(() => _status = v ?? _status),
              ),
            ]),
            const FormGap(),
            AppTextField(
              label: 'Website',
              controller: _website,
              hintText: 'https://example.com',
              validator: (v) => Validators.url(v),
            ),
            const FormGap(),
            AppTextField(
              label: 'Description',
              controller: _description,
              maxLines: 3,
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return false;
    final isNew = _existing == null;
    final business = (_existing ??
            Business(id: '', name: _name.text.trim()))
        .copyWith(
      name: _name.text.trim(),
      description: _description.text.trim(),
      type: _type.text.trim(),
      website: _website.text.trim(),
      country: _country.text.trim(),
      currency: _currency,
      status: _status,
    );
    try {
      await widget.repo.saveBusiness(business, isNew: isNew);
      return true;
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
      return false;
    }
  }
}
