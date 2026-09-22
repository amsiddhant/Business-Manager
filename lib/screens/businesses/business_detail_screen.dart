import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/app_exception.dart';
import '../../core/enums.dart';
import '../../core/permissions.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/money.dart';
import '../../models/app_user.dart';
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
import '../../widgets/common/data_table_card.dart';
import '../../widgets/common/detail_widgets.dart';
import '../../widgets/common/initials_avatar.dart';
import '../../widgets/common/page_header.dart';
import '../../widgets/common/search_field.dart';
import '../../widgets/common/state_views.dart';
import '../../widgets/common/status_badge.dart';
import 'businesses_screen.dart';

/// A full-screen business profile: identity + social links on the left, all
/// mapped entities (products, campaigns, orders, expenses, dealers) scoped to
/// this business, plus a team-access roster and a comment thread on the right.
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

    if (data.loading && !data.loaded) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(title: 'Business'),
          SizedBox(height: 48),
          LoadingView(),
        ],
      );
    }

    final business = data.businessById(businessId);
    if (business == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(
            title: 'Business',
            actions: [
              OutlinedButton.icon(
                onPressed: () => context.go(Routes.businesses),
                icon: const Icon(Icons.arrow_back, size: 18),
                label: const Text('Back to Businesses'),
              ),
            ],
          ),
          const SizedBox(height: 48),
          const EmptyView(
            icon: Icons.search_off,
            title: 'Business not found',
            message:
                'This business may have been removed or is not accessible.',
          ),
        ],
      );
    }

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

    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TenureBanner(business: business),
        const SizedBox(height: AppSpacing.lg),
        _ProfileCard(business: business),
        const SizedBox(height: AppSpacing.lg),
        _FinancialSummaryCard(
          summary: summary,
          currency: currency,
          period: filter.periodLabel,
        ),
        const SizedBox(height: AppSpacing.lg),
        _ProductsCard(products: products, currency: currency),
        const SizedBox(height: AppSpacing.lg),
        _CampaignsCard(campaigns: campaigns, currency: currency),
        const SizedBox(height: AppSpacing.lg),
        _OrdersCard(orders: orders, currency: currency),
        const SizedBox(height: AppSpacing.lg),
        _ExpensesCard(expenses: expenses, currency: currency),
        const SizedBox(height: AppSpacing.lg),
        _DealersCard(dealers: dealers, currency: currency),
        const SizedBox(height: AppSpacing.lg),
        _TeamAccessCard(business: business),
      ],
    );

    final repo = appState.repository;
    final right = DetailActivityColumn(
      activityAt: business.lastActivityAt,
      comments: business.comments,
      canComment: canEdit,
      onPost: (comment) async {
        await repo.saveBusiness(
          business.copyWith(comments: [...business.comments, comment]),
          isNew: false,
        );
        await data.refresh();
      },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: business.name,
          subtitle: '${business.id}'
              '${business.type.isEmpty ? '' : ' · ${business.type}'}',
          actions: [
            OutlinedButton.icon(
              onPressed: () => context.go(Routes.businesses),
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('Back'),
            ),
            if (canEdit)
              ElevatedButton.icon(
                onPressed: () => BusinessesScreen.openForm(context, business),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit'),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        DetailTwoColumn(left: left, right: right),
      ],
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
    final accent = closed ? AppColors.warning : AppColors.primary;
    final surface = closed ? AppColors.warningSurface : AppColors.primarySurface;

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
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    height: 1.05,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (caption != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    caption,
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textSecondary),
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
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSecondary),
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
          Row(
            children: [
              InitialsAvatar(name: business.name, size: 48),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(business.name,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                    if (business.type.isNotEmpty)
                      Text(business.type,
                          style: const TextStyle(
                              fontSize: 13, color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          DetailGrid(fields: fields),
          if (business.description.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.notes_outlined,
                    size: 18, color: AppColors.textTertiary),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Description',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.textSecondary)),
                      const SizedBox(height: 2),
                      Text(business.description,
                          style: const TextStyle(
                              fontSize: 14, height: 1.4)),
                    ],
                  ),
                ),
                CopyButton(label: 'description', value: business.description),
              ],
            ),
          ],
          if (social.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            const Text('Social Media',
                style: TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
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
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
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

class _FinancialSummaryCard extends StatelessWidget {
  const _FinancialSummaryCard({
    required this.summary,
    required this.currency,
    required this.period,
  });

  final ProfitSummary summary;
  final CurrencyCode currency;
  final String period;

  @override
  Widget build(BuildContext context) {
    final metrics = <_Metric>[
      _Metric('Revenue', MoneyFormatter.format(summary.revenue, currency)),
      _Metric('Product Cost',
          MoneyFormatter.format(summary.productCost, currency)),
      _Metric('Marketing',
          MoneyFormatter.format(summary.marketingCost, currency)),
      _Metric('Operating Exp.',
          MoneyFormatter.format(summary.operatingExpenses, currency)),
      _Metric('Gross Profit',
          MoneyFormatter.format(summary.grossProfit, currency),
          tone: summary.grossProfit.isNegative
              ? AppColors.error
              : AppColors.success),
      _Metric('Net Profit', MoneyFormatter.format(summary.netProfit, currency),
          tone: summary.netProfit.isNegative
              ? AppColors.error
              : AppColors.success),
      _Metric('Net Margin', PercentFormatter.format(summary.netMargin)),
      _Metric('Orders', '${summary.orderCount}'),
    ];

    return SectionCard(
      title: 'Financial Summary',
      subtitle: 'For $period',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = MediaQuery.sizeOf(context).width < 700 ? 2 : 4;
          const gap = AppSpacing.md;
          final tileWidth =
              (constraints.maxWidth - gap * (columns - 1)) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final m in metrics)
                SizedBox(width: tileWidth, child: _MetricTile(metric: m)),
            ],
          );
        },
      ),
    );
  }
}

class _Metric {
  const _Metric(this.label, this.value, {this.tone});
  final String label;
  final String value;
  final Color? tone;
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.metric});
  final _Metric metric;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(metric.label,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Text(
            metric.value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: metric.tone ?? AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductsCard extends StatefulWidget {
  const _ProductsCard({required this.products, required this.currency});

  final List<Product> products;
  final CurrencyCode currency;

  @override
  State<_ProductsCard> createState() => _ProductsCardState();
}

class _ProductsCardState extends State<_ProductsCard> {
  String _productSearch = '';

  @override
  Widget build(BuildContext context) {
    final products = widget.products;
    final currency = widget.currency;
    return SectionCard(
      title: 'Products',
      subtitle: '${products.length} associated',
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            child: SearchField(
              hintText: 'Search products by name, price or status…',
              onChanged: (v) => setState(() => _productSearch = v),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppDataTable<Product>(
            rows: products,
            rowsPerPage: 5,
            searchText: _productSearch,
            searchableText: (p) =>
                '${p.name} ${p.buyingPrice.minor} ${p.sellingPrice.minor} ${p.status.label}',
            emptyTitle: 'No products',
            emptyMessage: 'Products for this business will appear here.',
            onRowTap: (p) => context.go(Routes.productDetailPath(p.id)),
            columns: [
              AppColumn(
                label: 'Product',
                cell: (p) => Text(p.name,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                sortValue: (p) => p.name.toLowerCase(),
              ),
              AppColumn(
                label: 'Buying',
                numeric: true,
                cell: (p) => CurrencyText(p.buyingPrice, currency: currency),
                sortValue: (p) => p.buyingPrice.minor,
              ),
              AppColumn(
                label: 'Selling',
                numeric: true,
                cell: (p) => CurrencyText(p.sellingPrice, currency: currency),
                sortValue: (p) => p.sellingPrice.minor,
              ),
              AppColumn(
                label: 'Status',
                cell: (p) => StatusBadge.entity(p.status),
                sortValue: (p) => p.status.label,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CampaignsCard extends StatefulWidget {
  const _CampaignsCard({required this.campaigns, required this.currency});

  final List<Campaign> campaigns;
  final CurrencyCode currency;

  @override
  State<_CampaignsCard> createState() => _CampaignsCardState();
}

class _CampaignsCardState extends State<_CampaignsCard> {
  String _campaignSearch = '';

  @override
  Widget build(BuildContext context) {
    final campaigns = widget.campaigns;
    final currency = widget.currency;
    return SectionCard(
      title: 'Campaigns',
      subtitle: '${campaigns.length} associated',
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            child: SearchField(
              hintText: 'Search campaigns by name, platform or status…',
              onChanged: (v) => setState(() => _campaignSearch = v),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppDataTable<Campaign>(
            rows: campaigns,
            rowsPerPage: 5,
            searchText: _campaignSearch,
            searchableText: (c) =>
                '${c.name} ${c.platform.label} ${c.amountInvested.minor} ${c.status.label}',
            emptyTitle: 'No campaigns',
            emptyMessage: 'Campaigns for this business will appear here.',
            onRowTap: (c) => context.go(Routes.campaignDetailPath(c.id)),
            columns: [
              AppColumn(
                label: 'Campaign',
                cell: (c) => Text(c.name,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
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
                cell: (c) => CurrencyText(c.amountInvested, currency: currency),
                sortValue: (c) => c.amountInvested.minor,
              ),
              AppColumn(
                label: 'Status',
                cell: (c) => StatusBadge.campaign(c.status),
                sortValue: (c) => c.status.label,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OrdersCard extends StatefulWidget {
  const _OrdersCard({required this.orders, required this.currency});

  final List<Order> orders;
  final CurrencyCode currency;

  static final _epoch = DateTime.fromMillisecondsSinceEpoch(0);
  static DateTime _dateOf(Order o) =>
      o.orderDate ?? o.audit.createdAt ?? _epoch;

  @override
  State<_OrdersCard> createState() => _OrdersCardState();
}

class _OrdersCardState extends State<_OrdersCard> {
  String _orderSearch = '';

  @override
  Widget build(BuildContext context) {
    final orders = widget.orders;
    final currency = widget.currency;
    final sorted = [...orders]
      ..sort((a, b) =>
          _OrdersCard._dateOf(b).compareTo(_OrdersCard._dateOf(a)));
    return SectionCard(
      title: 'Orders',
      subtitle: '${orders.length} total',
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            child: SearchField(
              hintText: 'Search orders by ID, product or status…',
              onChanged: (v) => setState(() => _orderSearch = v),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppDataTable<Order>(
            rows: sorted,
            rowsPerPage: 5,
            searchText: _orderSearch,
            searchableText: (o) =>
                '${o.id} ${o.productName} ${AppDate.short(_OrdersCard._dateOf(o))} '
                '${o.recognisedRevenue.minor} ${o.status.label}',
            emptyTitle: 'No orders',
            emptyMessage: 'Orders for this business will appear here.',
            onRowTap: (o) => context.go(Routes.orderDetailPath(o.id)),
            columns: [
              AppColumn(
                label: 'Order ID',
                cell: (o) => Text(o.id,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                sortValue: (o) => o.id,
              ),
              AppColumn(
                label: 'Product',
                cell: (o) => Text(o.productName),
                sortValue: (o) => o.productName.toLowerCase(),
              ),
              AppColumn(
                label: 'Date',
                cell: (o) => Text(AppDate.short(_OrdersCard._dateOf(o))),
                sortValue: (o) =>
                    _OrdersCard._dateOf(o).millisecondsSinceEpoch,
              ),
              AppColumn(
                label: 'Revenue',
                numeric: true,
                cell: (o) =>
                    CurrencyText(o.recognisedRevenue, currency: currency),
                sortValue: (o) => o.recognisedRevenue.minor,
              ),
              AppColumn(
                label: 'Status',
                cell: (o) => StatusBadge.order(o.status),
                sortValue: (o) => o.status.label,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ExpensesCard extends StatefulWidget {
  const _ExpensesCard({required this.expenses, required this.currency});

  final List<Expense> expenses;
  final CurrencyCode currency;

  @override
  State<_ExpensesCard> createState() => _ExpensesCardState();
}

class _ExpensesCardState extends State<_ExpensesCard> {
  String _expenseSearch = '';

  @override
  Widget build(BuildContext context) {
    final expenses = widget.expenses;
    final currency = widget.currency;
    return SectionCard(
      title: 'Expenses',
      subtitle: '${expenses.length} associated',
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            child: SearchField(
              hintText: 'Search expenses by name, category or frequency…',
              onChanged: (v) => setState(() => _expenseSearch = v),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppDataTable<Expense>(
            rows: expenses,
            rowsPerPage: 5,
            searchText: _expenseSearch,
            searchableText: (e) =>
                '${e.name} ${e.category.label} ${e.amount.minor} ${e.frequency.label}',
            emptyTitle: 'No expenses',
            emptyMessage: 'Expenses for this business will appear here.',
            onRowTap: (e) => context.go(Routes.expenseDetailPath(e.id)),
            columns: [
              AppColumn(
                label: 'Expense',
                cell: (e) => Text(e.name,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                sortValue: (e) => e.name.toLowerCase(),
              ),
              AppColumn(
                label: 'Category',
                cell: (e) => StatusBadge(
                    label: e.category.label, tone: BadgeTone.neutral),
                sortValue: (e) => e.category.label,
              ),
              AppColumn(
                label: 'Amount',
                numeric: true,
                cell: (e) => CurrencyText(e.amount, currency: currency),
                sortValue: (e) => e.amount.minor,
              ),
              AppColumn(
                label: 'Frequency',
                cell: (e) => Text(e.frequency.label),
                sortValue: (e) => e.frequency.label,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DealersCard extends StatefulWidget {
  const _DealersCard({required this.dealers, required this.currency});

  final List<Dealer> dealers;
  final CurrencyCode currency;

  @override
  State<_DealersCard> createState() => _DealersCardState();
}

class _DealersCardState extends State<_DealersCard> {
  String _dealerSearch = '';

  @override
  Widget build(BuildContext context) {
    final dealers = widget.dealers;
    final currency = widget.currency;
    return SectionCard(
      title: 'Dealers',
      subtitle: '${dealers.length} associated',
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            child: SearchField(
              hintText: 'Search dealers by name, frequency or status…',
              onChanged: (v) => setState(() => _dealerSearch = v),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppDataTable<Dealer>(
            rows: dealers,
            rowsPerPage: 5,
            searchText: _dealerSearch,
            searchableText: (d) =>
                '${d.name} ${d.cost.minor} ${d.costFrequency.label} ${d.status.label}',
            emptyTitle: 'No dealers',
            emptyMessage: 'Dealers for this business will appear here.',
            onRowTap: (d) => context.go(Routes.dealerDetailPath(d.id)),
            columns: [
              AppColumn(
                label: 'Dealer',
                cell: (d) => Text(d.name,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                sortValue: (d) => d.name.toLowerCase(),
              ),
              AppColumn(
                label: 'Cost',
                numeric: true,
                cell: (d) => CurrencyText(d.cost, currency: currency),
                sortValue: (d) => d.cost.minor,
              ),
              AppColumn(
                label: 'Frequency',
                cell: (d) => Text(d.costFrequency.label),
                sortValue: (d) => d.costFrequency.label,
              ),
              AppColumn(
                label: 'Status',
                cell: (d) => StatusBadge.entity(d.status),
                sortValue: (d) => d.status.label,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The people with access to this business, grouped Owner / Admins / Users.
///
/// Enumerating user profiles is Owner-only in the Firestore rules, so for a
/// non-owner viewer we gate the roster behind an Owner-only note rather than
/// issuing a `list` query that would be rejected ("rules are not filters").
class _TeamAccessCard extends StatefulWidget {
  const _TeamAccessCard({required this.business});

  final Business business;

  @override
  State<_TeamAccessCard> createState() => _TeamAccessCardState();
}

class _TeamAccessCardState extends State<_TeamAccessCard> {
  Future<List<AppUser>>? _rosterFuture;

  @override
  void initState() {
    super.initState();
    final appState = context.read<AppState>();
    if (appState.currentUser?.isOwner ?? false) {
      _rosterFuture = appState.repository.fetchUsers();
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final isOwnerViewer = appState.currentUser?.isOwner ?? false;

    return SectionCard(
      title: 'Team Access',
      subtitle: 'Owners, admins & users with access to this business',
      child: !isOwnerViewer
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Text(
                'The team roster (admins & users) is visible to Owners only.',
                style:
                    TextStyle(fontSize: 12, color: AppColors.textTertiary),
              ),
            )
          : FutureBuilder<List<AppUser>>(
              future: _rosterFuture,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                }
                if (snap.hasError) {
                  return Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                    child: Text(ErrorMapper.friendly(snap.error!),
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.textSecondary)),
                  );
                }
                final roster = snap.data ?? const <AppUser>[];
                final b = widget.business;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _RoleGroup(
                      label: 'Owner',
                      icon: Icons.shield_outlined,
                      people:
                          roster.where((u) => u.role == UserRole.owner).toList(),
                    ),
                    _RoleGroup(
                      label: 'Admins',
                      icon: Icons.admin_panel_settings_outlined,
                      people: roster
                          .where((u) =>
                              u.role == UserRole.admin &&
                              u.assignedBusinessIds.contains(b.id))
                          .toList(),
                    ),
                    _RoleGroup(
                      label: 'Users',
                      icon: Icons.person_outline,
                      people: roster
                          .where((u) =>
                              u.role == UserRole.user &&
                              u.assignedBusinessIds.contains(b.id))
                          .toList(),
                    ),
                  ],
                );
              },
            ),
    );
  }
}

class _RoleGroup extends StatelessWidget {
  const _RoleGroup({
    required this.label,
    required this.icon,
    required this.people,
  });

  final String label;
  final IconData icon;
  final List<AppUser> people;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(left: AppSpacing.lg),
        dense: true,
        leading: Icon(icon, size: 18, color: AppColors.textTertiary),
        title: Text('$label (${people.length})',
            style:
                const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        children: people.isEmpty
            ? const [
                Padding(
                  padding: EdgeInsets.only(
                      left: AppSpacing.lg, bottom: AppSpacing.sm),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('None',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textTertiary)),
                  ),
                ),
              ]
            : [for (final p in people) _PersonTile(person: p)],
      ),
    );
  }
}

class _PersonTile extends StatelessWidget {
  const _PersonTile({required this.person});

  final AppUser person;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          InitialsAvatar(name: person.name, size: 28),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(person.name.isEmpty ? person.loginId : person.name,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500)),
                if (person.email.isNotEmpty)
                  Text(person.email,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textTertiary)),
              ],
            ),
          ),
          StatusBadge.role(person.role),
        ],
      ),
    );
  }
}
