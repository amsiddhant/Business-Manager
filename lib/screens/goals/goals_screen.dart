import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/permissions.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_x.dart';
import '../../core/utils/date_utils.dart';
import '../../models/goal.dart';
import '../../services/profit_calculation_service.dart';
import '../../state/app_state.dart';
import '../../state/data_controller.dart';
import '../../state/filter_controller.dart';
import '../../state/org_settings.dart';
import '../../state/smart_insights_controller.dart';
import '../../widgets/common/app_card.dart';
import '../../widgets/common/page_header.dart';
import '../../widgets/common/state_views.dart';
import '../../widgets/layout/app_page.dart';
import 'goal_editor.dart';
import 'goal_style.dart';
import 'widgets/goal_card.dart';
import 'widgets/year_at_a_glance.dart';

/// Goals & targets: progress against each goal for the selected business
/// (or the whole organisation), and the editor to set them.
class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key});

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  GoalPeriodType _type = GoalPeriodType.month;
  late GoalPeriod _period =
      GoalPeriod.containing(GoalPeriodType.month, DateTime.now());

  void _setType(GoalPeriodType type) {
    if (type == _type) return;
    setState(() {
      _type = type;
      _period = GoalPeriod.containing(type, _period.range.start);
    });
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataController>();
    final bid = context
        .select<FilterController, String?>((f) => f.selectedBusinessId);
    final user = context.watch<AppState>().currentUser;
    final atRisk =
        context.orgSettings((s) => s.alerts.goalAtRiskPercent).toDouble();
    final now = DateTime.now();

    final isAll = bid == null;
    final isOwner = user?.isOwner ?? false;
    final mayManage = user != null &&
        (isAll
            ? isOwner
            : user.can(Permission.manageGoals) && user.canAccessBusiness(bid));
    final canSet = mayManage && !data.goalsUnavailable;
    final scopeName =
        isAll ? 'All businesses' : (data.businessById(bid)?.name ?? 'Business');

    final goals = [
      for (final g in data.goalsFor(bid))
        if (g.period == _period) g,
    ];
    final progress = GoalStyle.progressOf(data, goals,
        asOf: now,
        atRiskPercent: atRisk,
        projection: smartOf(context)?.goalProjection);

    void edit(GoalPeriod period) =>
        showGoalEditor(context, businessId: bid, period: period);

    return AppPage(
      children: [
        PageHeader(
          title: 'Goals',
          subtitle: scopeName,
          icon: Icons.flag_outlined,
          actions: [
            if (canSet)
              FilledButton.icon(
                onPressed: () => edit(_period),
                icon: const Icon(Icons.flag_outlined, size: 18),
                label: const Text('Set goals'),
              ),
          ],
        ),
        if (!mayManage && user != null) ...[
          const SizedBox(height: AppSpacing.md),
          _Note(
            isAll
                ? 'Goals for all businesses are set by the owner.'
                : 'You can see these goals. People with permission to manage '
                    'goals can change them.',
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        if (data.goalsUnavailable)
          _Unavailable(isOwner: isOwner)
        else ...[
          _Controls(
            type: _type,
            period: _period,
            isCurrent: _period == GoalPeriod.containing(_type, now),
            onType: _setType,
            onPeriod: (p) => setState(() => _period = p),
            onCurrent: () =>
                setState(() => _period = GoalPeriod.containing(_type, now)),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (progress.isEmpty)
            AppCard(
              child: EmptyView(
                icon: Icons.flag_outlined,
                title: 'No goals for ${_period.label}',
                message: canSet
                    ? 'Set targets for revenue, profit and orders, and see '
                        'how you are doing against them.'
                    : 'No targets have been set for this period yet.',
                action: canSet
                    ? FilledButton(
                        onPressed: () => edit(_period),
                        child: Text('Add goals for ${_period.label}'),
                      )
                    : null,
              ),
            )
          else ...[
            _Overview(progress: progress),
            const SizedBox(height: AppSpacing.lg),
            _Grid(
              progress: progress,
              onTap: canSet ? (p) => edit(p.goal.period) : null,
            ),
          ],
          if (_type == GoalPeriodType.month)
            ..._yearAtAGlance(data, bid, now, atRisk),
        ],
      ],
    );
  }

  /// Twelve bars per figure for the FY of the month on show.
  List<Widget> _yearAtAGlance(
      DataController data, String? bid, DateTime now, double atRisk) {
    final fy = FinancialYear.forDate(_period.range.start).startYear;
    final months = GoalPeriod.financialYear(fy).months;
    final keys = {for (final m in months) m.key};
    final goals = [
      for (final g in data.goalsFor(bid))
        if (keys.contains(g.period.key)) g,
    ];
    if (goals.isEmpty) return const [];
    final byMetric = <GoalMetric, Map<String, GoalProgress>>{};
    for (final p in GoalStyle.progressOf(data, goals,
        asOf: now,
        atRiskPercent: atRisk,
        projection: smartOf(context)?.goalProjection)) {
      (byMetric[p.goal.metric] ??= {})[p.goal.period.key] = p;
    }
    final t = context.tokens;
    return [
      const SizedBox(height: AppSpacing.xl),
      Semantics(
        header: true,
        child: Text('Year at a glance',
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
                color: t.textPrimary)),
      ),
      const SizedBox(height: 2),
      Text(GoalPeriod.financialYear(fy).label,
          style: TextStyle(fontSize: 12.5, color: t.textTertiary)),
      const SizedBox(height: AppSpacing.md),
      YearAtAGlance(months: months, progress: byMetric),
    ];
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      children: [
        Icon(Icons.info_outline, size: 16, color: t.textTertiary),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(text,
              style: TextStyle(fontSize: 13, color: t.textSecondary)),
        ),
      ],
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.isOwner});
  final bool isOwner;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline, color: t.warning),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: isOwner
                ? Text.rich(
                    TextSpan(
                      style: TextStyle(color: t.textPrimary, fontSize: 14),
                      children: [
                        const TextSpan(
                            text:
                                'Goals need the latest Firestore rules — run '),
                        TextSpan(
                          text: 'firebase deploy --only firestore:rules',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w600,
                            backgroundColor: t.surfaceAlt,
                          ),
                        ),
                      ],
                    ),
                  )
                : Text("Goals aren't available yet.",
                    style: TextStyle(color: t.textPrimary, fontSize: 14)),
          ),
        ],
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.type,
    required this.period,
    required this.isCurrent,
    required this.onType,
    required this.onPeriod,
    required this.onCurrent,
  });

  final GoalPeriodType type;
  final GoalPeriod period;
  final bool isCurrent;
  final ValueChanged<GoalPeriodType> onType;
  final ValueChanged<GoalPeriod> onPeriod;
  final VoidCallback onCurrent;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Wrap(
      spacing: AppSpacing.lg,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SegmentedButton<GoalPeriodType>(
          showSelectedIcon: false,
          segments: [
            for (final type in GoalPeriodType.values)
              ButtonSegment(value: type, label: Text(type.label)),
          ],
          selected: {type},
          onSelectionChanged: (s) => onType(s.first),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Previous ${type.label.toLowerCase()}',
              onPressed: () => onPeriod(period.previous),
              icon: const Icon(Icons.chevron_left),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 112),
              child: Text(period.label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: t.textPrimary)),
            ),
            IconButton(
              tooltip: 'Next ${type.label.toLowerCase()}',
              onPressed: () => onPeriod(period.next),
              icon: const Icon(Icons.chevron_right),
            ),
            TextButton(
              onPressed: isCurrent ? null : onCurrent,
              child: const Text('Current'),
            ),
          ],
        ),
      ],
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({required this.progress});
  final List<GoalProgress> progress;

  int _count(bool Function(GoalStatus) test) =>
      progress.where((p) => test(p.status)).length;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final stats = [
      ('Goals', progress.length, t.textPrimary),
      ('Achieved', _count((s) => s == GoalStatus.achieved), t.success),
      ('On track', _count((s) => s == GoalStatus.onTrack), t.primary),
      (
        'At risk or behind',
        _count((s) =>
            s == GoalStatus.atRisk ||
            s == GoalStatus.behind ||
            s == GoalStatus.missed),
        t.warning
      ),
    ];
    return LayoutBuilder(builder: (context, c) {
      const gap = AppSpacing.md;
      final cols = c.maxWidth >= 640 ? 4 : 2;
      final w = ((c.maxWidth - gap * (cols - 1)) / cols).floorToDouble();
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final (label, count, color) in stats)
            SizedBox(
              width: w,
              child: AppCard(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                child: Semantics(
                  label: '$label: $count',
                  excludeSemantics: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$count',
                          style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: color,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ])),
                      Text(label,
                          style: TextStyle(
                              fontSize: 12.5, color: t.textSecondary)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      );
    });
  }
}

class _Grid extends StatelessWidget {
  const _Grid({required this.progress, this.onTap});

  final List<GoalProgress> progress;
  final void Function(GoalProgress)? onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      const gap = AppSpacing.lg;
      final cols = c.maxWidth >= 1000 ? 3 : (c.maxWidth >= 640 ? 2 : 1);
      final w = ((c.maxWidth - gap * (cols - 1)) / cols).floorToDouble();
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final p in progress)
            SizedBox(
              width: w,
              child: GoalCard(
                key: ValueKey(p.goal.id),
                progress: p,
                onTap: onTap == null ? null : () => onTap!(p),
              ),
            ),
        ],
      );
    });
  }
}
