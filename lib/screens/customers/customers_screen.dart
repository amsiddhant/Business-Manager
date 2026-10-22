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
import '../../models/customer.dart';
import '../../services/profit_calculation_service.dart';
import '../../services/summaries/customer_summaries.dart';
import '../../state/app_state.dart';
import '../../state/data_controller.dart';
import '../../state/filter_controller.dart';
import '../../widgets/common/confirm_dialog.dart';
import '../../widgets/common/csv_actions.dart';
import '../../widgets/common/currency_display.dart';
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
import 'invoice_action.dart';

/// Lists customers (CRM contacts) for the selected scope: pipeline figures,
/// deal-status quick filters, column filters, saved views, bulk status
/// changes and deletes, CSV import / export, and permission-gated create /
/// edit / duplicate / delete.
class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();

  /// Opens the add/edit form (also used by quick-create and the palette).
  /// [duplicateOf] prefills a new customer from an existing one (details and
  /// business tags only — never its contracts, contacts or comments).
  static Future<void> openForm(
      BuildContext context, Customer? existing, String? selectedBizId,
      {Customer? duplicateOf}) async {
    final data = context.read<DataController>();
    final repo = context.read<AppState>().repository;
    final businesses = data.selectableBusinesses;
    if (existing == null && businesses.isEmpty) {
      showErrorSnack(context, 'Create a business before adding customers.');
      return;
    }
    final saved = await showAppForm<bool>(
      context: context,
      builder: (_) => CustomerFormDialog(
        existing: existing,
        template: duplicateOf,
        repo: repo,
        businesses: businesses,
        preselectBusinessIds:
            selectedBizId == null ? const [] : [selectedBizId],
      ),
    );
    if (saved == true) {
      if (context.mounted) {
        showSuccessSnack(
            context,
            existing == null
                ? 'Customer created successfully'
                : 'Customer updated successfully');
      }
    }
  }
}

class _CustomersScreenState extends State<CustomersScreen> {
  static const _service = ProfitCalculationService();
  static final _epoch = DateTime.fromMillisecondsSinceEpoch(0);
  static DateTime _activityOf(Customer c) => c.lastActivityAt ?? _epoch;

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
          const PageHeader(title: 'Customers', icon: Icons.people_outline),
          const SizedBox(height: 48),
          ErrorView(message: data.error!, onRetry: () => data.refresh()),
        ],
      );
    }

    final bizId = filter.selectedBusinessId;
    final canCreate = user?.can(Permission.createCustomer) ?? false;
    final canExport = user?.can(Permission.exportData) ?? false;
    final canEdit = user?.can(Permission.editCustomer) ?? false;
    final canDelete = user?.can(Permission.deleteCustomer) ?? false;
    final repo = appState.repository;
    final t = context.tokens;
    final now = DateTime.now();

    final customers = [...data.customersFor(bizId)]
      ..sort((a, b) => _activityOf(b).compareTo(_activityOf(a)));

    CurrencyCode currencyOfBusiness(String id) =>
        data.businessById(id)?.currency ?? CurrencyCode.inr;
    // Figures are shown in the selected business's currency; INR for all.
    final pageCurrency =
        (bizId == null ? null : data.businessById(bizId))?.currency ??
            CurrencyCode.inr;

    /// The currency a customer's in-scope contracts are billed in, or null
    /// when they span businesses with different currencies.
    CurrencyCode? rowCurrency(Customer c) {
      final codes = {
        for (final k in _service.customerContractsInScope(c, bizId))
          currencyOfBusiness(k.businessId),
      };
      if (codes.isEmpty) return pageCurrency;
      return codes.length == 1 ? codes.first : null;
    }

    final summary =
        _service.summariseCustomers(customers, businessId: bizId, now: now);
    final scopeCurrencies = {
      for (final c in customers)
        for (final k in _service.customerContractsInScope(c, bizId))
          currencyOfBusiness(k.businessId),
    };
    final singleCurrency = scopeCurrencies.length <= 1;
    final winRate = summary.winRate;

    bool dueSoon(Customer c) {
      final e = _service.customerNextExpiry(c, bizId);
      return e != null && !e.isAfter(now.add(const Duration(days: 30)));
    }

    final addButton = canCreate
        ? FilledButton.icon(
            onPressed: () => CustomersScreen.openForm(context, null, bizId),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Customer'),
          )
        : null;

    return AppPage.slivers(
      slivers: [
        SliverToBoxAdapter(
          child: PageHeader(
            title: 'Customers',
            icon: Icons.people_outline,
            count: customers.length,
            subtitle: 'Manage leads, contacts and deal pipeline',
            actions: [
              if (canExport)
                OutlinedButton.icon(
                  onPressed: customers.isEmpty
                      ? null
                      : () => exportCustomersCsv(context, customers),
                  icon: const Icon(Icons.file_download_outlined, size: 18),
                  label: const Text('Export CSV'),
                ),
              if (canCreate)
                OutlinedButton.icon(
                  onPressed: () => importCustomersCsv(context),
                  icon: const Icon(Icons.file_upload_outlined, size: 18),
                  label: const Text('Import CSV'),
                ),
              ?addButton,
            ],
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
        if (customers.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: KpiStrip(items: [
              KpiItem(
                label: 'Customers',
                value: '${summary.count}',
                icon: Icons.people_outline,
                caption: '${summary.openCount} open deals',
              ),
              KpiItem(
                label: 'Won',
                value: '${summary.wonCount}',
                icon: Icons.verified_outlined,
                tone: t.success,
                caption: winRate == null
                    ? 'No closed deals yet'
                    : '${winRate.toStringAsFixed(0)}% win rate',
                tooltip: 'Deals marked Successful, and their share of the '
                    'deals that were won or lost.',
              ),
              KpiItem(
                label: 'Active contracts',
                value: '${summary.activeContracts}',
                icon: Icons.assignment_turned_in_outlined,
                caption: summary.expiredContracts == 0
                    ? null
                    : '${summary.expiredContracts} expired',
              ),
              KpiItem(
                label: 'Renewals due',
                value: '${summary.renewalsDue}',
                icon: Icons.event_repeat_outlined,
                tone: summary.renewalsDue > 0 ? t.warning : null,
                caption: 'Within 30 days',
                tooltip: 'Active contracts that expire in the next 30 days.',
              ),
              KpiItem(
                label: 'Annual recurring',
                value: singleCurrency
                    ? MoneyFormatter.compact(summary.annualRecurring,
                        scopeCurrencies.firstOrNull ?? pageCurrency)
                    : 'Mixed',
                icon: Icons.autorenew,
                caption: singleCurrency
                    ? 'Excludes one-time charges'
                    : 'Businesses bill in different currencies',
                tooltip: 'What the active contracts bill in a year '
                    '(monthly ones times twelve).',
              ),
            ]),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
        ],
        SliverAppDataGrid<Customer>(
          gridId: 'customers',
          rows: customers,
          rowKey: (c) => c.id,
          exportName: 'customers',
          initialSort: const [GridSort('activity', ascending: false)],
          searchHint: 'Search by name, email, phone or location…',
          searchText: (c) => '${c.id} ${c.name} ${c.businessType} '
              '${c.email} ${c.contactNo} ${c.location} ${c.dealStatus.label}',
          onRowTap: (c) => context.go(Routes.customerDetailPath(c.id)),
          quickFilters: [
            for (final s in DealStatus.values)
              GridQuickFilter<Customer>(
                id: s.wire,
                label: s.label,
                test: (c) => c.dealStatus == s,
              ),
            GridQuickFilter<Customer>(
              id: 'renewal-due',
              label: 'Renewal due',
              test: dueSoon,
            ),
          ],
          bulkActions: [
            if (canEdit)
              GridBulkAction<Customer>(
                label: 'Change status',
                icon: Icons.swap_horiz,
                children: [
                  // Successful needs a contract, captured one customer at a
                  // time from the customer's page.
                  for (final s in DealStatus.values)
                    if (s != DealStatus.successful)
                      GridBulkAction<Customer>(
                        label: s.label,
                        icon: Icons.flag_outlined,
                        allowed: (c) => c.dealStatus != s,
                        onRun: (context, rows) =>
                            _bulkStatus(context, repo, rows, s),
                      ),
                ],
              ),
            if (canDelete)
              GridBulkAction<Customer>(
                label: 'Delete',
                icon: Icons.delete_outline,
                destructive: true,
                onRun: (context, rows) => _bulkDelete(context, repo, rows),
              ),
          ],
          emptyTitle: 'No customers found',
          emptyIcon: Icons.people_outline,
          emptyMessage: canCreate
              ? 'Add your first customer to start tracking your pipeline.'
              : 'Customers will appear here once added.',
          emptyAction: addButton,
          columns: [
            GridColumn(
              id: 'name',
              label: 'Customer',
              flex: 2,
              pinned: true,
              cardRole: CardRole.title,
              minWidth: 200,
              cell: (c) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InitialsAvatar(name: c.name, size: 32),
                  const SizedBox(width: AppSpacing.sm),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(c.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        Text(
                          c.businessType.isEmpty ? c.id : c.businessType,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              TextStyle(fontSize: 12, color: t.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              sortValue: (c) => c.name.toLowerCase(),
              exportValue: (c) => c.name,
            ),
            GridColumn(
              id: 'type',
              label: 'Business type',
              cardRole: CardRole.subtitle,
              visibleByDefault: false,
              cell: (c) => Text(c.businessType.isEmpty ? '—' : c.businessType,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              sortValue: (c) => c.businessType.toLowerCase(),
              exportValue: (c) => c.businessType,
              filter: GridFilter.choice((c) =>
                  c.businessType.isEmpty ? 'Not set' : c.businessType),
            ),
            GridColumn(
              id: 'location',
              label: 'Location',
              flex: 2,
              cardRole: CardRole.meta,
              cell: (c) => Text(c.location.isEmpty ? '—' : c.location,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              sortValue: (c) => c.location.toLowerCase(),
              exportValue: (c) => c.location,
              filter: GridFilter.choice(
                  (c) => c.city.isEmpty ? 'Not set' : c.city),
            ),
            GridColumn(
              id: 'contact',
              label: 'Contact',
              flex: 2,
              cardRole: CardRole.meta,
              cell: (c) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(c.contactNo.isEmpty ? '—' : c.contactNo,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (c.email.isNotEmpty)
                    Text(c.email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: t.textSecondary)),
                ],
              ),
              sortValue: (c) => c.email.toLowerCase(),
              exportValue: (c) => '${c.contactNo} ${c.email}'.trim(),
            ),
            GridColumn(
              id: 'size',
              label: 'Size',
              cardRole: CardRole.meta,
              minWidth: 100,
              cell: (c) => Text(c.size.label),
              sortValue: (c) => c.size.index,
              exportValue: (c) => c.size.label,
              filter: GridFilter.choice((c) => c.size.label,
                  options: [for (final s in CompanySize.values) s.label]),
            ),
            GridColumn(
              id: 'businesses',
              label: 'Businesses',
              visibleByDefault: false,
              cardRole: CardRole.meta,
              cell: (c) => Text(
                  c.businessIds
                      .map((id) => data.businessById(id)?.name ?? id)
                      .join(', '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              exportValue: (c) => c.businessIds
                  .map((id) => data.businessById(id)?.name ?? id)
                  .join(', '),
            ),
            GridColumn(
              id: 'recurring',
              label: 'Annual recurring',
              numeric: true,
              cardRole: CardRole.metric,
              tooltip: 'Active contracts in scope, billed per year',
              cell: (c) {
                final m = _service.customerAnnualRecurring(c, bizId, now: now);
                if (!m.isPositive) {
                  return Text('—', style: TextStyle(color: t.textTertiary));
                }
                final cur = rowCurrency(c);
                return cur == null
                    ? Text('Mixed', style: TextStyle(color: t.textSecondary))
                    : CurrencyText(m, currency: cur);
              },
              sortValue: (c) =>
                  _service.customerAnnualRecurring(c, bizId, now: now).minor,
              exportValue: (c) => _service
                  .customerAnnualRecurring(c, bizId, now: now)
                  .major
                  .toStringAsFixed(2),
            ),
            GridColumn(
              id: 'renewal',
              label: 'Next renewal',
              cardRole: CardRole.meta,
              minWidth: 120,
              cell: (c) {
                final e = _service.customerNextExpiry(c, bizId);
                if (e == null) {
                  return Text('—', style: TextStyle(color: t.textTertiary));
                }
                final expired =
                    e.isBefore(DateTime(now.year, now.month, now.day));
                return Text(
                  AppDate.format(e),
                  style: TextStyle(
                      color: expired
                          ? t.error
                          : dueSoon(c)
                              ? t.warning
                              : null,
                      fontWeight: expired || dueSoon(c)
                          ? FontWeight.w600
                          : FontWeight.w400),
                );
              },
              sortValue: (c) =>
                  _service.customerNextExpiry(c, bizId)?.millisecondsSinceEpoch ??
                  9999999999999,
              exportValue: (c) {
                final e = _service.customerNextExpiry(c, bizId);
                return e == null ? '' : AppDate.format(e);
              },
              filter: GridFilter.dateRange(
                  (c) => _service.customerNextExpiry(c, bizId)),
            ),
            GridColumn(
              id: 'activity',
              label: 'Last activity',
              cardRole: CardRole.meta,
              visibleByDefault: false,
              minWidth: 120,
              cell: (c) => Text(c.lastActivityAt == null
                  ? '—'
                  : AppDate.format(c.lastActivityAt)),
              sortValue: (c) => _activityOf(c).millisecondsSinceEpoch,
              exportValue: (c) => c.lastActivityAt == null
                  ? ''
                  : AppDate.format(c.lastActivityAt),
              filter: GridFilter.dateRange(_activityOf),
            ),
            GridColumn(
              id: 'status',
              label: 'Deal status',
              cardRole: CardRole.badge,
              minWidth: 120,
              cell: (c) => StatusBadge.deal(c.dealStatus),
              sortValue: (c) => c.dealStatus.index,
              exportValue: (c) => c.dealStatus.label,
              filter: GridFilter.choice((c) => c.dealStatus.label,
                  options: [for (final s in DealStatus.values) s.label]),
            ),
            GridColumn(
              id: 'actions',
              label: '',
              pinned: true,
              cardRole: CardRole.actions,
              // View, Invoice, Edit, More and Delete (48 px each) plus the
              // cell padding.
              minWidth: 2 * AppSpacing.md +
                  48 * [true, true, canEdit, canCreate, canDelete]
                      .where((b) => b)
                      .length,
              cell: (c) => _RowActions(
                customer: c,
                businessId: bizId,
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

  static Future<void> _bulkStatus(BuildContext context, Repository repo,
      List<Customer> rows, DealStatus status) async {
    await runGridBulk<Customer>(
      context,
      rows: rows,
      verb: 'Updating',
      noun: 'customers',
      describe: (c) => c.name,
      task: (c) => repo.saveCustomer(c.copyWith(dealStatus: status),
          isNew: false),
    );
  }

  static Future<void> _bulkDelete(
      BuildContext context, Repository repo, List<Customer> rows) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Delete ${rows.length == 1 ? '1 customer' : '${rows.length} customers'}?',
      message: 'This removes them for everyone and cannot be easily undone.',
    );
    if (!ok || !context.mounted) return;
    await runGridBulk<Customer>(
      context,
      rows: rows,
      verb: 'Deleting',
      noun: 'customers',
      describe: (c) => c.name,
      task: (c) => repo.deleteCustomer(c.id, known: c),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) => const AppPage(
        children: [
          PageHeader(title: 'Customers', icon: Icons.people_outline),
          SizedBox(height: AppSpacing.lg),
          SkeletonCard(lines: 1, height: 88),
          SizedBox(height: AppSpacing.lg),
          SkeletonCard(lines: 8),
        ],
      );
}

class _RowActions extends StatelessWidget {
  const _RowActions({
    required this.customer,
    required this.businessId,
    required this.canCreate,
    required this.canEdit,
    required this.canDelete,
  });

  final Customer customer;

  /// The selected business (null == All Businesses). Scopes which contract the
  /// invoice action bills: a specific business only offers the invoice when that
  /// business has a contract; "All Businesses" offers it whenever any exists.
  final String? businessId;
  final bool canCreate;
  final bool canEdit;
  final bool canDelete;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'View',
          icon: const Icon(Icons.open_in_new, size: 18),
          onPressed: () =>
              context.go(Routes.customerDetailPath(customer.id)),
        ),
        if (CustomerActions.canInvoice(customer, businessId))
          IconButton(
            tooltip: 'Generate invoice',
            icon: const Icon(Icons.receipt_long_outlined, size: 18),
            onPressed: () => generateCustomerInvoice(context, customer,
                businessId: businessId),
          ),
        if (canEdit)
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined, size: 18),
            onPressed: () => CustomersScreen.openForm(context, customer, null),
          ),
        if (canCreate)
          IconButton(
            tooltip: 'Duplicate',
            icon: const Icon(Icons.copy_all_outlined, size: 18),
            onPressed: () => CustomerActions.duplicate(context, customer),
          ),
        if (canDelete)
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: () => CustomerActions.delete(context, customer),
          ),
      ],
    );
  }
}

/// The single-customer actions, shared by the list rows and the detail page.
class CustomerActions {
  CustomerActions._();

  /// Whether an invoice can be generated for the current scope: a specific
  /// business needs a contract of its own; "All Businesses" (null) needs any.
  static bool canInvoice(Customer customer, String? businessId) =>
      businessId == null
          ? customer.hasServiceContract
          : customer.hasContractFor(businessId);

  /// Opens the add form prefilled from [customer].
  static Future<void> duplicate(BuildContext context, Customer customer) =>
      CustomersScreen.openForm(
          context, null, customer.businessIds.firstOrNull,
          duplicateOf: customer);

  /// Confirms, then deletes. Returns true when the customer was deleted.
  static Future<bool> delete(BuildContext context, Customer customer) async {
    final repo = context.read<AppState>().repository;
    final ok = await showConfirmDialog(
      context,
      title: 'Delete customer?',
      message:
          'Delete "${customer.name}"? This action cannot be easily undone.',
    );
    if (ok != true) return false;
    try {
      await repo.deleteCustomer(customer.id, known: customer);
      if (context.mounted) showSuccessSnack(context, 'Customer deleted');
      return true;
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e);
      return false;
    }
  }
}

/// Public create/edit form, reused from the customer detail screen. Three
/// sections: Details, Businesses and Contact.
class CustomerFormDialog extends StatefulWidget {
  const CustomerFormDialog({
    super.key,
    required this.existing,
    required this.repo,
    required this.businesses,
    this.preselectBusinessIds = const [],
    this.template,
  });

  final Customer? existing;

  /// A customer to prefill a new one from (Duplicate).
  final Customer? template;
  final Repository repo;
  final List<Business> businesses;
  final List<String> preselectBusinessIds;

  @override
  State<CustomerFormDialog> createState() => _CustomerFormDialogState();
}

class _CustomerFormDialogState extends State<CustomerFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _businessType;
  late final TextEditingController _contactNo;
  late final TextEditingController _email;
  late final TextEditingController _city;
  late final TextEditingController _state;
  late final TextEditingController _country;
  late final TextEditingController _socialMedia;
  late final TextEditingController _description;
  late CompanySize _size;
  late DealStatus _dealStatus;

  /// Ids of businesses this customer is tagged to (multi-select).
  final Set<String> _businessIds = {};

  Customer? get _existing => widget.existing;

  @override
  void initState() {
    super.initState();
    final c = _existing ?? widget.template;
    _name = TextEditingController(
        text: c == null
            ? ''
            : widget.template != null && _existing == null
                ? '${c.name} (copy)'
                : c.name);
    _businessType = TextEditingController(text: c?.businessType ?? '');
    _contactNo = TextEditingController(text: c?.contactNo ?? '');
    _email = TextEditingController(text: c?.email ?? '');
    _city = TextEditingController(text: c?.city ?? '');
    _state = TextEditingController(text: c?.state ?? '');
    _country = TextEditingController(text: c?.country ?? 'India');
    _socialMedia = TextEditingController(text: c?.socialMedia ?? '');
    _description = TextEditingController(text: c?.description ?? '');
    _size = c?.size ?? CompanySize.small;
    // A duplicate starts a fresh pipeline entry.
    _dealStatus = _existing?.dealStatus ?? DealStatus.pending;
    // Seed the selection from the existing customer (only tags visible in this
    // scope are shown/editable; hidden tags are preserved server-side on save),
    // else from any preselected businesses (e.g. the current business filter).
    final selectable = widget.businesses.map((b) => b.id).toSet();
    if (c != null) {
      _businessIds.addAll(c.businessIds.where(selectable.contains));
    } else {      _businessIds.addAll(widget.preselectBusinessIds.where(selectable.contains));
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _businessType.dispose();
    _contactNo.dispose();
    _email.dispose();
    _city.dispose();
    _state.dispose();
    _country.dispose();
    _socialMedia.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isNew = _existing == null;
    return FormDialog(
      title: isNew
          ? (widget.template == null ? 'Add Customer' : 'Duplicate Customer')
          : 'Edit Customer',
      icon: Icons.people_outline,
      draftKey: isNew && widget.template == null ? 'customer.new' : null,
      onSubmit: _submit,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FormSection(
              title: 'Details',
              icon: Icons.badge_outlined,
              first: true,
              children: [
                AppTextField(
                  label: 'Customer Name',
                  controller: _name,
                  isRequired: true,
                  validator: (v) =>
                      Validators.required(v, field: 'Customer name'),
                ),
                const FormGap(),
                FormRow([
                  AppTextField(
                    label: 'Business Type',
                    controller: _businessType,
                    hintText: 'e.g. Retail, SaaS, Manufacturing',
                  ),
                  AppDropdown<CompanySize>(
                    label: 'Size',
                    value: _size,
                    items: CompanySize.values,
                    itemLabel: (s) => s.label,
                    onChanged: (v) => setState(() => _size = v ?? _size),
                  ),
                ]),
                const FormGap(),
                AppDropdown<DealStatus>(
                  label: 'Deal Status',
                  value: _dealStatus,
                  items: DealStatus.values,
                  itemLabel: (s) => s.label,
                  onChanged: (v) =>
                      setState(() => _dealStatus = v ?? _dealStatus),
                ),
                const FormGap(),
                AppTextField(
                  label: 'Description',
                  controller: _description,
                  maxLines: 3,
                ),
              ],
            ),
            FormSection(
              title: 'Businesses',
              icon: Icons.business_outlined,
              description: 'Which of your businesses this customer buys from.',
              children: [
                LabeledField(
                  label: 'Businesses',
                  isRequired: true,
                  helper: 'Tag this customer to one or more businesses.',
                  child: _BusinessMultiSelect(
                    businesses: widget.businesses,
                    selected: _businessIds,
                    onToggle: (id, sel) => setState(() {
                      if (sel) {
                        _businessIds.add(id);
                      } else {
                        _businessIds.remove(id);
                      }
                    }),
                  ),
                ),
              ],
            ),
            FormSection(
              title: 'Contact',
              icon: Icons.contact_phone_outlined,
              children: [
                FormRow([
                  AppTextField(
                    label: 'Contact No',
                    controller: _contactNo,
                    keyboardType: TextInputType.phone,
                  ),
                  AppTextField(
                    label: 'Email',
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? null
                        : Validators.email(v),
                  ),
                ]),
                const FormGap(),
                FormRow([
                  AppTextField(label: 'City', controller: _city),
                  AppTextField(label: 'State', controller: _state),
                ]),
                const FormGap(),
                FormRow([
                  AppTextField(label: 'Country', controller: _country),
                  AppTextField(
                    label: 'Social Media',
                    controller: _socialMedia,
                    hintText: 'Profile or handle',
                  ),
                ]),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return false;
    if (_businessIds.isEmpty) {
      showErrorSnack(context, 'Select at least one business for this customer.');
      return false;
    }
    final isNew = _existing == null;
    final customer = (_existing ??
            Customer(id: '', businessIds: const [], name: _name.text.trim()))
        .copyWith(
      businessIds: _businessIds.toList(),
      name: _name.text.trim(),
      businessType: _businessType.text.trim(),
      size: _size,
      contactNo: _contactNo.text.trim(),
      email: _email.text.trim(),
      city: _city.text.trim(),
      state: _state.text.trim(),
      country: _country.text.trim(),
      socialMedia: _socialMedia.text.trim(),
      dealStatus: _dealStatus,
      description: _description.text.trim(),
    );
    try {
      await widget.repo.saveCustomer(customer, isNew: isNew);
      return true;
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
      return false;
    }
  }
}

/// A searchable, multi-checkbox picker of onboarded businesses. Only businesses
/// the caller can access are passed in, so selecting is inherently scoped to the
/// user's assignments (Owner sees all; Admin/User see only assigned ones).
class _BusinessMultiSelect extends StatefulWidget {
  const _BusinessMultiSelect({
    required this.businesses,
    required this.selected,
    required this.onToggle,
  });

  final List<Business> businesses;
  final Set<String> selected;
  final void Function(String id, bool selected) onToggle;

  @override
  State<_BusinessMultiSelect> createState() => _BusinessMultiSelectState();
}

class _BusinessMultiSelectState extends State<_BusinessMultiSelect> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    if (widget.businesses.isEmpty) {
      return Text('No businesses available.',
          style: TextStyle(fontSize: 12, color: context.tokens.textTertiary));
    }
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? widget.businesses
        : widget.businesses
            .where((b) => b.name.toLowerCase().contains(q) ||
                b.id.toLowerCase().contains(q))
            .toList();

    return Container(
      decoration: BoxDecoration(
        color: context.tokens.card,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: context.tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search, size: 18),
                hintText: 'Search businesses…',
              ),
            ),
          ),
          const Divider(height: 1),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 196),
            child: filtered.isEmpty
                ? Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                    child: Text('No matching businesses.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 12, color: context.tokens.textTertiary)),
                  )
                : ListView(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    children: [
                      for (final b in filtered)
                        CheckboxListTile(
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                          value: widget.selected.contains(b.id),
                          onChanged: (v) => widget.onToggle(b.id, v ?? false),
                          title: Text(b.name,
                              style: const TextStyle(fontSize: 14)),
                          subtitle: Text(b.id,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: context.tokens.textTertiary)),
                        ),
                    ],
                  ),
          ),
          if (widget.selected.isNotEmpty) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md, vertical: AppSpacing.sm),
              child: Text(
                '${widget.selected.length} '
                '${widget.selected.length == 1 ? 'business' : 'businesses'} '
                'selected',
                style: TextStyle(
                    fontSize: 12, color: context.tokens.textSecondary),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
