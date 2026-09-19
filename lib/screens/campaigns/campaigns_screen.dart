import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/enums.dart';
import '../../core/permissions.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../core/validators.dart';
import '../../data/repository.dart';
import '../../models/business.dart';
import '../../models/campaign.dart';
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

/// Lists marketing campaigns for the selected scope, with full CRUD gated by
/// permission.
class CampaignsScreen extends StatelessWidget {
  const CampaignsScreen({super.key});

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
          const PageHeader(title: 'Campaigns'),
          const SizedBox(height: 48),
          ErrorView(message: data.error!, onRetry: () => data.refresh()),
        ],
      );
    }

    final bizId = filter.selectedBusinessId;
    final campaigns = data.campaignsFor(bizId);
    final canCreate = user?.can(Permission.createCampaign) ?? false;
    final canEdit = user?.can(Permission.editCampaign) ?? false;
    final canDelete = user?.can(Permission.deleteCampaign) ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: 'Campaigns',
          subtitle: 'Track advertising spend and performance',
          actions: [
            if (canCreate)
              ElevatedButton.icon(
                onPressed: () => _openForm(context, null, bizId),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Campaign'),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        AppDataTable<Campaign>(
          rows: campaigns,
          searchableText: (c) => '${c.id} ${c.name} ${c.platform.label}',
          emptyTitle: 'No campaigns found',
          emptyMessage: canCreate
              ? 'Create your first campaign to start tracking marketing spend.'
              : 'Campaigns will appear here once added.',
          emptyAction: canCreate
              ? ElevatedButton.icon(
                  onPressed: () => _openForm(context, null, bizId),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Campaign'),
                )
              : null,
          columns: [
            AppColumn(
              label: 'Campaign',
              cell: (c) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(c.name,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(_productName(data, c.productId),
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF6B7280))),
                ],
              ),
              sortValue: (c) => c.name.toLowerCase(),
            ),
            AppColumn(
              label: 'Platform',
              cell: (c) =>
                  StatusBadge(label: c.platform.label, tone: BadgeTone.info),
              sortValue: (c) => c.platform.label,
            ),
            AppColumn(
              label: 'Spend',
              numeric: true,
              cell: (c) => CurrencyText(c.amountInvested,
                  currency: _currencyFor(data, c.businessId)),
              sortValue: (c) => c.amountInvested.minor,
            ),
            AppColumn(
              label: 'Clicks',
              numeric: true,
              cell: (c) => Text('${c.clicks}'),
              sortValue: (c) => c.clicks,
            ),
            AppColumn(
              label: 'Conv.',
              numeric: true,
              cell: (c) => Text('${c.conversions}'),
              sortValue: (c) => c.conversions,
            ),
            AppColumn(
              label: 'Status',
              cell: (c) => StatusBadge.campaign(c.status),
              sortValue: (c) => c.status.label,
            ),
            AppColumn(
              label: '',
              cell: (c) => _RowActions(
                campaign: c,
                canEdit: canEdit,
                canDelete: canDelete,
              ),
            ),
          ],
        ),
      ],
    );
  }

  static String _productName(DataController data, String productId) =>
      data.productById(productId)?.name ?? '—';

  static CurrencyCode _currencyFor(DataController data, String businessId) =>
      data.businessById(businessId)?.currency ?? CurrencyCode.inr;

  static Future<void> _openForm(
      BuildContext context, Campaign? existing, String? selectedBizId) async {
    final data = context.read<DataController>();
    final repo = context.read<AppState>().repository;
    final businesses = data.selectableBusinesses;
    if (existing == null && data.products.isEmpty) {
      showErrorSnack(context, 'Create a product before adding campaigns.');
      return;
    }
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _CampaignFormDialog(
        existing: existing,
        repo: repo,
        businesses: businesses,
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
                ? 'Campaign created successfully'
                : 'Campaign updated successfully');
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
          PageHeader(title: 'Campaigns'),
          SizedBox(height: 48),
          LoadingView(),
        ],
      );
}

class _RowActions extends StatelessWidget {
  const _RowActions({
    required this.campaign,
    required this.canEdit,
    required this.canDelete,
  });

  final Campaign campaign;
  final bool canEdit;
  final bool canDelete;

  @override
  Widget build(BuildContext context) {
    if (!canEdit && !canDelete) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (canEdit)
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined, size: 18),
            onPressed: () => CampaignsScreen._openForm(
                context, campaign, campaign.businessId),
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
      title: 'Delete campaign?',
      message:
          'Delete "${campaign.name}"? This action cannot be easily undone.',
    );
    if (ok != true) return;
    try {
      await repo.deleteCampaign(campaign.id);
      await data.refresh();
      if (context.mounted) showSuccessSnack(context, 'Campaign deleted');
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e);
    }
  }
}

class _CampaignFormDialog extends StatefulWidget {
  const _CampaignFormDialog({
    required this.existing,
    required this.repo,
    required this.businesses,
    required this.allProducts,
    this.preselectBusinessId,
  });

  final Campaign? existing;
  final Repository repo;
  final List<Business> businesses;
  final List<Product> allProducts;
  final String? preselectBusinessId;

  @override
  State<_CampaignFormDialog> createState() => _CampaignFormDialogState();
}

class _CampaignFormDialogState extends State<_CampaignFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _type;
  late final TextEditingController _budget;
  late final TextEditingController _invested;
  late final TextEditingController _impressions;
  late final TextEditingController _clicks;
  late final TextEditingController _conversions;
  late final TextEditingController _url;
  late final TextEditingController _notes;
  late CampaignPlatform _platform;
  late CampaignStatus _status;
  DateTime? _startDate;
  DateTime? _endDate;
  String? _productId;

  Campaign? get _existing => widget.existing;

  @override
  void initState() {
    super.initState();
    final c = _existing;
    _name = TextEditingController(text: c?.name ?? '');
    _type = TextEditingController(text: c?.type ?? '');
    _budget = TextEditingController(
        text: c == null || c.budget.isZero ? '' : c.budget.major.toString());
    _invested = TextEditingController(
        text: c == null || c.amountInvested.isZero
            ? ''
            : c.amountInvested.major.toString());
    _impressions =
        TextEditingController(text: c == null ? '' : '${c.impressions}');
    _clicks = TextEditingController(text: c == null ? '' : '${c.clicks}');
    _conversions =
        TextEditingController(text: c == null ? '' : '${c.conversions}');
    _url = TextEditingController(text: c?.url ?? '');
    _notes = TextEditingController(text: c?.notes ?? '');
    _platform = c?.platform ?? CampaignPlatform.meta;
    _status = c?.status ?? CampaignStatus.draft;
    _startDate = c?.startDate;
    _endDate = c?.endDate;
    _productId = c?.productId ?? _initialProductId();
  }

  String? _initialProductId() {
    final scoped = _scopedProducts(widget.preselectBusinessId);
    return scoped.isNotEmpty ? scoped.first.id : null;
  }

  List<Product> _scopedProducts(String? bizId) {
    final list = bizId == null
        ? widget.allProducts
        : widget.allProducts.where((p) => p.businessId == bizId).toList();
    return list;
  }

  @override
  void dispose() {
    _name.dispose();
    _type.dispose();
    _budget.dispose();
    _invested.dispose();
    _impressions.dispose();
    _clicks.dispose();
    _conversions.dispose();
    _url.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isNew = _existing == null;
    // Products selectable in this dialog: for a new campaign, scope by the
    // product's business follows the chosen product itself.
    final products = widget.allProducts;
    return FormDialog(
      title: isNew ? 'Add Campaign' : 'Edit Campaign',
      onSubmit: _submit,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppTextField(
              label: 'Campaign Name',
              controller: _name,
              isRequired: true,
              validator: (v) => Validators.required(v, field: 'Campaign name'),
            ),
            const FormGap(),
            AppDropdown<String>(
              label: 'Product',
              isRequired: true,
              value: _productId,
              items: [for (final p in products) p.id],
              itemLabel: (id) => _labelForProduct(products, id),
              onChanged: (v) => setState(() => _productId = v),
            ),
            const FormGap(),
            FormRow([
              AppDropdown<CampaignPlatform>(
                label: 'Platform',
                value: _platform,
                items: CampaignPlatform.values,
                itemLabel: (p) => p.label,
                onChanged: (v) => setState(() => _platform = v ?? _platform),
              ),
              AppDropdown<CampaignStatus>(
                label: 'Status',
                value: _status,
                items: CampaignStatus.values,
                itemLabel: (s) => s.label,
                onChanged: (v) => setState(() => _status = v ?? _status),
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
                onChanged: (v) => setState(() => _endDate = v),
              ),
            ]),
            const FormGap(),
            FormRow([
              AppMoneyField(
                label: 'Budget',
                controller: _budget,
                validator: (v) => Validators.optionalNonNegativeNumber(v),
              ),
              AppMoneyField(
                label: 'Amount Invested',
                controller: _invested,
                validator: (v) => Validators.optionalNonNegativeNumber(v),
              ),
            ]),
            const FormGap(),
            FormRow([
              AppTextField(
                label: 'Impressions',
                controller: _impressions,
                keyboardType: TextInputType.number,
                validator: (v) => Validators.optionalNonNegativeNumber(v),
              ),
              AppTextField(
                label: 'Clicks',
                controller: _clicks,
                keyboardType: TextInputType.number,
                validator: (v) => Validators.optionalNonNegativeNumber(v),
              ),
              AppTextField(
                label: 'Conversions',
                controller: _conversions,
                keyboardType: TextInputType.number,
                validator: (v) => Validators.optionalNonNegativeNumber(v),
              ),
            ]),
            const FormGap(),
            AppTextField(
              label: 'Campaign URL',
              controller: _url,
              hintText: 'https://…',
              validator: (v) => Validators.url(v),
            ),
            const FormGap(),
            AppTextField(label: 'Notes', controller: _notes, maxLines: 2),
          ],
        ),
      ),
    );
  }

  String _labelForProduct(List<Product> products, String id) {
    final product = products.firstWhere((p) => p.id == id);
    final biz = widget.businesses.where((b) => b.id == product.businessId);
    final suffix = biz.isNotEmpty && widget.businesses.length > 1
        ? ' · ${biz.first.name}'
        : '';
    return '${product.name}$suffix';
  }

  int _parseInt(String raw) => int.tryParse(raw.trim()) ?? 0;

  Future<bool> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return false;
    final productId = _productId;
    if (productId == null) {
      showErrorSnack(context, 'Select a product for this campaign.');
      return false;
    }
    final product =
        widget.allProducts.firstWhere((p) => p.id == productId);
    final isNew = _existing == null;
    final campaign = (_existing ??
            Campaign(
              id: '',
              businessId: product.businessId,
              productId: productId,
              name: _name.text.trim(),
            ))
        .copyWith(
      productId: productId,
      name: _name.text.trim(),
      platform: _platform,
      type: _type.text.trim(),
      startDate: _startDate,
      endDate: _endDate,
      budget: Money.parse(_budget.text),
      amountInvested: Money.parse(_invested.text),
      impressions: _parseInt(_impressions.text),
      clicks: _parseInt(_clicks.text),
      conversions: _parseInt(_conversions.text),
      status: _status,
      url: _url.text.trim(),
      notes: _notes.text.trim(),
    );
    try {
      await widget.repo.saveCampaign(campaign, isNew: isNew);
      return true;
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
      return false;
    }
  }
}
