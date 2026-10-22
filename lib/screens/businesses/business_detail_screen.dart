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
import '../../models/business.dart';
import '../../models/campaign.dart';
import '../../models/dealer.dart';
import '../../models/expense.dart';
import '../../models/order.dart';
import '../../models/product.dart';
import '../../services/profit_calculation_service.dart';
import '../../state/app_state.dart';
import '../../state/data_controller.dart';
import '../../state/filter_controller.dart';
import '../../widgets/common/app_card.dart';
import '../../widgets/common/comment_thread.dart';
import '../../widgets/common/currency_display.dart';
import '../../widgets/common/detail_widgets.dart';
import '../../widgets/common/status_badge.dart';
import '../../widgets/common/team_access_card.dart';
import '../../widgets/data/app_data_grid.dart';
import '../../widgets/layout/detail_page.dart';
import '../../widgets/layout/kpi_strip.dart';
import 'businesses_screen.dart';

/// A full-screen business profile: identity, tenure and social links, the
/// headline figures, every mapped entity (products, campaigns, orders,
/// expenses, dealers) scoped to this business, a team-access roster, and a
/// comment thread.
///
/// Every mapped table is fed from the [DataController]'s already-access-scoped
/// lists, so a viewer only ever sees data for businesses they can access.
class BusinessDetailScreen extends StatelessWidget {
  const BusinessDetailScreen({super.key, required this.businessId});

  final String businessId;

  static const _service = ProfitCalculationService();

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataController>();
    final filter = context.watch<FilterController>();
    final appState = context.watch<AppState>();
    final user = appState.currentUser;
    void back() => context.go(Routes.businesses);

    if (data.loading && !data.loaded) {
      return DetailPage.loading(
          title: 'Business', onBack: back, backLabel: 'Businesses');
    }

    final business = data.businessById(businessId);
    if (business == null) {
      return DetailPage.notFound(
        title: 'Business',
        onBack: back,
        backLabel: 'Businesses',
        message: 'This business may have been removed or is not accessible.',
      );
    }

    final t = context.tokens;
    final currency = business.currency;
    final products = data.productsFor(business.id);
    final campaigns = data.campaignsFor(business.id);
    final orders = data.ordersFor(business.id);
    final expenses = data.expensesFor(business.id);
    final dealers = data.dealersFor(business.id);

    final summary = _service.summarise(
      orders: orders,
      campaigns: campaigns,
      expenses: expenses,
      range: filter.range,
    );

    final canEdit = user?.can(Permission.editBusiness) ?? false;
    final canArchive = user?.can(Permission.deleteBusiness) ?? false;
    final canRestore = canEdit && BusinessActions.canRestore(business);
    final canArchiveNow = canArchive && BusinessActions.canArchive(business);
    final tenure = business.tenure(DateTime.now());
    final period = filter.periodLabel;
    String money(Money m) => MoneyFormatter.format(m, currency);

    final repo = appState.repository;

    return DetailPage(
      title: business.name,
      subtitle: '${business.id}'
          '${business.type.isEmpty ? '' : ' · ${business.type}'}',
      avatarName: business.name,
      backLabel: 'Businesses',
      onBack: back,
      status: Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        children: [
          _LifecycleBadge(lifecycle: business.lifecycle),
          if (business.status != EntityStatus.active)
            StatusBadge.entity(business.status),
        ],
      ),
      meta: [
        if (business.type.isNotEmpty)
          DetailMeta(Icons.category_outlined, business.type, tooltip: 'Type'),
        DetailMeta(
          business.isClosed
              ? Icons.history_toggle_off
              : Icons.timelapse_outlined,
          tenure == null
              ? 'No start date'
              : (tenure.isToday ? 'Started today' : tenure.shortLabel),
          tooltip: business.isClosed ? 'Operated for' : 'Trading for',
        ),
        DetailMeta(Icons.public, business.country.isEmpty
            ? currency.name.toUpperCase()
            : '${business.country} · ${currency.name.toUpperCase()}',
            tooltip: 'Country and currency'),
        if (business.website.trim().isNotEmpty)
          DetailMeta(Icons.link, business.website.trim(),
              tooltip: 'Open website',
              onTap: () => openExternalUrl(business.website.trim())),
      ],
      primaryAction: canEdit
          ? FilledButton.icon(
              onPressed: () => BusinessesScreen.openForm(context, business),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Edit'),
            )
          : null,
      menu: [
        if (canRestore)
          DetailAction(
            label: 'Restore business',
            icon: Icons.unarchive_outlined,
            onSelected: () => BusinessActions.restore(context, business),
          ),
        if (canArchiveNow)
          DetailAction(
            label: 'Archive business',
            icon: Icons.archive_outlined,
            destructive: true,
            onSelected: () => BusinessActions.archive(context, business),
          ),
      ],
      banner: BusinessActions.canRestore(business)
          ? _HiddenBanner(
              business: business,
              onRestore: canRestore
                  ? () => BusinessActions.restore(context, business)
                  : null,
            )
          : null,
      kpis: [
        KpiItem(
          label: 'Revenue',
          value: money(summary.revenue),
          icon: Icons.trending_up,
          caption: period,
        ),
        KpiItem(
          label: 'Product cost',
          value: money(summary.productCost),
          icon: Icons.inventory_2_outlined,
        ),
        KpiItem(
          label: 'Marketing',
          value: money(summary.marketingCost),
          icon: Icons.campaign_outlined,
        ),
        KpiItem(
          label: 'Operating exp.',
          value: money(summary.operatingExpenses),
          icon: Icons.receipt_long_outlined,
        ),
        KpiItem(
          label: 'Gross profit',
          value: money(summary.grossProfit),
          icon: Icons.savings_outlined,
          tone: summary.grossProfit.isNegative ? t.error : t.success,
        ),
        KpiItem(
          label: 'Net profit',
          value: money(summary.netProfit),
          icon: Icons.account_balance_wallet_outlined,
          tone: summary.netProfit.isNegative ? t.error : t.success,
        ),
        KpiItem(
          label: 'Net margin',
          value: PercentFormatter.format(summary.netMargin),
          icon: Icons.percent,
        ),
        KpiItem(
          label: 'Orders',
          value: '${summary.orderCount}',
          icon: Icons.shopping_cart_outlined,
        ),
      ],
      activity: DetailActivityColumn(
        activityAt: business.lastActivityAt,
        comments: business.comments,
        canComment: canEdit,
        onPost: (comment) async {
          await repo.saveBusiness(
            business.copyWith(comments: [...business.comments, comment]),
            isNew: false,
          );
        },
      ),
      children: [
        _TenureBanner(business: business),
        _ProfileCard(business: business),
        _ProductsGrid(products: products, currency: currency),
        _CampaignsGrid(campaigns: campaigns, currency: currency),
        _OrdersGrid(orders: orders, currency: currency),
        _ExpensesGrid(expenses: expenses, currency: currency),
        _DealersGrid(dealers: dealers, currency: currency),
        TeamAccessCard.business(business),
      ],
    );
  }
}

/// A notice above the sections when the business is archived or inactive,
/// with a one-tap Restore for users who may edit it.
class _HiddenBanner extends StatelessWidget {
  const _HiddenBanner({required this.business, required this.onRestore});

  final Business business;
  final VoidCallback? onRestore;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final archived = business.status == EntityStatus.archived;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: t.warningSurface,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        border: Border.all(color: t.warning.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(archived ? Icons.archive_outlined : Icons.visibility_off_outlined,
              color: t.warning, size: 20),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              archived
                  ? 'This business is archived and hidden from active views.'
                  : 'This business is inactive and hidden from active views.',
              style: TextStyle(fontSize: 13.5, color: t.textPrimary),
            ),
          ),
          if (onRestore != null) ...[
            const SizedBox(width: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: onRestore,
              icon: const Icon(Icons.unarchive_outlined, size: 18),
              label: const Text('Restore'),
            ),
          ],
        ],
      ),
    );
  }
}

/// The headline tenure card: shows how long the business has been operating in
/// large type (e.g. "4 yr 3 mo"), with the trading window beneath. This is the
/// prominent element the detail page leads with.
///
/// For a closed business the span is measured to its end date and the copy
/// switches to "operated for". When no start date is recorded yet it degrades
/// to a gentle prompt rather than an empty box.
class _TenureBanner extends StatelessWidget {
  const _TenureBanner({required this.business});

  final Business business;

  @override
  Widget build(BuildContext context) {
    final closed = business.isClosed;
    final tenure = business.tenure(DateTime.now());
    final accent = closed ? context.tokens.warning : context.tokens.primary;
    final surface = closed ? context.tokens.warningSurface : context.tokens.primarySurface;

    final headline = tenure == null
        ? 'Not set'
        : (tenure.isToday ? 'Started today' : tenure.shortLabel);
    final caption = _caption(tenure, closed);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Icon(
              closed ? Icons.history_toggle_off : Icons.timelapse_outlined,
              color: accent,
              size: 26,
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  closed ? 'BUSINESS TENURE (CLOSED)' : 'BUSINESS TENURE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  headline,
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    height: 1.05,
                    color: context.tokens.textPrimary,
                  ),
                ),
                if (caption != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    caption,
                    style: TextStyle(
                        fontSize: 13, color: context.tokens.textSecondary),
                  ),
                ],
              ],
            ),
          ),
          if (tenure != null)
            _TenureBreakdown(tenure: tenure, accent: accent),
        ],
      ),
    );
  }

  /// A supporting line under the headline: the trading window, or a prompt to
  /// set a start date.
  String? _caption(TimeRemaining? tenure, bool closed) {
    if (tenure == null) {
      return 'Add a start date to track how long this business has operated.';
    }
    final start = AppDate.format(business.startDate);
    if (closed) {
      return 'Operated $start → ${AppDate.format(business.endDate)}';
    }
    return 'Trading since $start · ${tenure.totalDays} days';
  }
}

/// The years / months / days breakdown shown at the trailing edge of the tenure
/// banner on wide layouts; hidden on narrow ones to avoid crowding.
class _TenureBreakdown extends StatelessWidget {
  const _TenureBreakdown({required this.tenure, required this.accent});

  final TimeRemaining tenure;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    // Below ~520px the two-line headline + breakdown would collide; drop it.
    if (MediaQuery.sizeOf(context).width < 520) return const SizedBox.shrink();
    final units = <(int, String)>[
      (tenure.years, tenure.years == 1 ? 'year' : 'years'),
      (tenure.months, tenure.months == 1 ? 'month' : 'months'),
      (tenure.days, tenure.days == 1 ? 'day' : 'days'),
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (value, label) in units)
          Padding(
            padding: const EdgeInsets.only(left: AppSpacing.lg),
            child: Column(
              children: [
                Text(
                  '$value',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                      fontSize: 11, color: context.tokens.textSecondary),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Status pill for the operational [BusinessLifecycle] (green = active,
/// warning = closed) — distinct from the entity visibility badge.
class _LifecycleBadge extends StatelessWidget {
  const _LifecycleBadge({required this.lifecycle});

  final BusinessLifecycle lifecycle;

  @override
  Widget build(BuildContext context) => StatusBadge(
        label: lifecycle.label,
        tone: lifecycle.isClosed ? BadgeTone.warning : BadgeTone.success,
      );
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.business});
  final Business business;

  @override
  Widget build(BuildContext context) {
    final fields = <DetailField>[
      DetailField('Business ID', business.id, Icons.badge_outlined),
      DetailField('Type', business.type, Icons.category_outlined),
      DetailField('Founded By', business.foundedBy, Icons.emoji_people_outlined),
      DetailField('Owned By', business.ownedBy, Icons.person_outline),
      DetailField('Start Date', AppDate.format(business.startDate),
          Icons.event_available_outlined),
      if (business.isClosed)
        DetailField('End Date', AppDate.format(business.endDate),
            Icons.event_busy_outlined),
      DetailField('Company Size', business.size.label, Icons.groups_outlined),
      DetailField('Country', business.country, Icons.public),
      DetailField('Currency',
          '${business.currency.name.toUpperCase()} (${business.currency.symbol})',
          Icons.payments_outlined),
      DetailField('Website', business.website, Icons.link, isLink: true),
    ];
    final social = business.socialLinks;

    return SectionCard(
      title: 'Business Profile',
      trailing: _LifecycleBadge(lifecycle: business.lifecycle),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DetailGrid(fields: fields),
          if (business.description.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.notes_outlined,
                    size: 18, color: context.tokens.textTertiary),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Description',
                          style: TextStyle(
                              fontSize: 12, color: context.tokens.textSecondary)),
                      const SizedBox(height: 2),
                      Text(business.description,
                          style: const TextStyle(fontSize: 14, height: 1.4)),
                    ],
                  ),
                ),
                CopyButton(label: 'description', value: business.description),
              ],
            ),
          ],
          if (social.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            Text('Online presence',
                style: TextStyle(
                    fontSize: 12, color: context.tokens.textSecondary)),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final (label, url) in social)
                  OutlinedButton.icon(
                    onPressed: () => openExternalUrl(url),
                    icon: const Icon(Icons.open_in_new, size: 15),
                    label: Text(label),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.tokens.primary,
                      side: BorderSide(color: context.tokens.primary),
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ProductsGrid extends StatelessWidget {
  const _ProductsGrid({required this.products, required this.currency});

  final List<Product> products;
  final CurrencyCode currency;

  @override
  Widget build(BuildContext context) {
    return AppDataGrid<Product>(
      gridId: 'business.products',
      title: 'Products',
      subtitle: '${products.length} associated',
      rows: products,
      rowKey: (p) => p.id,
      pageSize: 5,
      exportName: 'business-products',
      searchHint: 'Search products by name, price or status…',
      searchText: (p) =>
          '${p.name} ${p.buyingPrice.minor} ${p.sellingPrice.minor} ${p.status.label}',
      emptyTitle: 'No products',
      emptyMessage: 'Products for this business will appear here.',
      emptyIcon: Icons.inventory_2_outlined,
      onRowTap: (p) => context.go(Routes.productDetailPath(p.id)),
      columns: [
        GridColumn<Product>(
          id: 'name',
          label: 'Product',
          flex: 2,
          cardRole: CardRole.title,
          cell: (p) => Text(p.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          sortValue: (p) => p.name.toLowerCase(),
          exportValue: (p) => p.name,
        ),
        GridColumn<Product>(
          id: 'buying',
          label: 'Buying',
          numeric: true,
          cardRole: CardRole.metric,
          cell: (p) => CurrencyText(p.buyingPrice, currency: currency),
          sortValue: (p) => p.buyingPrice.minor,
          exportValue: (p) => p.buyingPrice.major.toStringAsFixed(2),
        ),
        GridColumn<Product>(
          id: 'selling',
          label: 'Selling',
          numeric: true,
          cardRole: CardRole.metric,
          cell: (p) => CurrencyText(p.sellingPrice, currency: currency),
          sortValue: (p) => p.sellingPrice.minor,
          exportValue: (p) => p.sellingPrice.major.toStringAsFixed(2),
        ),
        GridColumn<Product>(
          id: 'status',
          label: 'Status',
          cardRole: CardRole.badge,
          cell: (p) => StatusBadge.entity(p.status),
          sortValue: (p) => p.status.label,
          exportValue: (p) => p.status.label,
        ),
      ],
    );
  }
}

class _CampaignsGrid extends StatelessWidget {
  const _CampaignsGrid({required this.campaigns, required this.currency});

  final List<Campaign> campaigns;
  final CurrencyCode currency;

  @override
  Widget build(BuildContext context) {
    return AppDataGrid<Campaign>(
      gridId: 'business.campaigns',
      title: 'Campaigns',
      subtitle: '${campaigns.length} associated',
      rows: campaigns,
      rowKey: (c) => c.id,
      pageSize: 5,
      exportName: 'business-campaigns',
      searchHint: 'Search campaigns by name, platform or status…',
      searchText: (c) =>
          '${c.name} ${c.platform.label} ${c.amountInvested.minor} ${c.status.label}',
      emptyTitle: 'No campaigns',
      emptyMessage: 'Campaigns for this business will appear here.',
      emptyIcon: Icons.campaign_outlined,
      onRowTap: (c) => context.go(Routes.campaignDetailPath(c.id)),
      columns: [
        GridColumn<Campaign>(
          id: 'name',
          label: 'Campaign',
          flex: 2,
          cardRole: CardRole.title,
          cell: (c) => Text(c.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          sortValue: (c) => c.name.toLowerCase(),
          exportValue: (c) => c.name,
        ),
        GridColumn<Campaign>(
          id: 'platform',
          label: 'Platform',
          cardRole: CardRole.meta,
          cell: (c) =>
              StatusBadge(label: c.platform.label, tone: BadgeTone.info),
          sortValue: (c) => c.platform.label,
          exportValue: (c) => c.platform.label,
        ),
        GridColumn<Campaign>(
          id: 'spend',
          label: 'Spend',
          numeric: true,
          cardRole: CardRole.metric,
          cell: (c) => CurrencyText(c.amountInvested, currency: currency),
          sortValue: (c) => c.amountInvested.minor,
          exportValue: (c) => c.amountInvested.major.toStringAsFixed(2),
        ),
        GridColumn<Campaign>(
          id: 'status',
          label: 'Status',
          cardRole: CardRole.badge,
          cell: (c) => StatusBadge.campaign(c.status),
          sortValue: (c) => c.status.label,
          exportValue: (c) => c.status.label,
        ),
      ],
    );
  }
}

class _OrdersGrid extends StatelessWidget {
  const _OrdersGrid({required this.orders, required this.currency});

  final List<Order> orders;
  final CurrencyCode currency;

  static final _epoch = DateTime.fromMillisecondsSinceEpoch(0);
  static DateTime _dateOf(Order o) =>
      o.orderDate ?? o.audit.createdAt ?? _epoch;

  @override
  Widget build(BuildContext context) {
    final sorted = [...orders]..sort((a, b) => _dateOf(b).compareTo(_dateOf(a)));
    return AppDataGrid<Order>(
      gridId: 'business.orders',
      title: 'Orders',
      subtitle: '${orders.length} total',
      rows: sorted,
      rowKey: (o) => o.id,
      pageSize: 5,
      exportName: 'business-orders',
      searchHint: 'Search orders by ID, product or status…',
      searchText: (o) => '${o.id} ${o.productName} '
          '${AppDate.short(_dateOf(o))} ${o.recognisedRevenue.minor} '
          '${o.status.label}',
      emptyTitle: 'No orders',
      emptyMessage: 'Orders for this business will appear here.',
      emptyIcon: Icons.receipt_long_outlined,
      onRowTap: (o) => context.go(Routes.orderDetailPath(o.id)),
      columns: [
        GridColumn<Order>(
          id: 'id',
          label: 'Order ID',
          minWidth: 110,
          cardRole: CardRole.subtitle,
          cell: (o) => Text(o.id,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          sortValue: (o) => o.id,
          exportValue: (o) => o.id,
        ),
        GridColumn<Order>(
          id: 'product',
          label: 'Product',
          flex: 2,
          cardRole: CardRole.title,
          cell: (o) => Text(o.productName,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          sortValue: (o) => o.productName.toLowerCase(),
          exportValue: (o) => o.productName,
        ),
        GridColumn<Order>(
          id: 'date',
          label: 'Date',
          minWidth: 110,
          cardRole: CardRole.meta,
          cell: (o) => Text(AppDate.short(_dateOf(o))),
          sortValue: (o) => _dateOf(o).millisecondsSinceEpoch,
          exportValue: (o) => AppDate.format(_dateOf(o)),
        ),
        GridColumn<Order>(
          id: 'revenue',
          label: 'Revenue',
          numeric: true,
          cardRole: CardRole.metric,
          cell: (o) => CurrencyText(o.recognisedRevenue, currency: currency),
          sortValue: (o) => o.recognisedRevenue.minor,
          exportValue: (o) => o.recognisedRevenue.major.toStringAsFixed(2),
        ),
        GridColumn<Order>(
          id: 'status',
          label: 'Status',
          minWidth: 120,
          cardRole: CardRole.badge,
          cell: (o) => StatusBadge.order(o.status),
          sortValue: (o) => o.status.label,
          exportValue: (o) => o.status.label,
        ),
      ],
    );
  }
}

class _ExpensesGrid extends StatelessWidget {
  const _ExpensesGrid({required this.expenses, required this.currency});

  final List<Expense> expenses;
  final CurrencyCode currency;

  @override
  Widget build(BuildContext context) {
    return AppDataGrid<Expense>(
      gridId: 'business.expenses',
      title: 'Expenses',
      subtitle: '${expenses.length} associated',
      rows: expenses,
      rowKey: (e) => e.id,
      pageSize: 5,
      exportName: 'business-expenses',
      searchHint: 'Search expenses by name, category or frequency…',
      searchText: (e) =>
          '${e.name} ${e.category.label} ${e.amount.minor} ${e.frequency.label}',
      emptyTitle: 'No expenses',
      emptyMessage: 'Expenses for this business will appear here.',
      emptyIcon: Icons.receipt_outlined,
      onRowTap: (e) => context.go(Routes.expenseDetailPath(e.id)),
      columns: [
        GridColumn<Expense>(
          id: 'name',
          label: 'Expense',
          flex: 2,
          cardRole: CardRole.title,
          cell: (e) => Text(e.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          sortValue: (e) => e.name.toLowerCase(),
          exportValue: (e) => e.name,
        ),
        GridColumn<Expense>(
          id: 'category',
          label: 'Category',
          cardRole: CardRole.badge,
          cell: (e) =>
              StatusBadge(label: e.category.label, tone: BadgeTone.neutral),
          sortValue: (e) => e.category.label,
          exportValue: (e) => e.category.label,
        ),
        GridColumn<Expense>(
          id: 'amount',
          label: 'Amount',
          numeric: true,
          cardRole: CardRole.metric,
          cell: (e) => CurrencyText(e.amount, currency: currency),
          sortValue: (e) => e.amount.minor,
          exportValue: (e) => e.amount.major.toStringAsFixed(2),
        ),
        GridColumn<Expense>(
          id: 'frequency',
          label: 'Frequency',
          cardRole: CardRole.meta,
          cell: (e) => Text(e.frequency.label),
          sortValue: (e) => e.frequency.label,
          exportValue: (e) => e.frequency.label,
        ),
      ],
    );
  }
}

class _DealersGrid extends StatelessWidget {
  const _DealersGrid({required this.dealers, required this.currency});

  final List<Dealer> dealers;
  final CurrencyCode currency;

  @override
  Widget build(BuildContext context) {
    return AppDataGrid<Dealer>(
      gridId: 'business.dealers',
      title: 'Dealers',
      subtitle: '${dealers.length} associated',
      rows: dealers,
      rowKey: (d) => d.id,
      pageSize: 5,
      exportName: 'business-dealers',
      searchHint: 'Search dealers by name, frequency or status…',
      searchText: (d) =>
          '${d.name} ${d.cost.minor} ${d.costFrequency.label} ${d.status.label}',
      emptyTitle: 'No dealers',
      emptyMessage: 'Dealers for this business will appear here.',
      emptyIcon: Icons.handshake_outlined,
      onRowTap: (d) => context.go(Routes.dealerDetailPath(d.id)),
      columns: [
        GridColumn<Dealer>(
          id: 'name',
          label: 'Dealer',
          flex: 2,
          cardRole: CardRole.title,
          cell: (d) => Text(d.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          sortValue: (d) => d.name.toLowerCase(),
          exportValue: (d) => d.name,
        ),
        GridColumn<Dealer>(
          id: 'cost',
          label: 'Cost',
          numeric: true,
          cardRole: CardRole.metric,
          cell: (d) => CurrencyText(d.cost, currency: currency),
          sortValue: (d) => d.cost.minor,
          exportValue: (d) => d.cost.major.toStringAsFixed(2),
        ),
        GridColumn<Dealer>(
          id: 'frequency',
          label: 'Frequency',
          cardRole: CardRole.meta,
          cell: (d) => Text(d.costFrequency.label),
          sortValue: (d) => d.costFrequency.label,
          exportValue: (d) => d.costFrequency.label,
        ),
        GridColumn<Dealer>(
          id: 'status',
          label: 'Status',
          cardRole: CardRole.badge,
          cell: (d) => StatusBadge.entity(d.status),
          sortValue: (d) => d.status.label,
          exportValue: (d) => d.status.label,
        ),
      ],
    );
  }
}
