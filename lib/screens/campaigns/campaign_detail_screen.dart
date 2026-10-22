import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/enums.dart';
import '../../core/permissions.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/theme_x.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/money.dart';
import '../../state/app_state.dart';
import '../../state/data_controller.dart';
import '../../widgets/common/app_card.dart';
import '../../widgets/common/comment_thread.dart';
import '../../widgets/common/detail_widgets.dart';
import '../../widgets/common/status_badge.dart';
import '../../widgets/layout/detail_page.dart';
import '../../widgets/layout/kpi_strip.dart';
import 'campaigns_screen.dart';

/// A single campaign view: performance metrics, the linked product & business,
/// and a comment thread. All linked entities are resolved through the
/// access-scoped [DataController], so nothing outside the viewer's reach shows.
class CampaignDetailScreen extends StatelessWidget {
  const CampaignDetailScreen({super.key, required this.campaignId});

  final String campaignId;

  static String _count(int n) => NumberFormat.decimalPattern('en_IN').format(n);

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataController>();
    final appState = context.watch<AppState>();
    final user = appState.currentUser;
    void back() => context.go(Routes.campaigns);

    if (data.loading && !data.loaded) {
      return DetailPage.loading(
          title: 'Campaign', onBack: back, backLabel: 'Campaigns');
    }

    final campaign = data.campaignById(campaignId);
    if (campaign == null) {
      return DetailPage.notFound(
        title: 'Campaign',
        onBack: back,
        backLabel: 'Campaigns',
        message: 'This campaign may have been removed or is not accessible.',
      );
    }

    final t = context.tokens;
    final business = data.businessById(campaign.businessId);
    final product = data.productById(campaign.productId);
    final currency = business?.currency ?? CurrencyCode.inr;
    final canCreate = user?.can(Permission.createCampaign) ?? false;
    final canEdit = user?.can(Permission.editCampaign) ?? false;
    final canDelete = user?.can(Permission.deleteCampaign) ?? false;
    final repo = appState.repository;
    String money(Money m) => MoneyFormatter.format(m, currency);
    final budgetUsed = campaign.budget.isPositive
        ? campaign.amountInvested.minor / campaign.budget.minor * 100
        : null;

    return DetailPage(
      title: campaign.name,
      subtitle: '${campaign.id} · ${campaign.platform.label}',
      icon: Icons.campaign_outlined,
      status: StatusBadge.campaign(campaign.status),
      backLabel: 'Campaigns',
      onBack: back,
      meta: [
        if (product != null)
          DetailMeta(Icons.inventory_2_outlined, product.name,
              tooltip: 'Open product',
              onTap: () => context.go(Routes.productDetailPath(product.id))),
        if (business != null)
          DetailMeta(Icons.business_outlined, business.name,
              tooltip: 'Open business',
              onTap: () => context.go(Routes.businessDetailPath(business.id))),
        DetailMeta(Icons.ads_click, campaign.platform.label,
            tooltip: 'Platform'),
        if (campaign.type.isNotEmpty)
          DetailMeta(Icons.label_outline, campaign.type, tooltip: 'Type'),
        if (campaign.startDate != null)
          DetailMeta(
            Icons.event_outlined,
            campaign.endDate == null
                ? 'From ${AppDate.format(campaign.startDate)}'
                : '${AppDate.format(campaign.startDate)} – '
                    '${AppDate.format(campaign.endDate)}',
            tooltip: 'Run dates',
          ),
        if (campaign.url.isNotEmpty)
          DetailMeta(Icons.open_in_new, 'Campaign page',
              tooltip: 'Open campaign URL',
              onTap: () => openExternalUrl(campaign.url)),
      ],
      primaryAction: canEdit
          ? FilledButton.icon(
              onPressed: () => CampaignsScreen.openForm(
                  context, campaign, campaign.businessId),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Edit'),
            )
          : null,
      menu: [
        if (canCreate)
          DetailAction(
            label: 'Duplicate',
            icon: Icons.copy_all_outlined,
            onSelected: () => CampaignActions.duplicate(context, campaign),
          ),
        if (canEdit && campaign.status != CampaignStatus.active)
          DetailAction(
            label: 'Mark active',
            icon: Icons.play_circle_outline,
            onSelected: () => CampaignActions.setStatus(
                context, campaign, CampaignStatus.active),
          ),
        if (canEdit && campaign.status == CampaignStatus.active)
          DetailAction(
            label: 'Pause',
            icon: Icons.pause_circle_outline,
            onSelected: () => CampaignActions.setStatus(
                context, campaign, CampaignStatus.paused),
          ),
        if (canEdit &&
            campaign.status != CampaignStatus.completed &&
            campaign.status != CampaignStatus.cancelled)
          DetailAction(
            label: 'Mark completed',
            icon: Icons.check_circle_outline,
            onSelected: () => CampaignActions.setStatus(
                context, campaign, CampaignStatus.completed),
          ),
        if (canDelete)
          DetailAction(
            label: 'Delete campaign',
            icon: Icons.delete_outline,
            destructive: true,
            onSelected: () async {
              if (await CampaignActions.delete(context, campaign) &&
                  context.mounted) {
                back();
              }
            },
          ),
      ],
      kpis: [
        KpiItem(
          label: 'Budget',
          value: money(campaign.budget),
          icon: Icons.account_balance_wallet_outlined,
        ),
        KpiItem(
          label: 'Amount Invested',
          value: money(campaign.amountInvested),
          icon: Icons.payments_outlined,
          caption: budgetUsed == null
              ? null
              : '${budgetUsed.toStringAsFixed(0)}% of budget',
          tone: budgetUsed != null && budgetUsed > 100 ? t.error : null,
        ),
        KpiItem(
          label: 'Impressions',
          value: _count(campaign.impressions),
          icon: Icons.visibility_outlined,
        ),
        KpiItem(
          label: 'Clicks',
          value: _count(campaign.clicks),
          icon: Icons.ads_click,
        ),
        KpiItem(
          label: 'Conversions',
          value: _count(campaign.conversions),
          icon: Icons.task_alt,
        ),
        KpiItem(
          label: 'CTR',
          value: PercentFormatter.format(campaign.ctr),
          icon: Icons.percent,
          tooltip: 'Click-through rate: clicks ÷ impressions.',
        ),
        KpiItem(
          label: 'Conv. Rate',
          value: PercentFormatter.format(campaign.conversionRate),
          icon: Icons.trending_up,
          tooltip: 'Conversion rate: conversions ÷ clicks.',
        ),
        KpiItem(
          label: 'Type',
          value: campaign.type.isEmpty ? '—' : campaign.type,
          icon: Icons.label_outline,
        ),
      ],
      activity: DetailActivityColumn(
        activityAt: campaign.lastActivityAt,
        comments: campaign.comments,
        canComment: canEdit,
        onPost: (comment) async {
          await repo.saveCampaign(
            campaign.copyWith(comments: [...campaign.comments, comment]),
            isNew: false,
          );
        },
      ),
      children: [
        SectionCard(
          title: 'Campaign details',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DetailGrid(fields: [
                DetailField('Campaign ID', campaign.id, Icons.badge_outlined),
                DetailField(
                    'Platform', campaign.platform.label, Icons.ads_click),
                DetailField(
                    'Business', business?.name ?? '—', Icons.business_outlined),
                DetailField(
                    'Product', product?.name ?? '—', Icons.inventory_2_outlined),
                DetailField(
                    'Start Date',
                    campaign.startDate == null
                        ? '—'
                        : AppDate.format(campaign.startDate),
                    Icons.event_outlined),
                DetailField(
                    'End Date',
                    campaign.endDate == null
                        ? '—'
                        : AppDate.format(campaign.endDate),
                    Icons.event_available_outlined),
                DetailField('Campaign URL', campaign.url, Icons.link,
                    isLink: true),
              ]),
              if (product != null) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        context.go(Routes.productDetailPath(product.id)),
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('View product'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: t.primary,
                      side: BorderSide(color: t.primary),
                    ),
                  ),
                ),
              ],
              if (campaign.notes.trim().isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: t.surfaceAlt,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Notes',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: t.textSecondary)),
                      const SizedBox(height: 4),
                      Text(campaign.notes,
                          style: const TextStyle(fontSize: 14, height: 1.4)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
