import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
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
import '../../models/campaign.dart';
import '../../models/product.dart';
import '../../services/profit_calculation_service.dart';
import '../../services/smart/suggestion_service.dart';
import '../../services/summaries/campaign_summaries.dart';
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
import '../../widgets/forms/suggestion_chips.dart';
import '../../widgets/layout/app_page.dart';
import '../../widgets/layout/kpi_strip.dart';

/// Lists marketing campaigns for the selected scope: spend and performance
/// figures, status and platform quick filters, column filters, bulk status
/// changes and deletes, export and a Duplicate action, with full CRUD gated
/// by permission.
class CampaignsScreen extends StatefulWidget {
  const CampaignsScreen({super.key});

  @override
  State<CampaignsScreen> createState() => _CampaignsScreenState();

  /// Opens the campaign form: [existing] to edit, or a new campaign —
  /// prefilled from [duplicateOf] when given.
  static Future<void> openForm(
      BuildContext context, Campaign? existing, String? selectedBizId,
      {Campaign? duplicateOf}) async {
    final data = context.read<DataController>();
    final repo = context.read<AppState>().repository;
    final businesses = data.selectableBusinesses;
    if (existing == null && data.products.isEmpty) {
      showErrorSnack(context, 'Create a product before adding campaigns.');
      return;
    }
    final saved = await showAppForm<bool>(
      context: context,
      builder: (_) => _CampaignFormDialog(
        existing: existing,
        template: duplicateOf,
        repo: repo,
        businesses: businesses,
        allProducts: data.products,
        preselectBusinessId: selectedBizId,
      ),
    );
    if (saved == true) {
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

class _CampaignsScreenState extends State<CampaignsScreen> {
  static const _service = ProfitCalculationService();
  static final _epoch = DateTime.fromMillisecondsSinceEpoch(0);
  static DateTime _dateOf(Campaign c) =>
      c.startDate ?? c.audit.createdAt ?? _epoch;

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
          const PageHeader(title: 'Campaigns', icon: Icons.campaign_outlined),
          const SizedBox(height: 48),
          ErrorView(message: data.error!, onRetry: () => data.refresh()),
        ],
      );
    }

    final bizId = filter.selectedBusinessId;
    final campaigns = [...data.campaignsFor(bizId)]
      ..sort((a, b) => _dateOf(b).compareTo(_dateOf(a)));
    final canCreate = user?.can(Permission.createCampaign) ?? false;
    final canEdit = user?.can(Permission.editCampaign) ?? false;
    final canDelete = user?.can(Permission.deleteCampaign) ?? false;
    final repo = appState.repository;
    final t = context.tokens;

    String productOf(Campaign c) =>
        data.productById(c.productId)?.name ?? '—';
    String businessOf(Campaign c) =>
        data.businessById(c.businessId)?.name ?? '';
    CurrencyCode currencyOf(Campaign c) =>
        data.businessById(c.businessId)?.currency ?? CurrencyCode.inr;
    // Figures are shown in the selected business's currency; INR for all.
    final pageCurrency =
        (bizId == null ? null : data.businessById(bizId))?.currency ??
            CurrencyCode.inr;
    String money(Money m) => MoneyFormatter.compact(m, pageCurrency);

    final summary = _service.summariseCampaigns(campaigns);
    final cpa = summary.costPerConversion;
    final used = summary.budgetUsed;

    final addButton = canCreate
        ? FilledButton.icon(
            onPressed: () => CampaignsScreen.openForm(context, null, bizId),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Campaign'),
          )
        : null;

    return AppPage.slivers(
      slivers: [
        SliverToBoxAdapter(
          child: PageHeader(
            title: 'Campaigns',
            icon: Icons.campaign_outlined,
            count: campaigns.length,
            subtitle: 'Track advertising spend and performance',
            actions: [?addButton],
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
        if (campaigns.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: KpiStrip(items: [
              KpiItem(
                label: 'Campaigns',
                value: '${summary.count}',
                icon: Icons.campaign_outlined,
                caption: '${summary.activeCount} active',
              ),
              KpiItem(
                label: 'Total spend',
                value: money(summary.spend),
                icon: Icons.payments_outlined,
                caption: used == null
                    ? null
                    : '${used.toStringAsFixed(0)}% of ${money(summary.budget)} budget',
                tooltip: 'Amount invested across these campaigns.',
              ),
              KpiItem(
                label: 'Impressions',
                value: _count(summary.impressions),
                icon: Icons.visibility_outlined,
              ),
              KpiItem(
                label: 'Clicks',
                value: _count(summary.clicks),
                icon: Icons.ads_click,
                caption: '${PercentFormatter.format(summary.ctr)} CTR',
                tooltip: 'Click-through rate: clicks ÷ impressions.',
              ),
              KpiItem(
                label: 'Conversions',
                value: _count(summary.conversions),
                icon: Icons.task_alt,
                caption:
                    '${PercentFormatter.format(summary.conversionRate)} of clicks',
                tooltip: 'Conversion rate: conversions ÷ clicks.',
              ),
              KpiItem(
                label: 'Cost / conversion',
                value: cpa == null ? '—' : money(cpa),
                icon: Icons.price_check,
                tone: cpa == null ? null : t.primary,
                tooltip: 'Total spend ÷ conversions.',
              ),
            ]),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
        ],
        SliverAppDataGrid<Campaign>(
          gridId: 'campaigns',
          rows: campaigns,
          rowKey: (c) => c.id,
          exportName: 'campaigns',
          searchHint: 'Search by name, product, platform, type or status…',
          searchText: (c) =>
              '${c.id} ${c.name} ${c.platform.label} ${c.type} '
              '${c.status.label} ${productOf(c)}',
          onRowTap: (c) => context.go(Routes.campaignDetailPath(c.id)),
          quickFilters: [
            for (final s in CampaignStatus.values)
              GridQuickFilter<Campaign>(
                id: s.wire,
                label: s.label,
                test: (c) => c.status == s,
              ),
            for (final p in CampaignPlatform.values)
              GridQuickFilter<Campaign>(
                id: 'platform-${p.wire}',
                label: p.label,
                icon: Icons.ads_click,
                test: (c) => c.platform == p,
              ),
          ],
          bulkActions: [
            if (canEdit)
              GridBulkAction<Campaign>(
                label: 'Change status',
                icon: Icons.swap_horiz,
                children: [
                  for (final s in CampaignStatus.values)
                    GridBulkAction<Campaign>(
                      label: s.label,
                      icon: _statusIcon(s),
                      allowed: (c) => c.status != s,
                      onRun: (context, rows) =>
                          _bulkStatus(context, repo, rows, s),
                    ),
                ],
              ),
            if (canDelete)
              GridBulkAction<Campaign>(
                label: 'Delete',
                icon: Icons.delete_outline,
                destructive: true,
                onRun: (context, rows) => _bulkDelete(context, repo, rows),
              ),
          ],
          emptyTitle: 'No campaigns yet',
          emptyIcon: Icons.campaign_outlined,
          emptyMessage: canCreate
              ? 'Create your first campaign to start tracking marketing spend.'
              : 'Campaigns will appear here once added.',
          emptyAction: addButton,
          columns: [
            GridColumn<Campaign>(
              id: 'id',
              label: 'Campaign ID',
              visibleByDefault: false,
              cardRole: CardRole.subtitle,
              minWidth: 110,
              cell: (c) => Text(c.id,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              sortValue: (c) => c.id,
              exportValue: (c) => c.id,
            ),
            GridColumn<Campaign>(
              id: 'name',
              label: 'Campaign',
              pinned: true,
              flex: 2,
              minWidth: 170,
              cardRole: CardRole.title,
              cell: (c) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(c.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(productOf(c),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12, color: context.tokens.textSecondary)),
                ],
              ),
              sortValue: (c) => c.name.toLowerCase(),
              exportValue: (c) => c.name,
            ),
            GridColumn<Campaign>(
              id: 'product',
              label: 'Product',
              visibleByDefault: false,
              cardRole: CardRole.subtitle,
              cell: (c) => Text(productOf(c),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              sortValue: (c) => productOf(c).toLowerCase(),
              exportValue: productOf,
              filter: GridFilter.choice(productOf),
            ),
            GridColumn<Campaign>(
              id: 'business',
              label: 'Business',
              visibleByDefault: false,
              cardRole: CardRole.meta,
              cell: (c) => Text(businessOf(c),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              sortValue: (c) => businessOf(c).toLowerCase(),
              exportValue: businessOf,
              filter: GridFilter.choice(businessOf),
            ),
            GridColumn<Campaign>(
              id: 'platform',
              label: 'Platform',
              cardRole: CardRole.meta,
              minWidth: 120,
              cell: (c) =>
                  StatusBadge(label: c.platform.label, tone: BadgeTone.info),
              sortValue: (c) => c.platform.label,
              exportValue: (c) => c.platform.label,
              filter: GridFilter.choice((c) => c.platform.label,
                  options: [for (final p in CampaignPlatform.values) p.label]),
            ),
            GridColumn<Campaign>(
              id: 'type',
              label: 'Type',
              cardRole: CardRole.meta,
              cell: (c) => Text(c.type.isEmpty ? '—' : c.type,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              sortValue: (c) => c.type.toLowerCase(),
              exportValue: (c) => c.type,
              filter: GridFilter.choice(
                  (c) => c.type.isEmpty ? 'No type' : c.type),
            ),
            GridColumn<Campaign>(
              id: 'start',
              label: 'Start',
              visibleByDefault: false,
              cardRole: CardRole.meta,
              minWidth: 110,
              cell: (c) => Text(
                  c.startDate == null ? '—' : AppDate.format(c.startDate)),
              sortValue: (c) => c.startDate?.millisecondsSinceEpoch ?? 0,
              exportValue: (c) =>
                  c.startDate == null ? '' : AppDate.format(c.startDate),
              filter: GridFilter.dateRange((c) => c.startDate),
            ),
            GridColumn<Campaign>(
              id: 'end',
              label: 'End',
              visibleByDefault: false,
              cardRole: CardRole.hidden,
              minWidth: 110,
              cell: (c) =>
                  Text(c.endDate == null ? '—' : AppDate.format(c.endDate)),
              sortValue: (c) => c.endDate?.millisecondsSinceEpoch ?? 0,
              exportValue: (c) =>
                  c.endDate == null ? '' : AppDate.format(c.endDate),
              filter: GridFilter.dateRange((c) => c.endDate),
            ),
            GridColumn<Campaign>(
              id: 'budget',
              label: 'Budget',
              numeric: true,
              visibleByDefault: false,
              cardRole: CardRole.hidden,
              cell: (c) => CurrencyText(c.budget, currency: currencyOf(c)),
              sortValue: (c) => c.budget.minor,
              exportValue: (c) => c.budget.major.toStringAsFixed(2),
              filter: GridFilter.numberRange((c) => c.budget.major),
              footer: (rows) => money(_service.summariseCampaigns(rows).budget),
            ),
            GridColumn<Campaign>(
              id: 'spend',
              label: 'Spend',
              numeric: true,
              cardRole: CardRole.metric,
              cell: (c) =>
                  CurrencyText(c.amountInvested, currency: currencyOf(c)),
              sortValue: (c) => c.amountInvested.minor,
              exportValue: (c) => c.amountInvested.major.toStringAsFixed(2),
              filter: GridFilter.numberRange((c) => c.amountInvested.major),
              footer: (rows) => money(_service.summariseCampaigns(rows).spend),
            ),
            GridColumn<Campaign>(
              id: 'clicks',
              label: 'Clicks',
              numeric: true,
              minWidth: 80,
              cardRole: CardRole.metric,
              cell: (c) => Text('${c.clicks}'),
              sortValue: (c) => c.clicks,
              exportValue: (c) => '${c.clicks}',
              footer: (rows) =>
                  '${_service.summariseCampaigns(rows).clicks}',
            ),
            GridColumn<Campaign>(
              id: 'conversions',
              label: 'Conv.',
              numeric: true,
              minWidth: 80,
              cardRole: CardRole.metric,
              tooltip: 'Conversions',
              cell: (c) => Text('${c.conversions}'),
              sortValue: (c) => c.conversions,
              exportValue: (c) => '${c.conversions}',
              footer: (rows) =>
                  '${_service.summariseCampaigns(rows).conversions}',
            ),
            GridColumn<Campaign>(
              id: 'ctr',
              label: 'CTR',
              numeric: true,
              visibleByDefault: false,
              minWidth: 80,
              cardRole: CardRole.hidden,
              tooltip: 'Click-through rate: clicks ÷ impressions',
              cell: (c) => Text(PercentFormatter.format(c.ctr)),
              sortValue: (c) => c.ctr,
              exportValue: (c) => c.ctr.toStringAsFixed(2),
            ),
            GridColumn<Campaign>(
              id: 'status',
              label: 'Status',
              cardRole: CardRole.badge,
              minWidth: 120,
              cell: (c) => StatusBadge.campaign(c.status),
              sortValue: (c) => c.status.label,
              exportValue: (c) => c.status.label,
              filter: GridFilter.choice((c) => c.status.label,
                  options: [for (final s in CampaignStatus.values) s.label]),
            ),
            GridColumn<Campaign>(
              id: 'actions',
              label: '',
              pinned: true,
              cardRole: CardRole.actions,
              // Edit, More and Delete (48 px each) plus the cell padding.
              minWidth: 2 * AppSpacing.md +
                  48 *
                      [canEdit, canEdit || canCreate, canDelete]
                          .where((b) => b)
                          .length,
              cell: (c) => _RowActions(
                campaign: c,
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

  /// 12,345 style grouping for headline counts.
  static String _count(int n) => NumberFormat.decimalPattern('en_IN').format(n);

  static IconData _statusIcon(CampaignStatus s) => switch (s) {
        CampaignStatus.draft => Icons.edit_note,
        CampaignStatus.active => Icons.play_circle_outline,
        CampaignStatus.paused => Icons.pause_circle_outline,
        CampaignStatus.completed => Icons.check_circle_outline,
        CampaignStatus.cancelled => Icons.cancel_outlined,
      };

  static Future<void> _bulkStatus(BuildContext context, Repository repo,
      List<Campaign> rows, CampaignStatus status) async {
    if (status == CampaignStatus.cancelled ||
        status == CampaignStatus.completed) {
      final ok = await showConfirmDialog(
        context,
        title: 'Mark ${_plural(rows.length)} ${status.label.toLowerCase()}?',
        message: 'Their recorded spend stays in your profit calculations.',
        confirmLabel: 'Mark ${status.label.toLowerCase()}',
        destructive: status == CampaignStatus.cancelled,
      );
      if (!ok || !context.mounted) return;
    }
    await runGridBulk<Campaign>(
      context,
      rows: rows,
      verb: 'Updating',
      noun: 'campaigns',
      describe: (c) => c.name,
      task: (c) => repo.saveCampaign(c.copyWith(status: status), isNew: false),
    );
  }

  static Future<void> _bulkDelete(
      BuildContext context, Repository repo, List<Campaign> rows) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Delete ${_plural(rows.length)}?',
      message: 'This removes them for everyone, along with their spend in '
          'profit calculations. It cannot be easily undone.',
    );
    if (!ok || !context.mounted) return;
    await runGridBulk<Campaign>(
      context,
      rows: rows,
      verb: 'Deleting',
      noun: 'campaigns',
      describe: (c) => c.name,
      task: (c) => repo.deleteCampaign(c.id, known: c),
    );
  }

  static String _plural(int n) => n == 1 ? '1 campaign' : '$n campaigns';
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) => const AppPage(
        children: [
          PageHeader(title: 'Campaigns', icon: Icons.campaign_outlined),
          SizedBox(height: AppSpacing.lg),
          SkeletonCard(lines: 1, height: 88),
          SizedBox(height: AppSpacing.lg),
          SkeletonCard(lines: 8),
        ],
      );
}

/// The single-campaign actions, shared by the list rows and the detail page.
class CampaignActions {
  CampaignActions._();

  static Future<void> duplicate(BuildContext context, Campaign campaign) =>
      CampaignsScreen.openForm(context, null, campaign.businessId,
          duplicateOf: campaign);

  /// Changes the status after a confirm where it matters; true when saved.
  static Future<bool> setStatus(
      BuildContext context, Campaign campaign, CampaignStatus status) async {
    final repo = context.read<AppState>().repository;
    if (status == CampaignStatus.cancelled ||
        status == CampaignStatus.completed) {
      final ok = await showConfirmDialog(
        context,
        title: 'Mark campaign ${status.label.toLowerCase()}?',
        message: '"${campaign.name}" keeps its recorded spend in your profit '
            'calculations.',
        confirmLabel: 'Mark ${status.label.toLowerCase()}',
        destructive: status == CampaignStatus.cancelled,
      );
      if (ok != true) return false;
    }
    try {
      await repo.saveCampaign(campaign.copyWith(status: status), isNew: false);
      if (context.mounted) {
        showSuccessSnack(
            context, 'Campaign marked ${status.label.toLowerCase()}');
      }
      return true;
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e);
      return false;
    }
  }

  /// Returns true when the campaign was deleted.
  static Future<bool> delete(BuildContext context, Campaign campaign) async {
    final repo = context.read<AppState>().repository;
    final ok = await showConfirmDialog(
      context,
      title: 'Delete campaign?',
      message:
          'Delete "${campaign.name}"? This action cannot be easily undone.',
    );
    if (ok != true) return false;
    try {
      await repo.deleteCampaign(campaign.id, known: campaign);
      if (context.mounted) showSuccessSnack(context, 'Campaign deleted');
      return true;
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e);
      return false;
    }
  }
}

enum _CampaignAction { duplicate, activate, pause }

class _RowActions extends StatelessWidget {
  const _RowActions({
    required this.campaign,
    required this.canCreate,
    required this.canEdit,
    required this.canDelete,
  });

  final Campaign campaign;
  final bool canCreate;
  final bool canEdit;
  final bool canDelete;

  @override
  Widget build(BuildContext context) {
    if (!canEdit && !canDelete && !canCreate) return const SizedBox.shrink();
    final canActivate = canEdit &&
        (campaign.status == CampaignStatus.draft ||
            campaign.status == CampaignStatus.paused);
    final canPause = canEdit && campaign.status == CampaignStatus.active;
    final hasMenu = canCreate || canActivate || canPause;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (canEdit)
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined, size: 18),
            onPressed: () => CampaignsScreen.openForm(
                context, campaign, campaign.businessId),
          ),
        if (hasMenu)
          PopupMenuButton<_CampaignAction>(
            tooltip: 'More actions',
            icon: const Icon(Icons.more_vert, size: 18),
            onSelected: (action) => switch (action) {
              _CampaignAction.duplicate =>
                CampaignActions.duplicate(context, campaign),
              _CampaignAction.activate => CampaignActions.setStatus(
                  context, campaign, CampaignStatus.active),
              _CampaignAction.pause => CampaignActions.setStatus(
                  context, campaign, CampaignStatus.paused),
            },
            itemBuilder: (_) => [
              if (canCreate)
                const PopupMenuItem(
                  value: _CampaignAction.duplicate,
                  child: _ActionRow(
                      icon: Icons.copy_all_outlined, label: 'Duplicate'),
                ),
              if (canActivate)
                const PopupMenuItem(
                  value: _CampaignAction.activate,
                  child: _ActionRow(
                      icon: Icons.play_circle_outline, label: 'Mark active'),
                ),
              if (canPause)
                const PopupMenuItem(
                  value: _CampaignAction.pause,
                  child: _ActionRow(
                      icon: Icons.pause_circle_outline, label: 'Pause'),
                ),
            ],
          ),
        if (canDelete)
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: () => CampaignActions.delete(context, campaign),
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

class _CampaignFormDialog extends StatefulWidget {
  const _CampaignFormDialog({
    required this.existing,
    this.template,
    required this.repo,
    required this.businesses,
    required this.allProducts,
    this.preselectBusinessId,
  });

  final Campaign? existing;

  /// A new campaign copies this one's setup (results start at zero).
  final Campaign? template;
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

  static const _suggest = DartSuggestionProvider();

  /// The selected product's business (the campaign's business).
  String? get _businessId => widget.allProducts
      .where((p) => p.id == _productId)
      .firstOrNull
      ?.businessId;

  /// The selected product's business currency, for the money fields.
  CurrencyCode get _currency {
    final bizId = _businessId;
    return widget.businesses.where((b) => b.id == bizId).firstOrNull?.currency ??
        CurrencyCode.inr;
  }

  @override
  void initState() {
    super.initState();
    final c = _existing ?? widget.template;
    final copy = _existing == null && widget.template != null;
    _name = TextEditingController(
        text: c == null ? '' : (copy ? '${c.name} (copy)' : c.name));
    _type = TextEditingController(text: c?.type ?? '');
    _budget = TextEditingController(
        text: c == null || c.budget.isZero ? '' : c.budget.major.toString());
    // A copy starts a fresh run: no spend and no results yet.
    final r = copy ? null : c;
    _invested = TextEditingController(
        text: r == null || r.amountInvested.isZero
            ? ''
            : r.amountInvested.major.toString());
    _impressions =
        TextEditingController(text: r == null ? '' : '${r.impressions}');
    _clicks = TextEditingController(text: r == null ? '' : '${r.clicks}');
    _conversions =
        TextEditingController(text: r == null ? '' : '${r.conversions}');
    _url = TextEditingController(text: c?.url ?? '');
    _notes = TextEditingController(text: c?.notes ?? '');
    _platform = c?.platform ?? CampaignPlatform.meta;
    _status = copy ? CampaignStatus.draft : (c?.status ?? CampaignStatus.draft);
    _startDate = c?.startDate;
    _endDate = c?.endDate;
    _productId = c?.productId ?? _initialProductId();
  }

  String? _initialProductId() {
    final scoped = _scopedProducts(widget.preselectBusinessId);
    return scoped.isNotEmpty ? scoped.first.id : null;
  }

  List<Product> _scopedProducts(String? bizId) => bizId == null
      ? widget.allProducts
      : widget.allProducts.where((p) => p.businessId == bizId).toList();

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
    // Products selectable in this dialog are scoped to the active business
    // (the campaign's business follows the chosen product). When no business
    // is pinned, every accessible product is offered — still searchable.
    final products = _scopedProducts(widget.preselectBusinessId);
    final symbol = _currency.symbol;
    final history = context
        .select<DataController, List<Campaign>>((d) => d.campaignsFor(null));
    final bizId = _businessId;
    return FormDialog(
      title: isNew
          ? (widget.template == null ? 'Add Campaign' : 'Duplicate Campaign')
          : 'Edit Campaign',
      subtitle: widget.template == null || !isNew
          ? null
          : 'A new campaign, copied from ${widget.template!.name}',
      icon: Icons.campaign_outlined,
      draftKey: isNew && widget.template == null ? 'campaign.new' : null,
      onSubmit: _submit,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FormSection(
              title: 'Basics & type',
              icon: Icons.campaign_outlined,
              first: true,
              children: [
                AppTextField(
                  label: 'Campaign Name',
                  controller: _name,
                  isRequired: true,
                  validator: (v) =>
                      Validators.required(v, field: 'Campaign name'),
                ),
                const FormGap(),
                AppSearchableDropdown<String>(
                  label: 'Product',
                  isRequired: true,
                  value: _productId,
                  items: [for (final p in products) p.id],
                  itemLabel: (id) => _labelForProduct(products, id),
                  hintText: 'Search products…',
                  helper: 'Its spend counts towards this product\'s profit.',
                  onChanged: (v) => setState(() => _productId = v),
                ),
                const FormGap(),
                FormRow([
                  AppDropdown<CampaignPlatform>(
                    label: 'Platform',
                    value: _platform,
                    items: CampaignPlatform.values,
                    itemLabel: (p) => p.label,
                    onChanged: (v) =>
                        setState(() => _platform = v ?? _platform),
                  ),
                  AppDropdown<CampaignStatus>(
                    label: 'Status',
                    value: _status,
                    items: CampaignStatus.values,
                    itemLabel: (s) => s.label,
                    onChanged: (v) => setState(() => _status = v ?? _status),
                  ),
                ]),
                if (isNew)
                  ListenableBuilder(
                    listenable: _name,
                    builder: (context, _) =>
                        SuggestionChips<CampaignPlatform>(
                      suggestions: _suggest.campaignPlatform(
                          name: _name.text,
                          history: history,
                          businessId: bizId),
                      labelOf: (p) => p.label,
                      current: _platform,
                      onSelected: (p) => setState(() => _platform = p),
                    ),
                  ),
                const FormGap(),
                AppTextField(
                  label: 'Type',
                  controller: _type,
                  hintText: 'e.g. Awareness, Retargeting, Lead generation',
                  helper: 'What the campaign is for. Optional.',
                ),
                ListenableBuilder(
                  listenable: _type,
                  builder: (context, _) => SuggestionChips<String>(
                    suggestions: _suggest.campaignType(
                        typed: _type.text, history: history, businessId: bizId),
                    labelOf: (v) => v,
                    current: _type.text.trim(),
                    onSelected: (v) => _type.text = v,
                  ),
                ),
                const FormGap(),
                AppTextField(
                  label: 'Campaign URL',
                  controller: _url,
                  hintText: 'https://…',
                  helper: 'Link to the ad or campaign manager. Optional.',
                  validator: (v) => Validators.url(v),
                ),
              ],
            ),
            FormSection(
              title: 'Budget & dates',
              icon: Icons.event_outlined,
              children: [
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
                    symbol: symbol,
                    label: 'Budget',
                    controller: _budget,
                    helper: 'What you plan to spend.',
                    validator: (v) => Validators.optionalNonNegativeNumber(v),
                  ),
                  AppMoneyField(
                    symbol: symbol,
                    label: 'Amount Invested',
                    controller: _invested,
                    helper: 'What you have actually spent.',
                    validator: (v) => Validators.optionalNonNegativeNumber(v),
                  ),
                ]),
              ],
            ),
            FormSection(
              title: 'Results',
              icon: Icons.insights_outlined,
              children: [
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
                _RatesStrip(
                  listenable: Listenable.merge(
                      [_impressions, _clicks, _conversions]),
                  preview: _preview,
                ),
              ],
            ),
            FormSection(
              title: 'Notes',
              icon: Icons.notes_outlined,
              children: [
                AppTextField(label: 'Notes', controller: _notes, maxLines: 3),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// The campaign as currently typed, for the live rates.
  Campaign _preview() => Campaign(
        id: '',
        businessId: '',
        productId: '',
        name: '',
        impressions: _parseInt(_impressions.text),
        clicks: _parseInt(_clicks.text),
        conversions: _parseInt(_conversions.text),
      );

  String _labelForProduct(List<Product> products, String id) {
    final product = products.where((p) => p.id == id).firstOrNull ??
        widget.allProducts.where((p) => p.id == id).firstOrNull;
    if (product == null) return id;
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
    final product = widget.allProducts.firstWhere((p) => p.id == productId);
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

/// Click-through and conversion rates of the results being typed.
class _RatesStrip extends StatelessWidget {
  const _RatesStrip({required this.listenable, required this.preview});

  final Listenable listenable;
  final Campaign Function() preview;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ListenableBuilder(
      listenable: listenable,
      builder: (context, _) {
        final c = preview();
        Widget figure(String label, String value) => Expanded(
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
                            color: t.textPrimary,
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
              figure('CTR (clicks ÷ impressions)',
                  PercentFormatter.format(c.ctr)),
              figure('Conv. rate (conversions ÷ clicks)',
                  PercentFormatter.format(c.conversionRate)),
            ],
          ),
        );
      },
    );
  }
}
