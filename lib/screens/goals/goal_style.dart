import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/enums.dart';
import '../../core/theme/theme_x.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/money.dart';
import '../../models/goal.dart';
import '../../services/profit_calculation_service.dart';
import '../../state/data_controller.dart';
import '../../widgets/common/status_badge.dart';

/// How goals look and read: status colours and the plain-English lines on a
/// goal card. No figures are worked out here (see `ProfitCalculationService`).
class GoalStyle {
  GoalStyle._();

  static const _service = ProfitCalculationService();

  /// Achieved = success, on track = brand, at risk = warning, behind and
  /// missed = danger, not started = neutral.
  static Color color(AppTokens t, GoalStatus status) => switch (status) {
        GoalStatus.achieved => t.success,
        GoalStatus.onTrack => t.primary,
        GoalStatus.atRisk => t.warning,
        GoalStatus.behind || GoalStatus.missed => t.error,
        GoalStatus.notStarted => t.textTertiary,
      };

  static BadgeTone tone(GoalStatus status) => switch (status) {
        GoalStatus.achieved => BadgeTone.success,
        GoalStatus.onTrack => BadgeTone.primary,
        GoalStatus.atRisk => BadgeTone.warning,
        GoalStatus.behind || GoalStatus.missed => BadgeTone.error,
        GoalStatus.notStarted => BadgeTone.neutral,
      };

  /// [value] of [metric]: money in [currency] (compact for tight spaces),
  /// or a plain count.
  static String value(GoalMetric metric, int value, CurrencyCode currency,
      {bool compact = false}) {
    if (metric.isCount) return NumberFormat.decimalPattern().format(value);
    final money = Money(value);
    return compact
        ? MoneyFormatter.compact(money, currency)
        : MoneyFormatter.format(money, currency);
  }

  /// Progress for each of [goals] as of [asOf], using the records of the
  /// goal's own business (everyone's for an organisation-wide goal).
  /// [projection] may give a forecast end value (minor units) for a goal;
  /// null means the run rate.
  static List<GoalProgress> progressOf(
    DataController data,
    Iterable<Goal> goals, {
    required DateTime asOf,
    double atRiskPercent = 90,
    int? Function(Goal)? projection,
  }) {
    final list = [
      for (final g in goals)
        _service.goalProgress(
          goal: g,
          orders: data.ordersFor(g.scopeBusinessId),
          campaigns: data.campaignsFor(g.scopeBusinessId),
          expenses: data.expensesFor(g.scopeBusinessId),
          asOf: asOf,
          atRiskPercent: atRiskPercent,
          projectedOverride: projection?.call(g),
        ),
    ];
    list.sort((a, b) => a.goal.metric.index.compareTo(b.goal.metric.index));
    return list;
  }

  /// "12% ahead of pace" / "8% behind pace"; null when pace doesn't apply.
  static String? paceLabel(GoalProgress p) {
    if (!p.status.isRunning || p.expectedToDate <= 0) return null;
    final diff = (p.pace - 100).round();
    if (diff == 0) return 'On pace';
    return diff > 0 ? '$diff% ahead of pace' : '${-diff}% behind pace';
  }

  /// "On course for ₹X by 30 Apr" while running; how it ended otherwise.
  static String? projectionLabel(GoalProgress p) {
    final g = p.goal;
    final end = AppDate.short(g.period.range.end);
    switch (p.status) {
      case GoalStatus.notStarted:
        return 'Starts ${AppDate.short(g.period.range.start)}';
      case GoalStatus.achieved:
        return p.actual > p.target
            ? 'Beat the target by ${value(g.metric, p.actual - p.target, g.currency, compact: true)}'
            : 'Target reached';
      case GoalStatus.missed:
        return 'Fell short by ${value(g.metric, p.remaining, g.currency, compact: true)}';
      case GoalStatus.onTrack:
      case GoalStatus.atRisk:
      case GoalStatus.behind:
        final projected = p.projected;
        if (projected == null) return null;
        return 'On course for ${value(g.metric, projected, g.currency, compact: true)} by $end';
    }
  }

  /// "Needs ₹Y a day"; null when nothing more is needed.
  static String? requiredLabel(GoalProgress p) {
    final per = p.requiredPerDay;
    if (per == null || p.status == GoalStatus.notStarted) return null;
    final g = p.goal;
    return 'Needs ${value(g.metric, per, g.currency, compact: true)} a day';
  }

  /// "12 days left" / "Last day"; null once the period is over or before it
  /// starts.
  static String? daysLeftLabel(GoalProgress p) {
    if (p.status == GoalStatus.notStarted || p.status == GoalStatus.missed) {
      return null;
    }
    final left = p.totalDays - p.elapsedDays;
    if (left < 0) return null;
    if (left == 0) return p.status.isRunning ? 'Last day' : null;
    return left == 1 ? '1 day left' : '$left days left';
  }

  /// "62%" for the middle of a ring.
  static String percentLabel(GoalProgress p) => '${p.percent.round()}%';

  static String semantics(GoalProgress p) =>
      '${p.goal.metric.label}, ${p.percent.round()} percent of target, '
      '${p.status.label}';
}
