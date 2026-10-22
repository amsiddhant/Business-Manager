import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/permissions.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_x.dart';
import '../../../models/goal.dart';
import '../../../services/profit_calculation_service.dart';
import '../../../state/app_state.dart';
import '../../../state/data_controller.dart';
import '../../../state/org_settings.dart';
import '../../../state/smart_insights_controller.dart';
import '../../../widgets/common/app_card.dart';
import '../../dashboard/widgets/dashboard_section.dart';
import '../goal_editor.dart';
import '../goal_style.dart';
import 'progress_ring.dart';

/// The dashboard's goals section: the selected scope's running goals with
/// their progress. Renders nothing when there are none.
class GoalsSummaryCard extends StatelessWidget {
  const GoalsSummaryCard({super.key, this.businessId});

  /// The business in scope; null = the organisation-wide goals.
  final String? businessId;

  static const _maxShown = 4;

  /// This month's goals, else this quarter's, else this financial year's.
  static ({GoalPeriod period, List<Goal> goals})? runningNow(
      List<Goal> goals, DateTime now) {
    for (final type in GoalPeriodType.values) {
      final period = GoalPeriod.containing(type, now);
      final match = [
        for (final g in goals)
          if (g.period == period) g,
      ];
      if (match.isNotEmpty) return (period: period, goals: match);
    }
    return null;
  }

  void _viewAll(BuildContext context) =>
      GoRouter.maybeOf(context)?.go(Routes.goals);

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataController>();
    final user = context.watch<AppState>().currentUser;
    final atRisk =
        context.orgSettings((s) => s.alerts.goalAtRiskPercent).toDouble();
    final goals = data.goalsFor(businessId);
    if (goals.isEmpty) return const SizedBox.shrink();

    final now = DateTime.now();
    final running = runningNow(goals, now);
    final canSet = user != null &&
        !data.goalsUnavailable &&
        (businessId == null
            ? user.isOwner
            : user.can(Permission.manageGoals) &&
                user.canAccessBusiness(businessId!));
    final t = context.tokens;

    final Widget body;
    if (running == null) {
      body = AppCard(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            Icon(Icons.flag_outlined, color: t.textTertiary),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text('No goals for this month',
                  style: TextStyle(color: t.textSecondary, fontSize: 14)),
            ),
            if (canSet)
              TextButton(
                onPressed: () => showGoalEditor(context,
                    businessId: businessId,
                    period: GoalPeriod.containing(GoalPeriodType.month, now)),
                child: const Text('Set goals'),
              ),
          ],
        ),
      );
    } else {
      final progress = GoalStyle.progressOf(data, running.goals,
              asOf: now,
              atRiskPercent: atRisk,
              projection: smartOf(context)?.goalProjection)
          .take(_maxShown)
          .toList();
      body = AppCard(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: LayoutBuilder(builder: (context, c) {
          const gap = AppSpacing.lg;
          final cols = progress.length.clamp(1, c.maxWidth >= 640 ? 4 : 2);
          final w = ((c.maxWidth - gap * (cols - 1)) / cols).floorToDouble();
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final p in progress)
                SizedBox(width: w, child: _CompactGoal(progress: p)),
            ],
          );
        }),
      );
    }

    return DashboardSection(
      title: 'Goals',
      subtitle: running?.period.label,
      trailing: TextButton(
        onPressed: () => _viewAll(context),
        child: const Text('View all'),
      ),
      tiles: [DashTile(span: 12, child: body)],
    );
  }
}

class _CompactGoal extends StatelessWidget {
  const _CompactGoal({required this.progress});
  final GoalProgress progress;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final p = progress;
    final color = GoalStyle.color(t, p.status);
    return Row(
      children: [
        ProgressRing(
          percent: p.percent,
          color: color,
          size: 56,
          strokeWidth: 6,
          semanticsLabel: GoalStyle.semantics(p),
          child: Text(GoalStyle.percentLabel(p),
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: t.textPrimary)),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(p.goal.metric.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: t.textPrimary)),
              Text(p.status.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600, color: color)),
            ],
          ),
        ),
      ],
    );
  }
}
