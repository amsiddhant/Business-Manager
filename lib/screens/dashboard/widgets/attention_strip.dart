import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_x.dart';
import '../../../services/alert_service.dart';
import '../../../services/insight_service.dart';
import '../../../widgets/common/app_card.dart';
import 'insight_card.dart';

/// "What needs attention": an alerts summary card first, then the insights.
/// A grid on wide screens; a swipeable row on phones.
class AttentionStrip extends StatelessWidget {
  const AttentionStrip({
    super.key,
    required this.alerts,
    required this.insights,
    required this.onOpenAlerts,
    required this.onOpen,
  });

  /// The user's active alerts, most urgent first.
  final List<AppAlert> alerts;
  final List<Insight> insights;
  final VoidCallback onOpenAlerts;

  /// Opens a route; null when the user can't open it.
  final VoidCallback? Function(String? route) onOpen;

  static const cardHeight = 168.0;

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[
      AlertsSummaryCard(alerts: alerts, onOpenAlerts: onOpenAlerts),
      for (final i in insights) InsightCard(insight: i, onTap: onOpen(i.route)),
    ];

    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < 640) {
        return SizedBox(
          height: cardHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: cards.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
            itemBuilder: (context, i) => SizedBox(
                width: (c.maxWidth * 0.82).clamp(240.0, 320.0),
                child: cards[i]),
          ),
        );
      }
      final columns = c.maxWidth >= 1200 ? 4 : (c.maxWidth >= 900 ? 3 : 2);
      const gap = AppSpacing.lg;
      final width = (c.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final card in cards)
            SizedBox(width: width, height: cardHeight, child: card),
        ],
      );
    });
  }
}

/// The alerts at a glance: how many need attention and the top three, or an
/// "all caught up" note.
class AlertsSummaryCard extends StatelessWidget {
  const AlertsSummaryCard({
    super.key,
    required this.alerts,
    required this.onOpenAlerts,
  });

  final List<AppAlert> alerts;
  final VoidCallback onOpenAlerts;

  static Color colorOf(AppTokens t, AlertSeverity s) => switch (s) {
    AlertSeverity.high => t.error,
    AlertSeverity.medium => t.warning,
    AlertSeverity.info => t.info,
  };

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final urgent = [
      for (final a in alerts)
        if (a.severity != AlertSeverity.info) a,
    ];
    final shown = (urgent.isEmpty ? alerts : urgent).take(3).toList();
    final high = urgent.any((a) => a.severity == AlertSeverity.high);
    final accent = urgent.isEmpty ? t.success : (high ? t.error : t.warning);

    return AppCard(
      onTap: onOpenAlerts,
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
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                    urgent.isEmpty
                        ? Icons.check_circle_outline
                        : Icons.notifications_active_outlined,
                    size: 17,
                    color: accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                    urgent.isEmpty
                        ? 'All caught up'
                        : '${urgent.length} '
                            '${urgent.length == 1 ? 'alert needs' : 'alerts need'}'
                            ' attention',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: t.textPrimary)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: shown.isEmpty
                ? Text('Nothing needs your attention right now.',
                    style: TextStyle(
                        fontSize: 12.5, height: 1.4, color: t.textSecondary))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final a in shown)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  color: colorOf(t, a.severity),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(a.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 12.5,
                                        color: t.textSecondary)),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
          Row(
            children: [
              Text('Open alerts',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: t.primary)),
              const SizedBox(width: 4),
              Icon(Icons.arrow_forward, size: 15, color: t.primary),
            ],
          ),
        ],
      ),
    );
  }
}
