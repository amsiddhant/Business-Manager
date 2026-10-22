import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_x.dart';
import '../../../services/insight_service.dart';
import '../../../widgets/common/app_card.dart';

/// One insight: a tone-coloured icon, a short title and a sentence. Tapping
/// opens where it points, when there is somewhere to go.
class InsightCard extends StatelessWidget {
  const InsightCard({super.key, required this.insight, this.onTap});

  final Insight insight;
  final VoidCallback? onTap;

  static Color colorOf(AppTokens t, InsightTone tone) => switch (tone) {
    InsightTone.positive => t.success,
    InsightTone.negative => t.error,
    InsightTone.warning => t.warning,
    InsightTone.neutral => t.info,
  };

  static IconData iconOf(Insight i) => switch (i.kind) {
    InsightKind.revenueChange => i.tone == InsightTone.negative
        ? Icons.trending_down
        : Icons.trending_up,
    InsightKind.marginChange => Icons.percent,
    InsightKind.concentration => Icons.pie_chart_outline,
    InsightKind.weakCampaigns => Icons.campaign_outlined,
    InsightKind.bestCampaign => Icons.emoji_events_outlined,
    InsightKind.spendSpike => Icons.bolt_outlined,
    InsightKind.contractsExpiring => Icons.event_busy_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = colorOf(t, insight.tone);
    return Semantics(
      button: onTap != null,
      label: '${insight.title}. ${insight.message}',
      excludeSemantics: true,
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(iconOf(insight), size: 17, color: color),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(insight.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13.5,
                          height: 1.25,
                          fontWeight: FontWeight.w600,
                          color: t.textPrimary)),
                ),
                if (onTap != null)
                  Icon(Icons.arrow_forward, size: 16, color: t.textTertiary),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Text(insight.message,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12.5, height: 1.4, color: t.textSecondary)),
            ),
          ],
        ),
      ),
    );
  }
}
