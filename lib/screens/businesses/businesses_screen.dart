import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/enums.dart';
import '../../core/permissions.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_x.dart';
import '../../core/utils/date_utils.dart';
import '../../core/validators.dart';
import '../../data/repository.dart';
import '../../models/business.dart';
import '../../services/profit_calculation_service.dart';
import '../../services/summaries/business_summaries.dart';
import '../../state/app_state.dart';
import '../../state/data_controller.dart';
import '../../widgets/common/confirm_dialog.dart';
import '../../widgets/common/initials_avatar.dart';
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

/// Lists all businesses the current user can access, with create / edit /
/// archive / restore actions gated by permission: headline counts, status
/// quick filters, column filters, bulk archive & restore, and CSV export.
class BusinessesScreen extends StatefulWidget {
  const BusinessesScreen({super.key});

  @override
  State<BusinessesScreen> createState() => _BusinessesScreenState();

  static Future<void> openForm(BuildContext context, Business? existing) async {
    final repo = context.read<AppState>().repository;
    final saved = await showAppForm<bool>(
      context: context,
      builder: (_) => _BusinessFormDialog(existing: existing, repo: repo),
    );
    if (saved == true) {
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

/// The single-business actions, shared by the list rows and the detail page.
/// Each asks for confirmation, saves, and reports the outcome in a snack.
class BusinessActions {
  BusinessActions._();

  /// Archived or hidden businesses can be brought back.
  static bool canRestore(Business b) => b.status != EntityStatus.active;

  static bool canArchive(Business b) => b.status != EntityStatus.archived;

  /// Archives [business] after confirmation. True when it was archived.
  static Future<bool> archive(BuildContext context, Business business) async {
    final repo = context.read<AppState>().repository;
    final ok = await showConfirmDialog(
      context,
      title: 'Archive business?',
      message: 'Archiving "${business.name}" hides it and its data from active '
          'views. Financial records are preserved and it can be restored.',
      confirmLabel: 'Archive',
    );
    if (!ok) return false;
    try {
      await repo.archiveBusiness(business.id, known: business);
      if (context.mounted) showSuccessSnack(context, 'Business archived');
      return true;
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e);
      return false;
    }
  }

  /// Sets an archived / inactive [business] back to active after
  /// confirmation. True when it was restored.
  static Future<bool> restore(BuildContext context, Business business) async {
    final repo = context.read<AppState>().repository;
    final archived = business.status == EntityStatus.archived;
    final ok = await showConfirmDialog(
      context,
      title: 'Restore business?',
      message: '"${business.name}" will be active again and show in active '
          'views, along with its data.',
      confirmLabel: 'Restore',
      destructive: false,
    );
    if (!ok) return false;
    try {
      await repo.saveBusiness(
        business.copyWith(status: EntityStatus.active),
        isNew: false,
      );
      if (context.mounted) {
        showSuccessSnack(
            context, archived ? 'Business restored' : 'Business reactivated');
      }
      return true;
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e);
      return false;
    }
  }
}

/// The state a business is in, for the list's filters: archived and inactive
/// (visibility) win over closed (lifecycle).
String businessStateLabel(Business b) {
  if (b.status == EntityStatus.archived) return 'Archived';
  if (b.status == EntityStatus.inactive) return 'Inactive';
  if (b.isClosed) return 'Closed';
  return 'Active';
}

class _BusinessesScreenState extends State<BusinessesScreen> {
  static const _service = ProfitCalculationService();

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataController>();
    final appState = context.watch<AppState>();
    final user = appState.currentUser;

    if (data.loading && !data.loaded) {
      return const _Loading();
    }
    if (data.error != null && !data.loaded) {
      return AppPage(
        children: [
          const PageHeader(title: 'Businesses', icon: Icons.business_outlined),
          const SizedBox(height: 48),
          ErrorView(message: data.error!, onRetry: () => data.refresh()),
        ],
      );
    }

    final canCreate = user?.can(Permission.createBusiness) ?? false;
    final canEdit = user?.can(Permission.editBusiness) ?? false;
    final canArchive = user?.can(Permission.deleteBusiness) ?? false;
    final repo = appState.repository;

    final businesses = data.businesses;
    final now = DateTime.now();
    final summary = _service.summariseBusinesses(businesses, now);

    final addButton = canCreate
        ? FilledButton.icon(
            onPressed: () => BusinessesScreen.openForm(context, null),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Business'),
          )
        : null;

    final t = context.tokens;
    final avg = summary.averageTenureDays;

    return AppPage.slivers(
      slivers: [
        SliverToBoxAdapter(
          child: PageHeader(
            title: 'Businesses',
            icon: Icons.business_outlined,
            count: businesses.length,
            subtitle: 'Manage the businesses in your portfolio',
            actions: [?addButton],
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
        if (businesses.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: KpiStrip(items: [
              KpiItem(
                label: 'Businesses',
                value: '${summary.total}',
                icon: Icons.business_outlined,
                caption: 'In your portfolio',
              ),
              KpiItem(
                label: 'Trading',
                value: '${summary.trading}',
                icon: Icons.storefront_outlined,
                tone: summary.trading > 0 ? t.success : null,
                caption: 'Active and operating',
                tooltip: 'Visible businesses that have not been closed.',
              ),
              KpiItem(
                label: 'Closed',
                value: '${summary.closed}',
                icon: Icons.history_toggle_off,
                tone: summary.closed > 0 ? t.warning : null,
                caption: 'Wound down',
              ),
              KpiItem(
                label: 'Inactive / archived',
                value: '${summary.inactive + summary.archived}',
                icon: Icons.archive_outlined,
                caption: '${summary.inactive} inactive · '
                    '${summary.archived} archived',
                tooltip: 'Hidden from active views. Restore them from the '
                    'row menu.',
              ),
              KpiItem(
                label: 'Avg. tenure',
                value: avg == null ? '—' : _tenureOf(avg),
                icon: Icons.timelapse_outlined,
                tooltip: 'Average time from start date to today (or to the '
                    'closing date), over businesses with a start date.',
              ),
            ]),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
        ],
        SliverAppDataGrid<Business>(
          gridId: 'businesses',
          rows: businesses,
          rowKey: (b) => b.id,
          exportName: 'businesses',
          searchHint: 'Search by name, type, country, owner or status…',
          searchText: (b) =>
              '${b.name} ${b.type} ${b.country} ${b.foundedBy} ${b.ownedBy} '
              '${b.lifecycle.label} ${b.status.label} ${b.currency.name}',
          onRowTap: (b) => context.go(Routes.businessDetailPath(b.id)),
          quickFilters: [
            GridQuickFilter<Business>(
              id: 'active',
              label: 'Active',
              test: (b) => businessStateLabel(b) == 'Active',
            ),
            GridQuickFilter<Business>(
              id: 'closed',
              label: 'Closed',
              test: (b) => businessStateLabel(b) == 'Closed',
            ),
            GridQuickFilter<Business>(
              id: 'inactive',
              label: 'Inactive',
              test: (b) => b.status == EntityStatus.inactive,
            ),
            GridQuickFilter<Business>(
              id: 'archived',
              label: 'Archived',
              test: (b) => b.status == EntityStatus.archived,
            ),
          ],
          bulkActions: [
            if (canEdit)
              GridBulkAction<Business>(
                label: 'Restore',
                icon: Icons.unarchive_outlined,
                allowed: BusinessActions.canRestore,
                onRun: (context, rows) => _bulkRestore(context, repo, rows),
              ),
            if (canArchive)
              GridBulkAction<Business>(
                label: 'Archive',
                icon: Icons.archive_outlined,
                destructive: true,
                allowed: BusinessActions.canArchive,
                onRun: (context, rows) => _bulkArchive(context, repo, rows),
              ),
          ],
          emptyTitle: 'No businesses yet',
          emptyIcon: Icons.business_outlined,
          emptyMessage: canCreate
              ? 'Create your first business to start tracking profitability.'
              : 'No businesses have been assigned to you.',
          emptyAction: addButton,
          columns: [
            GridColumn<Business>(
              id: 'name',
              label: 'Business',
              flex: 2,
              pinned: true,
              minWidth: 200,
              cardRole: CardRole.title,
              cell: (b) => Row(
                children: [
                  InitialsAvatar(name: b.name, size: 32),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(b.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              sortValue: (b) => b.name.toLowerCase(),
              exportValue: (b) => b.name,
            ),
            GridColumn<Business>(
              id: 'type',
              label: 'Type',
              cardRole: CardRole.subtitle,
              cell: (b) => Text(b.type.isEmpty ? '—' : b.type,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              sortValue: (b) => b.type.toLowerCase(),
              exportValue: (b) => b.type,
              filter: GridFilter.choice(
                  (b) => b.type.isEmpty ? 'No type' : b.type),
            ),
            GridColumn<Business>(
              id: 'founder',
              label: 'Founded By',
              flex: 2,
              cardRole: CardRole.meta,
              cell: (b) => Text(b.foundedBy.isEmpty ? '—' : b.foundedBy,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              sortValue: (b) => b.foundedBy.toLowerCase(),
              exportValue: (b) => b.foundedBy,
            ),
            GridColumn<Business>(
              id: 'owner',
              label: 'Owned By',
              flex: 2,
              visibleByDefault: false,
              cardRole: CardRole.hidden,
              cell: (b) => Text(b.ownedBy.isEmpty ? '—' : b.ownedBy,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              sortValue: (b) => b.ownedBy.toLowerCase(),
              exportValue: (b) => b.ownedBy,
            ),
            GridColumn<Business>(
              id: 'country',
              label: 'Country',
              cardRole: CardRole.meta,
              cell: (b) => Text(b.country.isEmpty ? '—' : b.country),
              sortValue: (b) => b.country,
              exportValue: (b) => b.country,
              filter: GridFilter.choice(
                  (b) => b.country.isEmpty ? 'No country' : b.country),
            ),
            GridColumn<Business>(
              id: 'currency',
              label: 'Currency',
              visibleByDefault: false,
              minWidth: 96,
              cardRole: CardRole.hidden,
              cell: (b) => Text(b.currency.name.toUpperCase()),
              sortValue: (b) => b.currency.name,
              exportValue: (b) => b.currency.name.toUpperCase(),
              filter: GridFilter.choice((b) => b.currency.name.toUpperCase()),
            ),
            GridColumn<Business>(
              id: 'start',
              label: 'Started',
              visibleByDefault: false,
              minWidth: 110,
              cardRole: CardRole.hidden,
              cell: (b) => Text(AppDate.format(b.startDate)),
              sortValue: (b) => b.startDate?.millisecondsSinceEpoch ?? 0,
              exportValue: (b) => AppDate.format(b.startDate),
              filter: GridFilter.dateRange((b) => b.startDate),
            ),
            GridColumn<Business>(
              id: 'tenure',
              label: 'Tenure',
              minWidth: 100,
              cardRole: CardRole.metric,
              cell: (b) => Text(
                b.tenure(now)?.shortLabel ?? '—',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              // Sort by the absolute span so "—" (no start date) sorts last.
              sortValue: (b) => b.tenure(now)?.totalDays ?? -1,
              exportValue: (b) => b.tenure(now)?.shortLabel ?? '',
            ),
            GridColumn<Business>(
              id: 'status',
              label: 'Status',
              minWidth: 150,
              cardRole: CardRole.badge,
              cell: (b) => _BusinessStatusCell(business: b),
              sortValue: (b) => businessStateLabel(b),
              exportValue: businessStateLabel,
              filter: GridFilter.choice(businessStateLabel, options: const [
                'Active',
                'Closed',
                'Inactive',
                'Archived',
              ]),
            ),
            GridColumn<Business>(
              id: 'actions',
              label: '',
              pinned: true,
              cardRole: CardRole.actions,
              // Edit and the More menu (48 px each) plus the cell padding.
              minWidth: 2 * AppSpacing.md +
                  48 * [canEdit, canEdit || canArchive].where((b) => b).length,
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

  /// "3 yr 2 mo" for an average of [days] days.
  static String _tenureOf(int days) {
    final years = days ~/ 365;
    final months = (days % 365) ~/ 30;
    if (years == 0 && months == 0) return '$days d';
    if (years == 0) return '$months mo';
    return months == 0 ? '$years yr' : '$years yr $months mo';
  }

  static Future<void> _bulkArchive(
      BuildContext context, Repository repo, List<Business> rows) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Archive ${_plural(rows.length)}?',
      message: 'They and their data are hidden from active views. Financial '
          'records are preserved and they can be restored.',
      confirmLabel: 'Archive',
    );
    if (!ok || !context.mounted) return;
    await runGridBulk<Business>(
      context,
      rows: rows,
      verb: 'Archiving',
      noun: 'businesses',
      describe: (b) => b.name,
      task: (b) => repo.archiveBusiness(b.id, known: b),
    );
  }

  static Future<void> _bulkRestore(
      BuildContext context, Repository repo, List<Business> rows) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Restore ${_plural(rows.length)}?',
      message: 'They will be active again and show in active views.',
      confirmLabel: 'Restore',
      destructive: false,
    );
    if (!ok || !context.mounted) return;
    await runGridBulk<Business>(
      context,
      rows: rows,
      verb: 'Restoring',
      noun: 'businesses',
      describe: (b) => b.name,
      task: (b) => repo.saveBusiness(
        b.copyWith(status: EntityStatus.active),
        isNew: false,
      ),
    );
  }

  static String _plural(int n) => n == 1 ? '1 business' : '$n businesses';
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) => const AppPage(
        children: [
          PageHeader(title: 'Businesses', icon: Icons.business_outlined),
          SizedBox(height: AppSpacing.lg),
          SkeletonCard(lines: 1, height: 88),
          SizedBox(height: AppSpacing.lg),
          SkeletonCard(lines: 8),
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

enum _BusinessAction { restore, archive }

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
    final canRestore = canEdit && BusinessActions.canRestore(business);
    final canArchiveRow = canArchive && BusinessActions.canArchive(business);
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
        if (canRestore || canArchiveRow)
          PopupMenuButton<_BusinessAction>(
            tooltip: 'More actions',
            icon: const Icon(Icons.more_vert, size: 18),
            onSelected: (action) => switch (action) {
              _BusinessAction.restore =>
                BusinessActions.restore(context, business),
              _BusinessAction.archive =>
                BusinessActions.archive(context, business),
            },
            itemBuilder: (_) => [
              if (canRestore)
                const PopupMenuItem(
                  value: _BusinessAction.restore,
                  child: _ActionRow(
                      icon: Icons.unarchive_outlined, label: 'Restore'),
                ),
              if (canArchiveRow)
                const PopupMenuItem(
                  value: _BusinessAction.archive,
                  child: _ActionRow(
                      icon: Icons.archive_outlined, label: 'Archive'),
                ),
            ],
          ),
      ],
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 18, color: context.tokens.textSecondary),
          const SizedBox(width: AppSpacing.md),
          Text(label),
        ],
      );
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

  /// Set on submit when the closed → end date rule is broken; shown inline
  /// under the dates and cleared as soon as they change.
  String? _dateIssue;

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

  /// The closed → end date rule, or null when the dates are fine.
  String? _dateRuleIssue() {
    if (!_lifecycle.isClosed) return null;
    if (_endDate == null) return 'Select an end date for a closed business.';
    if (_startDate != null && _endDate!.isBefore(_startDate!)) {
      return 'End date cannot be before the start date.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return FormDialog(
      title: _existing == null ? 'Add Business' : 'Edit Business',
      icon: Icons.business_outlined,
      draftKey: _existing == null ? 'business.new' : null,
      onSubmit: _submit,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FormSection(
              title: 'Basics',
              icon: Icons.storefront_outlined,
              first: true,
              children: [
                AppTextField(
                  label: 'Business Name',
                  controller: _name,
                  isRequired: true,
                  validator: (v) =>
                      Validators.required(v, field: 'Business name'),
                ),
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
                    helper: 'Figures for this business are shown in it',
                    onChanged: (v) =>
                        setState(() => _currency = v ?? _currency),
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
                AppTextField(
                  label: 'Description',
                  controller: _description,
                  maxLines: 3,
                ),
              ],
            ),
            FormSection(
              title: 'Ownership & dates',
              icon: Icons.event_outlined,
              children: [
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
                FormRow([
                  AppDropdown<BusinessLifecycle>(
                    label: 'Business Status',
                    value: _lifecycle,
                    items: BusinessLifecycle.values,
                    itemLabel: (l) => l.label,
                    helper: 'Closed once it has stopped trading',
                    onChanged: (v) => setState(() {
                      _lifecycle = v ?? _lifecycle;
                      _dateIssue = null;
                      // Dropping back to Active clears any stale closure date.
                      if (!_lifecycle.isClosed) _endDate = null;
                    }),
                  ),
                  AppDateField(
                    label: 'Start Date',
                    value: _startDate,
                    helper: 'When the business began trading',
                    lastDate: DateTime.now(),
                    onChanged: (v) => setState(() {
                      _startDate = v;
                      _dateIssue = null;
                    }),
                  ),
                ]),
                if (_lifecycle.isClosed) ...[
                  AppDateField(
                    label: 'End Date',
                    value: _endDate,
                    isRequired: true,
                    helper: 'When the business ceased trading',
                    firstDate: _startDate,
                    onChanged: (v) => setState(() {
                      _endDate = v;
                      _dateIssue = null;
                    }),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        _dateIssue == null
                            ? Icons.info_outline
                            : Icons.error_outline,
                        size: 16,
                        color: _dateIssue == null ? t.textTertiary : t.error,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          _dateIssue ??
                              'A closed business needs an end date, on or '
                                  'after its start date.',
                          style: TextStyle(
                            fontSize: 12.5,
                            color:
                                _dateIssue == null ? t.textSecondary : t.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
            FormSection(
              title: 'Online presence',
              icon: Icons.public,
              description: 'Shown as quick links on the business page.',
              children: [
                AppTextField(
                  label: 'Website',
                  controller: _website,
                  hintText: 'https://example.com',
                  validator: (v) => Validators.url(v),
                ),
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
                AppTextField(
                  label: 'Other',
                  controller: _otherSocial,
                  hintText: 'https://…',
                  validator: (v) => Validators.url(v),
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
    // A closed business needs an end date, and it can't precede the start.
    final issue = _dateRuleIssue();
    if (issue != null) {
      setState(() => _dateIssue = issue);
      return false;
    }
    final isNew = _existing == null;
    // Active businesses carry no closure date, whatever was previously set.
    final endDate = _lifecycle.isClosed ? _endDate : null;
    final business = (_existing ?? Business(id: '', name: _name.text.trim()))
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
