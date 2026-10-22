import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/enums.dart';
import '../../core/permissions.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_x.dart';
import '../../core/utils/money.dart';
import '../../core/validators.dart';
import '../../data/repository.dart';
import '../../models/business.dart';
import '../../models/product.dart';
import '../../services/profit_calculation_service.dart';
import '../../services/summaries/product_summaries.dart';
import '../../state/app_state.dart';
import '../../state/data_controller.dart';
import '../../state/filter_controller.dart';
import '../../widgets/common/confirm_dialog.dart';
import '../../widgets/common/csv_actions.dart';
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

/// Lists products for the selected business (or all accessible businesses):
/// catalogue figures, status quick filters, column filters, bulk status
/// changes and deletes, CSV import/export and a Duplicate action, with
/// create / edit / delete gated by permission.
class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();

  /// Opens the add/edit form (also used by quick-create and the palette):
  /// [existing] to edit, or a new product — prefilled from [duplicateOf]
  /// when given.
  static Future<void> openForm(
          BuildContext context, Product? existing, String? selectedBizId,
          {Product? duplicateOf}) =>
      _ProductsScreenState._openForm(context, existing, selectedBizId,
          duplicateOf: duplicateOf);
}

class _ProductsScreenState extends State<ProductsScreen> {
  static const _service = ProfitCalculationService();

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
          const PageHeader(title: 'Products', icon: Icons.inventory_2_outlined),
          const SizedBox(height: 48),
          ErrorView(message: data.error!, onRetry: () => data.refresh()),
        ],
      );
    }

    final bizId = filter.selectedBusinessId;
    final products = [...data.productsFor(bizId)]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final canCreate = user?.can(Permission.createProduct) ?? false;
    final canExport = user?.can(Permission.exportData) ?? false;
    final canEdit = user?.can(Permission.editProduct) ?? false;
    final canDelete = user?.can(Permission.deleteProduct) ?? false;
    final needsBusiness = bizId == null && data.selectableBusinesses.length > 1;
    final repo = appState.repository;
    final t = context.tokens;

    // Figures are shown in the selected business's currency; INR for all.
    final pageCurrency =
        (bizId == null ? null : data.businessById(bizId))?.currency ??
            CurrencyCode.inr;
    String money(Money m) => MoneyFormatter.compact(m, pageCurrency);
    CurrencyCode currencyOf(Product p) => _currencyFor(data, p.businessId);
    String businessOf(Product p) => data.businessById(p.businessId)?.name ?? '';
    final summary = _service.summariseProducts(products);

    final addButton = canCreate
        ? FilledButton.icon(
            onPressed: () => _openForm(context, null, bizId),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Product'),
          )
        : null;

    return AppPage.slivers(
      slivers: [
        SliverToBoxAdapter(
          child: PageHeader(
            title: 'Products',
            icon: Icons.inventory_2_outlined,
            count: products.length,
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
              ?addButton,
            ],
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
        if (products.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: KpiStrip(items: [
              KpiItem(
                label: 'Products',
                value: '${summary.count}',
                icon: Icons.inventory_2_outlined,
                caption: '${summary.activeCount} active',
              ),
              KpiItem(
                label: 'Avg. selling price',
                value: money(summary.averageSellingPrice),
                icon: Icons.sell_outlined,
                tooltip: 'Mean list price of products that have one.',
              ),
              KpiItem(
                label: 'Avg. buying price',
                value: money(summary.averageBuyingPrice),
                icon: Icons.shopping_bag_outlined,
                tooltip: 'Mean buying price of products that have one.',
              ),
              KpiItem(
                label: 'Avg. list margin',
                value: summary.averageMarkup == null
                    ? '—'
                    : PercentFormatter.format(summary.averageMarkup!),
                icon: Icons.percent,
                tone: summary.averageMarkup == null
                    ? null
                    : summary.averageMarkup! < 0
                        ? t.error
                        : t.success,
                tooltip: '(Selling − buying) ÷ selling, averaged over '
                    'products with a selling price.',
              ),
              KpiItem(
                label: 'Categories',
                value: '${summary.categoryCount}',
                icon: Icons.category_outlined,
                caption: summary.inactiveCount == 0
                    ? null
                    : '${summary.inactiveCount} not active',
              ),
            ]),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
        ],
        SliverAppDataGrid<Product>(
          gridId: 'products',
          rows: products,
          rowKey: (p) => p.id,
          exportName: 'products',
          searchHint: 'Search by ID, name, SKU, category or status…',
          searchText: (p) =>
              '${p.id} ${p.name} ${p.sku} ${p.category} ${p.status.label}',
          onRowTap: (p) => context.go(Routes.productDetailPath(p.id)),
          quickFilters: [
            for (final s in EntityStatus.values)
              GridQuickFilter<Product>(
                id: s.wire,
                label: s.label,
                test: (p) => p.status == s,
              ),
          ],
          bulkActions: [
            if (canEdit)
              GridBulkAction<Product>(
                label: 'Change status',
                icon: Icons.swap_horiz,
                children: [
                  for (final s in EntityStatus.values)
                    GridBulkAction<Product>(
                      label: s.label,
                      icon: switch (s) {
                        EntityStatus.active => Icons.check_circle_outline,
                        EntityStatus.inactive => Icons.pause_circle_outline,
                        EntityStatus.archived => Icons.archive_outlined,
                      },
                      allowed: (p) => p.status != s,
                      onRun: (context, rows) =>
                          _bulkStatus(context, repo, rows, s),
                    ),
                ],
              ),
            if (canDelete)
              GridBulkAction<Product>(
                label: 'Delete',
                icon: Icons.delete_outline,
                destructive: true,
                onRun: (context, rows) => _bulkDelete(context, repo, rows),
              ),
          ],
          emptyTitle: 'No products yet',
          emptyIcon: Icons.inventory_2_outlined,
          emptyMessage: canCreate
              ? 'Create your first product to start tracking profitability.'
              : 'Products will appear here once added.',
          emptyAction: addButton,
          columns: [
            GridColumn<Product>(
              id: 'id',
              label: 'Product ID',
              pinned: true,
              cardRole: CardRole.subtitle,
              minWidth: 110,
              cell: (p) => Text(p.id,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              sortValue: (p) => p.id,
              exportValue: (p) => p.id,
            ),
            GridColumn<Product>(
              id: 'name',
              label: 'Name',
              flex: 2,
              minWidth: 160,
              cardRole: CardRole.title,
              cell: (p) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (p.category.isNotEmpty)
                    Text(p.category,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12, color: context.tokens.textSecondary)),
                ],
              ),
              sortValue: (p) => p.name.toLowerCase(),
              exportValue: (p) => p.name,
            ),
            GridColumn<Product>(
              id: 'sku',
              label: 'SKU',
              cardRole: CardRole.meta,
              cell: (p) => Text(p.sku.isEmpty ? '—' : p.sku,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              sortValue: (p) => p.sku.toLowerCase(),
              exportValue: (p) => p.sku,
            ),
            GridColumn<Product>(
              id: 'category',
              label: 'Category',
              visibleByDefault: false,
              cardRole: CardRole.meta,
              cell: (p) => Text(p.category.isEmpty ? '—' : p.category,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              sortValue: (p) => p.category.toLowerCase(),
              exportValue: (p) => p.category,
              filter: GridFilter.choice(
                  (p) => p.category.isEmpty ? 'Uncategorised' : p.category),
            ),
            GridColumn<Product>(
              id: 'business',
              label: 'Business',
              visibleByDefault: false,
              cardRole: CardRole.meta,
              cell: (p) => Text(businessOf(p),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              sortValue: (p) => businessOf(p).toLowerCase(),
              exportValue: businessOf,
              filter: GridFilter.choice(businessOf),
            ),
            GridColumn<Product>(
              id: 'buying',
              label: 'Buying',
              numeric: true,
              cardRole: CardRole.metric,
              cell: (p) =>
                  CurrencyText(p.buyingPrice, currency: currencyOf(p)),
              sortValue: (p) => p.buyingPrice.minor,
              exportValue: (p) => p.buyingPrice.major.toStringAsFixed(2),
              filter: GridFilter.numberRange((p) => p.buyingPrice.major),
            ),
            GridColumn<Product>(
              id: 'selling',
              label: 'Selling',
              numeric: true,
              cardRole: CardRole.metric,
              cell: (p) =>
                  CurrencyText(p.sellingPrice, currency: currencyOf(p)),
              sortValue: (p) => p.sellingPrice.minor,
              exportValue: (p) => p.sellingPrice.major.toStringAsFixed(2),
              filter: GridFilter.numberRange((p) => p.sellingPrice.major),
            ),
            GridColumn<Product>(
              id: 'margin',
              label: 'Margin',
              numeric: true,
              cardRole: CardRole.metric,
              minWidth: 96,
              tooltip: '(Selling − buying) ÷ selling',
              cell: (p) => Text(_marginText(p)),
              sortValue: (p) =>
                  _service.summariseProducts([p]).averageMarkup ?? -1e9,
              exportValue: _marginText,
              footer: (rows) {
                final m = _service.summariseProducts(rows).averageMarkup;
                return m == null ? '—' : 'Avg ${PercentFormatter.format(m)}';
              },
            ),
            GridColumn<Product>(
              id: 'status',
              label: 'Status',
              cardRole: CardRole.badge,
              minWidth: 120,
              cell: (p) => StatusBadge.entity(p.status),
              sortValue: (p) => p.status.label,
              exportValue: (p) => p.status.label,
              filter: GridFilter.choice((p) => p.status.label,
                  options: [for (final s in EntityStatus.values) s.label]),
            ),
            GridColumn<Product>(
              id: 'actions',
              label: '',
              pinned: true,
              cardRole: CardRole.actions,
              // View, Edit, More and Delete (48 px each) plus the padding.
              minWidth: 2 * AppSpacing.md +
                  48 *
                      [true, canEdit, canCreate || canEdit, canDelete]
                          .where((b) => b)
                          .length,
              cell: (p) => _RowActions(
                product: p,
                canCreate: canCreate,
                canEdit: canEdit,
                canDelete: canDelete,
              ),
            ),
          ],
        ),
        if (needsBusiness)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: Text(
                'Tip: select a single business from the top bar to set which '
                'business new products are created in.',
                style: TextStyle(fontSize: 12, color: t.textTertiary),
              ),
            ),
          ),
      ],
    );
  }

  static String _marginText(Product p) {
    final m =
        const ProfitCalculationService().summariseProducts([p]).averageMarkup;
    return m == null ? '—' : PercentFormatter.format(m);
  }

  static CurrencyCode _currencyFor(DataController data, String businessId) =>
      data.businessById(businessId)?.currency ?? CurrencyCode.inr;

  static Future<void> _bulkStatus(BuildContext context, Repository repo,
      List<Product> rows, EntityStatus status) async {
    if (status != EntityStatus.active) {
      final ok = await showConfirmDialog(
        context,
        title: 'Mark ${_plural(rows.length)} ${status.label.toLowerCase()}?',
        message: 'They stay in your records and past orders, but are no '
            'longer treated as active products.',
        confirmLabel: 'Mark ${status.label.toLowerCase()}',
      );
      if (!ok || !context.mounted) return;
    }
    await runGridBulk<Product>(
      context,
      rows: rows,
      verb: 'Updating',
      noun: 'products',
      describe: (p) => p.name,
      task: (p) => repo.saveProduct(p.copyWith(status: status), isNew: false),
    );
  }

  static Future<void> _bulkDelete(
      BuildContext context, Repository repo, List<Product> rows) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Delete ${_plural(rows.length)}?',
      message: 'This removes them for everyone and cannot be easily undone.',
    );
    if (!ok || !context.mounted) return;
    await runGridBulk<Product>(
      context,
      rows: rows,
      verb: 'Deleting',
      noun: 'products',
      describe: (p) => p.name,
      task: (p) => repo.deleteProduct(p.id, known: p),
    );
  }

  static String _plural(int n) => n == 1 ? '1 product' : '$n products';

  static Future<void> _openForm(
      BuildContext context, Product? existing, String? selectedBizId,
      {Product? duplicateOf}) async {
    final data = context.read<DataController>();
    final repo = context.read<AppState>().repository;
    final businesses = data.selectableBusinesses;
    if (existing == null && businesses.isEmpty) {
      showErrorSnack(context, 'Create a business before adding products.');
      return;
    }
    final saved = await showAppForm<bool>(
      context: context,
      builder: (_) => _ProductFormDialog(
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
                ? 'Product created successfully'
                : 'Product updated successfully');
      }
    }
  }
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) => const AppPage(
        children: [
          PageHeader(title: 'Products', icon: Icons.inventory_2_outlined),
          SizedBox(height: AppSpacing.lg),
          SkeletonCard(lines: 1, height: 88),
          SizedBox(height: AppSpacing.lg),
          SkeletonCard(lines: 8),
        ],
      );
}

/// The single-product actions, shared by the list rows and the detail page.
class ProductActions {
  ProductActions._();

  static Future<void> duplicate(BuildContext context, Product product) =>
      ProductsScreen.openForm(context, null, product.businessId,
          duplicateOf: product);

  /// Changes the status after a confirm; true when it was saved.
  static Future<bool> setStatus(
      BuildContext context, Product product, EntityStatus status) async {
    final repo = context.read<AppState>().repository;
    if (status != EntityStatus.active) {
      final ok = await showConfirmDialog(
        context,
        title: 'Mark product ${status.label.toLowerCase()}?',
        message: '"${product.name}" stays in your records and past orders, '
            'but is no longer treated as an active product.',
        confirmLabel: 'Mark ${status.label.toLowerCase()}',
      );
      if (ok != true) return false;
    }
    try {
      await repo.saveProduct(product.copyWith(status: status), isNew: false);
      if (context.mounted) {
        showSuccessSnack(
            context, 'Product marked ${status.label.toLowerCase()}');
      }
      return true;
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e);
      return false;
    }
  }

  /// Returns true when the product was deleted.
  static Future<bool> delete(BuildContext context, Product product) async {
    final repo = context.read<AppState>().repository;
    final ok = await showConfirmDialog(
      context,
      title: 'Delete product?',
      message: 'Delete "${product.name}"? This action cannot be easily undone.',
    );
    if (ok != true) return false;
    try {
      await repo.deleteProduct(product.id, known: product);
      if (context.mounted) showSuccessSnack(context, 'Product deleted');
      return true;
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e);
      return false;
    }
  }
}

enum _ProductAction { duplicate, activate, deactivate }

class _RowActions extends StatelessWidget {
  const _RowActions({
    required this.product,
    required this.canCreate,
    required this.canEdit,
    required this.canDelete,
  });

  final Product product;
  final bool canCreate;
  final bool canEdit;
  final bool canDelete;

  @override
  Widget build(BuildContext context) {
    final canActivate = canEdit && product.status != EntityStatus.active;
    final canDeactivate = canEdit && product.status == EntityStatus.active;
    final hasMenu = canCreate || canActivate || canDeactivate;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'View',
          icon: const Icon(Icons.open_in_new, size: 18),
          onPressed: () => context.go(Routes.productDetailPath(product.id)),
        ),
        if (canEdit)
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined, size: 18),
            onPressed: () =>
                ProductsScreen.openForm(context, product, product.businessId),
          ),
        if (hasMenu)
          PopupMenuButton<_ProductAction>(
            tooltip: 'More actions',
            icon: const Icon(Icons.more_vert, size: 18),
            onSelected: (action) => switch (action) {
              _ProductAction.duplicate =>
                ProductActions.duplicate(context, product),
              _ProductAction.activate =>
                ProductActions.setStatus(context, product, EntityStatus.active),
              _ProductAction.deactivate => ProductActions.setStatus(
                  context, product, EntityStatus.inactive),
            },
            itemBuilder: (_) => [
              if (canCreate)
                const PopupMenuItem(
                  value: _ProductAction.duplicate,
                  child: _ActionRow(
                      icon: Icons.copy_all_outlined, label: 'Duplicate'),
                ),
              if (canActivate)
                const PopupMenuItem(
                  value: _ProductAction.activate,
                  child: _ActionRow(
                      icon: Icons.check_circle_outline, label: 'Mark active'),
                ),
              if (canDeactivate)
                const PopupMenuItem(
                  value: _ProductAction.deactivate,
                  child: _ActionRow(
                      icon: Icons.pause_circle_outline, label: 'Mark inactive'),
                ),
            ],
          ),
        if (canDelete)
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: () => ProductActions.delete(context, product),
          ),
      ],
    );
  }
}

/// A leading-icon + label row used inside the actions popup menu.
class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: AppSpacing.sm),
        Text(label),
      ],
    );
  }
}

/// Public create/edit form, reused from the product detail screen.
class ProductFormDialog extends StatelessWidget {
  const ProductFormDialog({
    super.key,
    required this.existing,
    required this.repo,
    required this.businesses,
    this.template,
    this.preselectBusinessId,
  });

  final Product? existing;

  /// A new product copies this one's details.
  final Product? template;
  final Repository repo;
  final List<Business> businesses;
  final String? preselectBusinessId;

  @override
  Widget build(BuildContext context) => _ProductFormDialog(
        existing: existing,
        template: template,
        repo: repo,
        businesses: businesses,
        preselectBusinessId: preselectBusinessId,
      );
}

class _ProductFormDialog extends StatefulWidget {
  const _ProductFormDialog({
    required this.existing,
    this.template,
    required this.repo,
    required this.businesses,
    this.preselectBusinessId,
  });

  final Product? existing;
  final Product? template;
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

  /// The chosen business's currency, for the money fields.
  CurrencyCode get _currency =>
      widget.businesses
          .where((b) => b.id == _businessId)
          .firstOrNull
          ?.currency ??
      CurrencyCode.inr;

  @override
  void initState() {
    super.initState();
    final p = _existing ?? widget.template;
    final copy = _existing == null && widget.template != null;
    _name = TextEditingController(
        text: p == null ? '' : (copy ? '${p.name} (copy)' : p.name));
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
    // A SKU identifies one product: a copy starts without it.
    _sku = TextEditingController(text: copy ? '' : p?.sku ?? '');
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
    final symbol = _currency.symbol;
    return FormDialog(
      title: isNew
          ? (widget.template == null ? 'Add Product' : 'Duplicate Product')
          : 'Edit Product',
      subtitle: widget.template == null || !isNew
          ? null
          : 'A new product, copied from ${widget.template!.name}',
      icon: Icons.inventory_2_outlined,
      draftKey: isNew && widget.template == null ? 'product.new' : null,
      onSubmit: _submit,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FormSection(
              title: 'Basics',
              icon: Icons.badge_outlined,
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
                    helper: 'Prices use this business\'s currency.',
                    onChanged: (v) => setState(() => _businessId = v),
                  ),
                  const FormGap(),
                ],
                AppTextField(
                  label: 'Product Name',
                  controller: _name,
                  isRequired: true,
                  validator: (v) =>
                      Validators.required(v, field: 'Product name'),
                ),
                const FormGap(),
                FormRow([
                  AppTextField(
                    label: 'SKU',
                    controller: _sku,
                    helper: 'Your stock-keeping code. Optional.',
                  ),
                  AppTextField(
                    label: 'Category',
                    controller: _category,
                    helper: 'Groups products in filters and reports.',
                  ),
                ]),
                const FormGap(),
                AppDropdown<EntityStatus>(
                  label: 'Status',
                  value: _status,
                  items: const [EntityStatus.active, EntityStatus.inactive],
                  itemLabel: (s) => s.label,
                  helper: 'Inactive products are kept but no longer sold.',
                  onChanged: (v) => setState(() => _status = v ?? _status),
                ),
              ],
            ),
            FormSection(
              title: 'Pricing',
              icon: Icons.payments_outlined,
              children: [
                FormRow([
                  AppMoneyField(
                    symbol: symbol,
                    label: 'Buying Price',
                    controller: _buying,
                    helper: 'Default cost to buy one unit.',
                    validator: (v) => Validators.optionalNonNegativeNumber(v),
                  ),
                  AppMoneyField(
                    symbol: symbol,
                    label: 'Selling Price',
                    controller: _selling,
                    helper: 'Default price per unit on new orders.',
                    validator: (v) => Validators.optionalNonNegativeNumber(v),
                  ),
                ]),
                const FormGap(),
                _MarginStrip(
                  listenable: Listenable.merge([_buying, _selling]),
                  preview: _preview,
                  currency: _currency,
                ),
              ],
            ),
            FormSection(
              title: 'Details',
              icon: Icons.notes_outlined,
              children: [
                AppTextField(
                  label: 'Product URL',
                  controller: _url,
                  hintText: 'https://example.com/product',
                  helper: 'Link to the product page. Optional.',
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
          ],
        ),
      ),
    );
  }

  /// The product as currently typed, for the live margin.
  Product _preview() => Product(
        id: '',
        businessId: '',
        name: '',
        buyingPrice: Money.parse(_buying.text),
        sellingPrice: Money.parse(_selling.text),
      );

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

/// Profit per unit and margin of the prices being typed.
class _MarginStrip extends StatelessWidget {
  const _MarginStrip({
    required this.listenable,
    required this.preview,
    required this.currency,
  });

  final Listenable listenable;
  final Product Function() preview;
  final CurrencyCode currency;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ListenableBuilder(
      listenable: listenable,
      builder: (context, _) {
        final p = preview();
        final perUnit = p.sellingPrice - p.buyingPrice;
        final margin = const ProfitCalculationService()
            .summariseProducts([p]).averageMarkup;
        final tone = perUnit.isNegative ? t.error : t.success;
        Widget figure(String label, String value, {Color? color}) => Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(fontSize: 11.5, color: t.textSecondary)),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(value,
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: color ?? t.textPrimary,
                            fontFeatures: const [
                              FontFeature.tabularFigures()
                            ])),
                  ),
                ],
              ),
            );
        return Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: t.primarySurface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            border: Border.all(color: t.primary.withValues(alpha: 0.15)),
          ),
          child: Row(
            children: [
              figure(
                  'Profit per unit', MoneyFormatter.format(perUnit, currency),
                  color: tone),
              figure('List margin',
                  margin == null ? '—' : PercentFormatter.format(margin),
                  color: margin == null ? null : tone),
            ],
          ),
        );
      },
    );
  }
}
