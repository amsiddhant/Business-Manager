import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_x.dart';
import '../../../services/profit_calculation_service.dart';
import '../../../widgets/common/app_card.dart';
import '../../../widgets/common/status_badge.dart';
import '../goal_style.dart';
import 'progress_ring.dart';

/// One goal: a progress ring, what's been done against the target, its
/// status, and how the pace and projection look. Tapping opens the editor.
class GoalCard extends StatelessWidget {
  const GoalCard({super.key, required this.progress, this.onTap});

  final GoalProgress progress;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final p = progress;
    final g = p.goal;
    final color = GoalStyle.color(t, p.status);
    final pace = GoalStyle.paceLabel(p);
    final projection = GoalStyle.projectionLabel(p);
    final required = GoalStyle.requiredLabel(p);
    final daysLeft = GoalStyle.daysLeftLabel(p);

    final lines = <Widget>[
      if (projection != null) _line(t, Icons.trending_up, projection),
      if (required != null) _line(t, Icons.speed_outlined, required),
      if (daysLeft != null) _line(t, Icons.schedule, daysLeft),
    ];

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ProgressRing(
                percent: p.percent,
                color: color,
                semanticsLabel: GoalStyle.semantics(p),
                child: Text(
                  GoalStyle.percentLabel(p),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: t.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(g.metric.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: t.textPrimary)),
                    const SizedBox(height: 2),
                    Text(
                      '${GoalStyle.value(g.metric, p.actual, g.currency, compact: true)}'
                      ' of ${GoalStyle.value(g.metric, g.target, g.currency, compact: true)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13,
                          color: t.textSecondary,
                          fontFeatures: const [FontFeature.tabularFigures()]),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      children: [
                        StatusBadge(
                            label: p.status.label,
                            tone: GoalStyle.tone(p.status)),
                        if (pace != null) _PaceChip(label: pace, progress: p),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (lines.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            for (var i = 0; i < lines.length; i++) ...[
              if (i > 0) const SizedBox(height: 4),
              lines[i],
            ],
          ],
          if (g.note.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(g.note,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: t.textTertiary)),
          ],
        ],
      ),
    );
  }

  Widget _line(AppTokens t, IconData icon, String text) => Row(
        children: [
          Icon(icon, size: 15, color: t.textTertiary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 12.5, color: t.textSecondary)),
          ),
        ],
      );
}

class _PaceChip extends StatelessWidget {
  const _PaceChip({required this.label, required this.progress});

  final String label;
  final GoalProgress progress;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ahead = progress.pace >= 100;
    final fg = ahead ? t.success : t.warning;
    final bg = ahead ? t.successSurface : t.warningSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: ShapeDecoration(color: bg, shape: const StadiumBorder()),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ahead ? Icons.arrow_upward : Icons.arrow_downward,
              size: 12, color: fg),
          const SizedBox(width: 3),
          Text(label,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
        ],
      ),
    );
  }
}
