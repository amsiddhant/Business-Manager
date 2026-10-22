import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_x.dart';
import '../../../models/goal.dart';
import '../../../services/profit_calculation_service.dart';
import '../../../widgets/common/app_card.dart';
import '../goal_style.dart';

/// Twelve small bars per figure: how each month of the financial year did
/// against its goal. Months without a goal are left empty.
class YearAtAGlance extends StatelessWidget {
  const YearAtAGlance({
    super.key,
    required this.months,
    required this.progress,
  });

  /// The FY's twelve months, in order.
  final List<GoalPeriod> months;

  /// Progress for each metric's month goals, keyed by month key.
  final Map<GoalMetric, Map<String, GoalProgress>> progress;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final entry in progress.entries) ...[
            Text(entry.key.label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: t.textPrimary)),
            const SizedBox(height: AppSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final m in months)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: _Bar(month: m, progress: entry.value[m.key]),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.month, required this.progress});

  final GoalPeriod month;
  final GoalProgress? progress;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final p = progress;
    final letter = DateFormat('MMM').format(month.range.start);
    final fill = p == null ? 0.0 : (p.percent / 100).clamp(0.0, 1.0);
    final tip = p == null
        ? '${month.label}: no goal'
        : '${month.label}: '
            '${GoalStyle.value(p.goal.metric, p.actual, p.goal.currency, compact: true)}'
            ' of ${p.goal.targetLabel} · ${p.status.label}';
    return Tooltip(
      message: tip,
      child: Column(
        children: [
          Container(
            height: 44,
            alignment: Alignment.bottomCenter,
            decoration: BoxDecoration(
              color: t.surfaceAlt,
              borderRadius: BorderRadius.circular(4),
            ),
            child: p == null
                ? null
                : FractionallySizedBox(
                    heightFactor: fill,
                    widthFactor: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: GoalStyle.color(t, p.status),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 4),
          Text(letter,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: TextStyle(fontSize: 10, color: t.textTertiary)),
        ],
      ),
    );
  }
}
