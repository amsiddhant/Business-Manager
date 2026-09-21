import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/enums.dart';
import '../../core/permissions.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/validators.dart';
import '../../data/repository.dart';
import '../../models/business.dart';
import '../../models/customer.dart';
import '../../state/app_state.dart';
import '../../state/data_controller.dart';
import '../../state/filter_controller.dart';
import '../../widgets/common/confirm_dialog.dart';
import '../../widgets/common/data_table_card.dart';
import '../../widgets/common/initials_avatar.dart';
import '../../widgets/common/page_header.dart';
import '../../widgets/common/responsive.dart';
import '../../widgets/common/search_field.dart';
import '../../widgets/common/state_views.dart';
import '../../widgets/common/status_badge.dart';
import '../../widgets/forms/form_dialog.dart';
import '../../widgets/forms/form_fields.dart';

/// Lists customers (CRM contacts) for the selected scope with a live search
/// bar, deal-status filter and permission-gated create / edit / delete.
class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  String _search = '';
  DealStatus? _dealFilter;

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
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PageHeader(title: 'Customers'),
          const SizedBox(height: 48),
          ErrorView(message: data.error!, onRetry: () => data.refresh()),
        ],
      );
    }

    final bizId = filter.selectedBusinessId;
    final canCreate = user?.can(Permission.createCustomer) ?? false;
    final canEdit = user?.can(Permission.editCustomer) ?? false;
    final canDelete = user?.can(Permission.deleteCustomer) ?? false;

    var customers = [...data.customersFor(bizId)]
      ..sort((a, b) => _activityOf(b).compareTo(_activityOf(a)));
    if (_dealFilter != null) {
      customers =
          customers.where((c) => c.dealStatus == _dealFilter).toList();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: 'Customers',
          subtitle: 'Manage leads, contacts and deal pipeline',
          actions: [
            if (canCreate)
              ElevatedButton.icon(
                onPressed: () => _openForm(context, null, bizId),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Customer'),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        _FilterBar(
          onSearch: (v) => setState(() => _search = v),
          dealFilter: _dealFilter,
          onDealFilter: (v) => setState(() => _dealFilter = v),
        ),
        const SizedBox(height: AppSpacing.md),
        AppDataTable<Customer>(
          rows: customers,
          searchText: _search,
          searchableText: (c) => '${c.id} ${c.name} ${c.businessType} '
              '${c.email} ${c.contactNo} ${c.location} ${c.dealStatus.label}',
          onRowTap: (c) => context.go(Routes.customerDetailPath(c.id)),
          emptyTitle: 'No customers found',
          emptyMessage: canCreate
              ? 'Add your first customer to start tracking your pipeline.'
              : 'Customers will appear here once added.',
          emptyAction: canCreate
              ? ElevatedButton.icon(
                  onPressed: () => _openForm(context, null, bizId),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Customer'),
                )
              : null,
          columns: [
            AppColumn(
              label: 'Customer',
              cell: (c) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InitialsAvatar(name: c.name, size: 36),
                  const SizedBox(width: AppSpacing.sm),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(c.name,
                          style:
                              const TextStyle(fontWeight: FontWeight.w600)),
                      Text(
                        c.businessType.isEmpty ? c.id : c.businessType,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ],
              ),
              sortValue: (c) => c.name.toLowerCase(),
            ),
            AppColumn(
              label: 'Location',
              cell: (c) =>
                  Text(c.location.isEmpty ? '—' : c.location),
              sortValue: (c) => c.location.toLowerCase(),
            ),
            AppColumn(
              label: 'Contact',
              cell: (c) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(c.contactNo.isEmpty ? '—' : c.contactNo),
                  if (c.email.isNotEmpty)
                    Text(c.email,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
              sortValue: (c) => c.email.toLowerCase(),
            ),
            AppColumn(
              label: 'Size',
              cell: (c) => Text(c.size.label),
              sortValue: (c) => c.size.index,
            ),
            AppColumn(
              label: 'Deal Status',
              cell: (c) => StatusBadge.deal(c.dealStatus),
              sortValue: (c) => c.dealStatus.index,
            ),
            AppColumn(
              label: '',
              cell: (c) => _RowActions(
                customer: c,
                canEdit: canEdit,
                canDelete: canDelete,
              ),
            ),
          ],
        ),
      ],
    );
  }

  static Future<void> _openForm(
      BuildContext context, Customer? existing, String? selectedBizId) async {
    final data = context.read<DataController>();
    final repo = context.read<AppState>().repository;
    final businesses = data.selectableBusinesses;
    if (existing == null && businesses.isEmpty) {
      showErrorSnack(context, 'Create a business before adding customers.');
      return;
    }
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => CustomerFormDialog(
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
                ? 'Customer created successfully'
                : 'Customer updated successfully');
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
          PageHeader(title: 'Customers'),
          SizedBox(height: 48),
          LoadingView(),
        ],
      );
}

/// The live search + deal-status filter row above the customers table.
class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.onSearch,
    required this.dealFilter,
    required this.onDealFilter,
  });

  final ValueChanged<String> onSearch;
  final DealStatus? dealFilter;
  final ValueChanged<DealStatus?> onDealFilter;

  @override
  Widget build(BuildContext context) {
    final search = SearchField(
      hintText: 'Search customers by name, email, phone or location…',
      onChanged: onSearch,
    );
    final statusFilter = _DealStatusFilter(
      value: dealFilter,
      onChanged: onDealFilter,
    );
    if (Responsive.isMobile(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          search,
          const SizedBox(height: AppSpacing.sm),
          statusFilter,
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: search),
        const SizedBox(width: AppSpacing.md),
        statusFilter,
      ],
    );
  }
}

/// A compact "All statuses" + deal-status dropdown used to filter the table.
class _DealStatusFilter extends StatelessWidget {
  const _DealStatusFilter({required this.value, required this.onChanged});

  final DealStatus? value;
  final ValueChanged<DealStatus?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<DealStatus?>(
          value: value,
          icon: const Icon(Icons.filter_list, size: 18),
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          items: [
            const DropdownMenuItem<DealStatus?>(
              value: null,
              child: Text('All statuses'),
            ),
            for (final s in DealStatus.values)
              DropdownMenuItem<DealStatus?>(value: s, child: Text(s.label)),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _RowActions extends StatelessWidget {
  const _RowActions({
    required this.customer,
    required this.canEdit,
    required this.canDelete,
  });

  final Customer customer;
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
        if (canEdit)
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined, size: 18),
            onPressed: () => _CustomersScreenState._openForm(
                context, customer, customer.businessId),
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
      title: 'Delete customer?',
      message:
          'Delete "${customer.name}"? This action cannot be easily undone.',
    );
    if (ok != true) return;
    try {
      await repo.deleteCustomer(customer.id);
      await data.refresh();
      if (context.mounted) showSuccessSnack(context, 'Customer deleted');
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e);
    }
  }
}

/// Public create/edit form, reused from the customer detail screen.
class CustomerFormDialog extends StatefulWidget {
  const CustomerFormDialog({
    super.key,
    required this.existing,
    required this.repo,
    required this.businesses,
    this.preselectBusinessId,
  });

  final Customer? existing;
  final Repository repo;
  final List<Business> businesses;
  final String? preselectBusinessId;

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
  String? _businessId;

  Customer? get _existing => widget.existing;

  @override
  void initState() {
    super.initState();
    final c = _existing;
    _name = TextEditingController(text: c?.name ?? '');
    _businessType = TextEditingController(text: c?.businessType ?? '');
    _contactNo = TextEditingController(text: c?.contactNo ?? '');
    _email = TextEditingController(text: c?.email ?? '');
    _city = TextEditingController(text: c?.city ?? '');
    _state = TextEditingController(text: c?.state ?? '');
    _country = TextEditingController(text: c?.country ?? 'India');
    _socialMedia = TextEditingController(text: c?.socialMedia ?? '');
    _description = TextEditingController(text: c?.description ?? '');
    _size = c?.size ?? CompanySize.small;
    _dealStatus = c?.dealStatus ?? DealStatus.pending;
    _businessId = c?.businessId ??
        widget.preselectBusinessId ??
        (widget.businesses.isNotEmpty ? widget.businesses.first.id : null);
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
      title: isNew ? 'Add Customer' : 'Edit Customer',
      onSubmit: _submit,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isNew && widget.businesses.length > 1) ...[
              AppDropdown<String>(
                label: 'Business',
                isRequired: true,
                value: _businessId,
                items: [for (final b in widget.businesses) b.id],
                itemLabel: (id) =>
                    widget.businesses.firstWhere((b) => b.id == id).name,
                onChanged: (v) => setState(() => _businessId = v),
              ),
              const FormGap(),
            ],
            AppTextField(
              label: 'Customer Name',
              controller: _name,
              isRequired: true,
              validator: (v) => Validators.required(v, field: 'Customer name'),
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
            const FormGap(),
            AppDropdown<DealStatus>(
              label: 'Deal Status',
              value: _dealStatus,
              items: DealStatus.values,
              itemLabel: (s) => s.label,
              onChanged: (v) => setState(() => _dealStatus = v ?? _dealStatus),
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
    final bizId = _businessId;
    if (bizId == null) {
      showErrorSnack(context, 'Select a business for this customer.');
      return false;
    }
    final isNew = _existing == null;
    final customer = (_existing ??
            Customer(id: '', businessId: bizId, name: _name.text.trim()))
        .copyWith(
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
