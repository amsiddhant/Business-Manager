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
import '../../models/product.dart';
import '../../state/app_state.dart';
import '../../state/data_controller.dart';
import '../../state/filter_controller.dart';
import '../../widgets/common/confirm_dialog.dart';
import '../../widgets/common/csv_actions.dart';
import '../../widgets/common/currency_display.dart';
import '../../widgets/common/data_table_card.dart';
import '../../widgets/common/page_header.dart';
import '../../widgets/common/search_field.dart';
import '../../widgets/common/state_views.dart';
import '../../widgets/common/status_badge.dart';
import '../../widgets/forms/form_dialog.dart';
import '../../widgets/forms/form_fields.dart';

/// Lists products for the selected business (or all accessible businesses),
/// with create / edit / delete gated by permission.
class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
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
          const PageHeader(title: 'Products'),
          const SizedBox(height: 48),
          ErrorView(message: data.error!, onRetry: () => data.refresh()),
        ],
      );
    }

    final bizId = filter.selectedBusinessId;
    final products = data.productsFor(bizId);
    final canCreate = user?.can(Permission.createProduct) ?? false;
    final canExport = user?.can(Permission.exportData) ?? false;
    final canEdit = user?.can(Permission.editProduct) ?? false;
    final canDelete = user?.can(Permission.deleteProduct) ?? false;
    final needsBusiness = bizId == null && data.selectableBusinesses.length > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: 'Products',
          subtitle: 'Track catalogue, pricing and profitability',
          actions: [
            if (canExport)
              OutlinedButton.icon(
                onPressed: products.isEmpty
                    ? null
                    : () => exportProductsCsv(context, products),
                icon: const Icon(Icons.file_download_outlined, size: 18),
                label: const Text('Export CSV'),
              ),
            if (canCreate)
              OutlinedButton.icon(
                onPressed: () => importProductsCsv(context),
                icon: const Icon(Icons.file_upload_outlined, size: 18),
                label: const Text('Import CSV'),
              ),
            if (canCreate)
              ElevatedButton.icon(
                onPressed: () => _openForm(context, null, bizId),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Product'),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        SearchField(
          hintText: 'Search products by ID, name, SKU or category…',
          onChanged: (v) => setState(() => _search = v),
        ),
        const SizedBox(height: AppSpacing.md),
        AppDataTable<Product>(
          rows: products,
          searchText: _search,
          searchableText: (p) =>
              '${p.id} ${p.name} ${p.sku} ${p.category} ${p.status.label}',
          onRowTap: (p) => context.go(Routes.productDetailPath(p.id)),
          emptyTitle: 'No products found',
          emptyMessage: canCreate
              ? 'Create your first product to start tracking profitability.'
              : 'Products will appear here once added.',
          emptyAction: canCreate
              ? ElevatedButton.icon(
                  onPressed: () => _openForm(context, null, bizId),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Product'),
                )
              : null,
          columns: [
            AppColumn(
              label: 'Product ID',
              cell: (p) => Text(p.id,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              sortValue: (p) => p.id,
            ),
            AppColumn(
              label: 'Name',
              cell: (p) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(p.name,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (p.category.isNotEmpty)
                    Text(p.category,
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF6B7280))),
                ],
              ),
              sortValue: (p) => p.name.toLowerCase(),
            ),
            AppColumn(
              label: 'SKU',
              cell: (p) => Text(p.sku.isEmpty ? '—' : p.sku),
              sortValue: (p) => p.sku,
            ),
            AppColumn(
              label: 'Buying',
              numeric: true,
              cell: (p) => CurrencyText(p.buyingPrice,
                  currency: _currencyFor(data, p.businessId)),
              sortValue: (p) => p.buyingPrice.minor,
            ),
            AppColumn(
              label: 'Selling',
              numeric: true,
              cell: (p) => CurrencyText(p.sellingPrice,
                  currency: _currencyFor(data, p.businessId)),
              sortValue: (p) => p.sellingPrice.minor,
            ),
            AppColumn(
              label: 'Status',
              cell: (p) => StatusBadge.entity(p.status),
              sortValue: (p) => p.status.label,
            ),
            AppColumn(
              label: '',
              cell: (p) => _RowActions(
                product: p,
                canEdit: canEdit,
                canDelete: canDelete,
              ),
            ),
          ],
        ),
        if (needsBusiness) ...[
          const SizedBox(height: AppSpacing.md),
          const Text(
            'Tip: select a single business from the top bar to set which '
            'business new products are created in.',
            style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
          ),
        ],
      ],
    );
  }

  static CurrencyCode _currencyFor(DataController data, String businessId) =>
      data.businessById(businessId)?.currency ?? CurrencyCode.inr;

  static Future<void> _openForm(
      BuildContext context, Product? existing, String? selectedBizId) async {
    final data = context.read<DataController>();
    final repo = context.read<AppState>().repository;
    final businesses = data.selectableBusinesses;
    if (existing == null && businesses.isEmpty) {
      showErrorSnack(context, 'Create a business before adding products.');
      return;
    }
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _ProductFormDialog(
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
                ? 'Product created successfully'
                : 'Product updated successfully');
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
          PageHeader(title: 'Products'),
          SizedBox(height: 48),
          LoadingView(),
        ],
      );
}

class _RowActions extends StatelessWidget {
  const _RowActions({
    required this.product,
    required this.canEdit,
    required this.canDelete,
  });

  final Product product;
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
              context.go(Routes.productDetailPath(product.id)),
        ),
        if (canEdit)
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined, size: 18),
            onPressed: () => _ProductsScreenState._openForm(
                context, product, product.businessId),
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
      title: 'Delete product?',
      message: 'Delete "${product.name}"? This action cannot be easily undone.',
    );
    if (ok != true) return;
    try {
      await repo.deleteProduct(product.id);
      await data.refresh();
      if (context.mounted) showSuccessSnack(context, 'Product deleted');
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e);
    }
  }
}

/// Public create/edit form, reused from the product detail screen.
class ProductFormDialog extends StatelessWidget {
  const ProductFormDialog({
    super.key,
    required this.existing,
    required this.repo,
    required this.businesses,
    this.preselectBusinessId,
  });

  final Product? existing;
  final Repository repo;
  final List<Business> businesses;
  final String? preselectBusinessId;

  @override
  Widget build(BuildContext context) => _ProductFormDialog(
        existing: existing,
        repo: repo,
        businesses: businesses,
        preselectBusinessId: preselectBusinessId,
      );
}

class _ProductFormDialog extends StatefulWidget {
  const _ProductFormDialog({
    required this.existing,
    required this.repo,
    required this.businesses,
    this.preselectBusinessId,
  });

  final Product? existing;
  final Repository repo;
  final List<Business> businesses;
  final String? preselectBusinessId;

  @override
  State<_ProductFormDialog> createState() => _ProductFormDialogState();
}

class _ProductFormDialogState extends State<_ProductFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _buying;
  late final TextEditingController _selling;
  late final TextEditingController _url;
  late final TextEditingController _sku;
  late final TextEditingController _category;
  late EntityStatus _status;
  String? _businessId;

  Product? get _existing => widget.existing;

  @override
  void initState() {
    super.initState();
    final p = _existing;
    _name = TextEditingController(text: p?.name ?? '');
    _description = TextEditingController(text: p?.description ?? '');
    _buying = TextEditingController(
        text: p == null || p.buyingPrice.isZero
            ? ''
            : p.buyingPrice.major.toString());
    _selling = TextEditingController(
        text: p == null || p.sellingPrice.isZero
            ? ''
            : p.sellingPrice.major.toString());
    _url = TextEditingController(text: p?.url ?? '');
    _sku = TextEditingController(text: p?.sku ?? '');
    _category = TextEditingController(text: p?.category ?? '');
    _status = p?.status ?? EntityStatus.active;
    _businessId = p?.businessId ??
        widget.preselectBusinessId ??
        (widget.businesses.isNotEmpty ? widget.businesses.first.id : null);
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _buying.dispose();
    _selling.dispose();
    _url.dispose();
    _sku.dispose();
    _category.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isNew = _existing == null;
    return FormDialog(
      title: isNew ? 'Add Product' : 'Edit Product',
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
              label: 'Product Name',
              controller: _name,
              isRequired: true,
              validator: (v) => Validators.required(v, field: 'Product name'),
            ),
            const FormGap(),
            FormRow([
              AppMoneyField(
                label: 'Buying Price',
                controller: _buying,
                validator: (v) => Validators.optionalNonNegativeNumber(v),
              ),
              AppMoneyField(
                label: 'Selling Price',
                controller: _selling,
                validator: (v) => Validators.optionalNonNegativeNumber(v),
              ),
            ]),
            const FormGap(),
            FormRow([
              AppTextField(label: 'SKU', controller: _sku),
              AppTextField(label: 'Category', controller: _category),
            ]),
            const FormGap(),
            FormRow([
              AppTextField(
                label: 'Product URL',
                controller: _url,
                hintText: 'https://example.com/product',
                validator: (v) => Validators.url(v),
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
      showErrorSnack(context, 'Select a business for this product.');
      return false;
    }
    final isNew = _existing == null;
    final product = (_existing ??
            Product(id: '', businessId: bizId, name: _name.text.trim()))
        .copyWith(
      name: _name.text.trim(),
      description: _description.text.trim(),
      buyingPrice: Money.parse(_buying.text),
      sellingPrice: Money.parse(_selling.text),
      url: _url.text.trim(),
      sku: _sku.text.trim(),
      category: _category.text.trim(),
      status: _status,
    );
    try {
      await widget.repo.saveProduct(product, isNew: isNew);
      return true;
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
      return false;
    }
  }
}
