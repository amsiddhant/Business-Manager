import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/enums.dart';
import '../../core/permissions.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/money.dart';
import '../../models/campaign.dart';
import '../../state/app_state.dart';
import '../../state/data_controller.dart';
import '../../widgets/common/app_card.dart';
import '../../widgets/common/comment_thread.dart';
import '../../widgets/common/detail_widgets.dart';
import '../../widgets/common/page_header.dart';
import '../../widgets/common/state_views.dart';
import '../../widgets/common/status_badge.dart';
import 'campaigns_screen.dart';

/// A single campaign view: performance metrics, the linked product & business,
/// and a comment thread. All linked entities are resolved through the
/// access-scoped [DataController], so nothing outside the viewer's reach shows.
class CampaignDetailScreen extends StatelessWidget {
  const CampaignDetailScreen({super.key, required this.campaignId});

  final String campaignId;

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataController>();
    final appState = context.watch<AppState>();
    final user = appState.currentUser;

    if (data.loading && !data.loaded) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(title: 'Campaign'),
          SizedBox(height: 48),
          LoadingView(),
        ],
      );
    }

    final campaign = data.campaignById(campaignId);
    if (campaign == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(
            title: 'Campaign',
            actions: [
              OutlinedButton.icon(
                onPressed: () => context.go(Routes.campaigns),
                icon: const Icon(Icons.arrow_back, size: 18),
                label: const Text('Back to Campaigns'),
              ),
            ],
          ),
          const SizedBox(height: 48),
          const EmptyView(
            icon: Icons.search_off,
            title: 'Campaign not found',
            message:
                'This campaign may have been removed or is not accessible.',
          ),
        ],
      );
    }

    final business = data.businessById(campaign.businessId);
    final product = data.productById(campaign.productId);
    final currency = business?.currency ?? CurrencyCode.inr;
    final canEdit = user?.can(Permission.editCampaign) ?? false;

    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SummaryCard(
          campaign: campaign,
          currency: currency,
          businessName: business?.name,
          productName: product?.name,
          productId: product?.id,
        ),
      ],
    );

    final repo = appState.repository;
    final right = DetailActivityColumn(
      activityAt: campaign.lastActivityAt,
      comments: campaign.comments,
      canComment: canEdit,
      onPost: (comment) async {
        await repo.saveCampaign(
          campaign.copyWith(comments: [...campaign.comments, comment]),
          isNew: false,
        );
        await data.refresh();
      },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: campaign.name,
          subtitle: '${campaign.id} · ${campaign.platform.label}',
          actions: [
            OutlinedButton.icon(
              onPressed: () => context.go(Routes.campaigns),
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('Back'),
            ),
            if (canEdit)
              ElevatedButton.icon(
                onPressed: () => CampaignsScreen.openForm(
                    context, campaign, campaign.businessId),
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

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.campaign,
    required this.currency,
    required this.businessName,
    required this.productName,
    required this.productId,
  });

  final Campaign campaign;
  final CurrencyCode currency;
  final String? businessName;
  final String? productName;
  final String? productId;

  @override
  Widget build(BuildContext context) {
    final metrics = <_Metric>[
      _Metric('Budget', MoneyFormatter.format(campaign.budget, currency)),
      _Metric('Amount Invested',
          MoneyFormatter.format(campaign.amountInvested, currency)),
      _Metric('Impressions', '${campaign.impressions}'),
      _Metric('Clicks', '${campaign.clicks}'),
      _Metric('Conversions', '${campaign.conversions}'),
      _Metric('CTR', PercentFormatter.format(campaign.ctr)),
      _Metric('Conv. Rate', PercentFormatter.format(campaign.conversionRate)),
      _Metric('Type', campaign.type.isEmpty ? '—' : campaign.type),
    ];

    final fields = <DetailField>[
      DetailField('Campaign ID', campaign.id, Icons.badge_outlined),
      DetailField('Platform', campaign.platform.label, Icons.ads_click),
      DetailField('Business', businessName ?? '—', Icons.business_outlined),
      DetailField('Product', productName ?? '—', Icons.inventory_2_outlined),
      DetailField('Start Date',
          campaign.startDate == null ? '—' : AppDate.format(campaign.startDate),
          Icons.event_outlined),
      DetailField('End Date',
          campaign.endDate == null ? '—' : AppDate.format(campaign.endDate),
          Icons.event_available_outlined),
      DetailField('Campaign URL', campaign.url, Icons.link, isLink: true),
    ];

    return SectionCard(
      title: 'Campaign Summary',
      trailing: StatusBadge.campaign(campaign.status),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
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
          const SizedBox(height: AppSpacing.lg),
          DetailGrid(fields: fields),
          if (productId != null) ...[
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => context.go(Routes.productDetailPath(productId!)),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('View product'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                ),
              ),
            ),
          ],
          if (campaign.notes.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            const Text('Notes',
                style:
                    TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 2),
            Text(campaign.notes,
                style: const TextStyle(fontSize: 14, height: 1.4)),
          ],
        ],
      ),
    );
  }
}

class _Metric {
  const _Metric(this.label, this.value);
  final String label;
  final String value;
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
          Text(metric.value,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
