import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/enums.dart';
import '../../core/permissions.dart';
import '../../core/routing/app_routes.dart';
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
                onPressed: () => openForm(context, null),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Business'),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        AppDataTable<Business>(
          rows: businesses,
          onRowTap: (b) => context.go(Routes.businessDetailPath(b.id)),
          searchableText: (b) =>
              '${b.name} ${b.type} ${b.country} ${b.foundedBy} ${b.ownedBy}',
          emptyTitle: 'No businesses yet',
          emptyMessage: canCreate
              ? 'Create your first business to start tracking profitability.'
              : 'No businesses have been assigned to you.',
          emptyAction: canCreate
              ? ElevatedButton.icon(
                  onPressed: () => openForm(context, null),
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
              label: 'Founded By',
              cell: (b) => Text(b.foundedBy.isEmpty ? '—' : b.foundedBy),
              sortValue: (b) => b.foundedBy.toLowerCase(),
            ),
            AppColumn(
              label: 'Country',
              cell: (b) => Text(b.country),
              sortValue: (b) => b.country,
            ),
            AppColumn(
              label: 'Tenure',
              cell: (b) => Text(
                b.tenure(DateTime.now())?.shortLabel ?? '—',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              // Sort by the absolute span so "—" (no start date) sorts last.
              sortValue: (b) => b.tenure(DateTime.now())?.totalDays ?? -1,
            ),
            AppColumn(
              label: 'Status',
              cell: (b) => _BusinessStatusCell(business: b),
              sortValue: (b) => b.lifecycle.label,
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

  static Future<void> openForm(BuildContext context, Business? existing) async {
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

/// The Status cell in the businesses table: the operational lifecycle badge
/// (Active / Closed) plus a secondary visibility badge when the row is hidden
/// (Inactive) or archived, so both axes are legible at a glance.
class _BusinessStatusCell extends StatelessWidget {
  const _BusinessStatusCell({required this.business});

  final Business business;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        StatusBadge(
          label: business.lifecycle.label,
          tone: business.lifecycle.isClosed
              ? BadgeTone.warning
              : BadgeTone.success,
        ),
        if (business.status != EntityStatus.active)
          StatusBadge.entity(business.status),
      ],
    );
  }
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
            onPressed: () => BusinessesScreen.openForm(context, business),
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
  late final TextEditingController _website;
  late final TextEditingController _country;
  late final TextEditingController _foundedBy;
  late final TextEditingController _ownedBy;
  late final TextEditingController _facebook;
  late final TextEditingController _instagram;
  late final TextEditingController _x;
  late final TextEditingController _pinterest;
  late final TextEditingController _linkedin;
  late final TextEditingController _reddit;
  late final TextEditingController _otherSocial;
  late CurrencyCode _currency;
  late EntityStatus _status;
  late CompanySize _size;
  late BusinessLifecycle _lifecycle;
  DateTime? _startDate;
  DateTime? _endDate;
  // Business Type is a free-form string with searchable suggestions; the
  // selected/typed value is held here so imported values outside the preset
  // list are preserved.
  String _type = '';

  Business? get _existing => widget.existing;

  @override
  void initState() {
    super.initState();
    final b = _existing;
    _name = TextEditingController(text: b?.name ?? '');
    _description = TextEditingController(text: b?.description ?? '');
    _website = TextEditingController(text: b?.website ?? '');
    _country = TextEditingController(text: b?.country ?? 'India');
    _foundedBy = TextEditingController(text: b?.foundedBy ?? '');
    _ownedBy = TextEditingController(text: b?.ownedBy ?? '');
    _facebook = TextEditingController(text: b?.facebookUrl ?? '');
    _instagram = TextEditingController(text: b?.instagramUrl ?? '');
    _x = TextEditingController(text: b?.xUrl ?? '');
    _pinterest = TextEditingController(text: b?.pinterestUrl ?? '');
    _linkedin = TextEditingController(text: b?.linkedinUrl ?? '');
    _reddit = TextEditingController(text: b?.redditUrl ?? '');
    _otherSocial = TextEditingController(text: b?.otherSocialUrl ?? '');
    _currency = b?.currency ?? CurrencyCode.inr;
    _status = b?.status ?? EntityStatus.active;
    _size = b?.size ?? CompanySize.small;
    _lifecycle = b?.lifecycle ?? BusinessLifecycle.active;
    _startDate = b?.startDate;
    _endDate = b?.endDate;
    _type = b?.type ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _website.dispose();
    _country.dispose();
    _foundedBy.dispose();
    _ownedBy.dispose();
    _facebook.dispose();
    _instagram.dispose();
    _x.dispose();
    _pinterest.dispose();
    _linkedin.dispose();
    _reddit.dispose();
    _otherSocial.dispose();
    super.dispose();
  }

  /// Preset business-type suggestions plus any imported value not already in
  /// the list (so an existing off-list type stays selectable).
  List<String> get _typeItems {
    final items = [...kBusinessTypes];
    if (_type.isNotEmpty && !items.contains(_type)) items.insert(0, _type);
    return items;
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
              AppSearchableDropdown<String>(
                label: 'Business Type',
                value: _type.isEmpty ? null : _type,
                items: _typeItems,
                itemLabel: (t) => t,
                hintText: 'Search or select…',
                onChanged: (v) => setState(() => _type = v ?? ''),
              ),
              AppTextField(label: 'Country', controller: _country),
            ]),
            const FormGap(),
            FormRow([
              AppDropdown<CompanySize>(
                label: 'Company Size',
                value: _size,
                items: CompanySize.values,
                itemLabel: (s) => s.label,
                onChanged: (v) => setState(() => _size = v ?? _size),
              ),
              AppDropdown<CurrencyCode>(
                label: 'Currency',
                value: _currency,
                items: CurrencyCode.values,
                itemLabel: (c) => '${c.name.toUpperCase()} (${c.symbol})',
                onChanged: (v) => setState(() => _currency = v ?? _currency),
              ),
              AppDropdown<EntityStatus>(
                label: 'Visibility',
                value: _status,
                items: const [EntityStatus.active, EntityStatus.inactive],
                itemLabel: (s) => s.label,
                helper: 'Hide from active views without archiving',
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
            const FormGap(),
            const _SectionLabel('Founding & Ownership'),
            const FormGap(),
            FormRow([
              AppTextField(
                label: 'Founded By',
                controller: _foundedBy,
                hintText: 'e.g. Jane Doe',
              ),
              AppTextField(
                label: 'Owned By',
                controller: _ownedBy,
                hintText: 'Current owner',
              ),
            ]),
            const FormGap(),
            FormRow([
              AppDropdown<BusinessLifecycle>(
                label: 'Business Status',
                value: _lifecycle,
                items: BusinessLifecycle.values,
                itemLabel: (l) => l.label,
                onChanged: (v) => setState(() {
                  _lifecycle = v ?? _lifecycle;
                  // Dropping back to Active clears any stale closure date.
                  if (!_lifecycle.isClosed) _endDate = null;
                }),
              ),
              AppDateField(
                label: 'Start Date',
                value: _startDate,
                helper: 'When the business began trading',
                lastDate: DateTime.now(),
                onChanged: (v) => setState(() => _startDate = v),
              ),
            ]),
            if (_lifecycle.isClosed) ...[
              const FormGap(),
              AppDateField(
                label: 'End Date',
                value: _endDate,
                isRequired: true,
                helper: 'When the business ceased trading',
                firstDate: _startDate,
                onChanged: (v) => setState(() => _endDate = v),
              ),
            ],
            const FormGap(),
            const _SectionLabel('Social Media'),
            const FormGap(),
            FormRow([
              AppTextField(
                label: 'Facebook',
                controller: _facebook,
                hintText: 'https://facebook.com/…',
                validator: (v) => Validators.url(v),
              ),
              AppTextField(
                label: 'Instagram',
                controller: _instagram,
                hintText: 'https://instagram.com/…',
                validator: (v) => Validators.url(v),
              ),
            ]),
            const FormGap(),
            FormRow([
              AppTextField(
                label: 'X (Twitter)',
                controller: _x,
                hintText: 'https://x.com/…',
                validator: (v) => Validators.url(v),
              ),
              AppTextField(
                label: 'Pinterest',
                controller: _pinterest,
                hintText: 'https://pinterest.com/…',
                validator: (v) => Validators.url(v),
              ),
            ]),
            const FormGap(),
            FormRow([
              AppTextField(
                label: 'LinkedIn',
                controller: _linkedin,
                hintText: 'https://linkedin.com/…',
                validator: (v) => Validators.url(v),
              ),
              AppTextField(
                label: 'Reddit',
                controller: _reddit,
                hintText: 'https://reddit.com/…',
                validator: (v) => Validators.url(v),
              ),
            ]),
            const FormGap(),
            AppTextField(
              label: 'Other',
              controller: _otherSocial,
              hintText: 'https://…',
              validator: (v) => Validators.url(v),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return false;
    // A closed business needs an end date, and it can't precede the start.
    if (_lifecycle.isClosed) {
      if (_endDate == null) {
        showErrorSnack(context, 'Select an end date for a closed business.');
        return false;
      }
      if (_startDate != null && _endDate!.isBefore(_startDate!)) {
        showErrorSnack(context, 'End date cannot be before the start date.');
        return false;
      }
    }
    final isNew = _existing == null;
    // Active businesses carry no closure date, whatever was previously set.
    final endDate = _lifecycle.isClosed ? _endDate : null;
    final business = (_existing ??
            Business(id: '', name: _name.text.trim()))
        .copyWith(
      name: _name.text.trim(),
      description: _description.text.trim(),
      type: _type.trim(),
      website: _website.text.trim(),
      country: _country.text.trim(),
      currency: _currency,
      size: _size,
      status: _status,
      lifecycle: _lifecycle,
      foundedBy: _foundedBy.text.trim(),
      ownedBy: _ownedBy.text.trim(),
      startDate: _startDate,
      endDate: endDate,
      facebookUrl: _facebook.text.trim(),
      instagramUrl: _instagram.text.trim(),
      xUrl: _x.text.trim(),
      pinterestUrl: _pinterest.text.trim(),
      linkedinUrl: _linkedin.text.trim(),
      redditUrl: _reddit.text.trim(),
      otherSocialUrl: _otherSocial.text.trim(),
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

/// A small left-aligned section heading used to group related form fields.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Color(0xFF6B7280),
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
