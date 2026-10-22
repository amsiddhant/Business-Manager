import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_x.dart';
import '../../../core/utils/date_utils.dart';
import '../../../models/app_settings.dart';
import '../../../state/org_settings.dart';
import '../../../state/smart_insights_controller.dart';
import '../settings_draft.dart';
import '../settings_widgets.dart';

/// The icon for an on-device AI [status].
IconData smartStatusIcon(SmartStatus status) => switch (status) {
      SmartStatus.off => Icons.block,
      SmartStatus.baseline => Icons.tune,
      SmartStatus.enhanced => Icons.auto_awesome,
      SmartStatus.error => Icons.error_outline,
    };

/// The colour for an on-device AI [status].
Color smartStatusColor(AppTokens t, SmartStatus status) => switch (status) {
      SmartStatus.off => t.textTertiary,
      SmartStatus.baseline => t.textSecondary,
      SmartStatus.enhanced => t.success,
      SmartStatus.error => t.warning,
    };

/// Settings for on-device smart features, and how they are doing.
class SmartSection extends StatelessWidget {
  const SmartSection({super.key, required this.draft});

  final SettingsDraft draft;

  @override
  Widget build(BuildContext context) {
    final smart = draft.settings.smart;
    return SettingsPanel(
      title: 'Smart AI',
      subtitle: 'Suggestions that learn from your own records',
      onReset: () => draft.resetSection((s, d) => s.copyWith(smart: d.smart)),
      children: [
        const _StatusCard(),
        SettingsCard(
          children: [
            NumberStepper(
              label: 'Records needed before learning starts',
              helper: 'Until then the app uses simple rules instead.',
              value: smart.minRows,
              min: 20,
              max: 500,
              step: 10,
              onChanged: (v) => draft.update(
                  (s) => s.copyWith(smart: s.smart.copyWith(minRows: v.toInt()))),
            ),
            const SizedBox(height: 12),
            SettingSwitch(
              title: 'Wipe on sign-out',
              subtitle: 'Clear what the app learned on this device when '
                  'someone signs out.',
              value: smart.wipeOnSignOut,
              onChanged: (v) => draft.update((s) =>
                  s.copyWith(smart: s.smart.copyWith(wipeOnSignOut: v))),
            ),
          ],
        ),
      ],
    );
  }
}

/// What the on-device AI is doing on this device right now.
class _StatusCard extends StatelessWidget {
  const _StatusCard();

  @override
  Widget build(BuildContext context) {
    final smart = smartOf(context);
    if (smart == null) {
      return const SettingsCard(
        title: 'On-device AI',
        children: [
          SettingsNote('The built-in models are in use. Status isn’t '
              'available here.'),
        ],
      );
    }
    final t = context.tokens;
    final forecasts =
        context.orgSettings((s) => s.features.isOn(AppFeature.forecasts));
    final anomalies =
        context.orgSettings((s) => s.features.isOn(AppFeature.anomalies));
    final suggestions =
        context.orgSettings((s) => s.features.isOn(AppFeature.suggestions));
    final minRows = context.orgSettings((s) => s.smart.minRows);
    final status = smart.status;
    final test = smart.selfTest;
    final problem = smart.problem;
    final tfForecast = forecasts && (smart.forecastFor(null)?.enhanced ?? false);
    final tfSpend = anomalies && smart.spendScores.isNotEmpty;
    return SettingsCard(
      title: 'On-device AI',
      subtitle: 'Improves forecasts, spend checks and suggestions on this '
          'device. Nothing leaves it.',
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(smartStatusIcon(status),
            size: 18, color: smartStatusColor(t, status)),
        const SizedBox(width: AppSpacing.xs),
        Text(status.label,
            style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: smartStatusColor(t, status))),
      ]),
      children: [
        if (problem != null) ...[
          SettingsNote(problem, tone: SettingsNoteTone.warning),
          const SizedBox(height: AppSpacing.md),
        ],
        _Line('Forecasts',
            !forecasts ? 'Off' : (tfForecast ? 'On-device model' : 'Built-in trend')),
        _Line('Spend checks',
            !anomalies ? 'Off' : (tfSpend ? 'On-device model' : 'Built-in')),
        if (!suggestions) const _Line('Suggestions', 'Off'),
        if (suggestions)
          for (final m in smart.models) _ModelRow(m, minRows: minRows),
        _Line(
            'Self-test',
            test == null
                ? 'Not run yet'
                : '${test.passed ? 'Passed' : 'Failed'} in ${test.ms} ms'),
      ],
    );
  }
}

class _ModelRow extends StatelessWidget {
  const _ModelRow(this.model, {required this.minRows});

  final SmartModelInfo model;
  final int minRows;

  static String _percent(double v) => '${(v * 100).round()}%';

  @override
  Widget build(BuildContext context) {
    final trained = model.trainedAt;
    final String detail;
    if (trained == null) {
      detail = model.rows < minRows
          ? '${model.rows} of $minRows records so far'
          : '${model.rows} records, not learned yet';
    } else {
      detail = [
        '${model.rows} records',
        'accuracy ${_percent(model.accuracy ?? 0)} '
            'vs ${_percent(model.rulesAccuracy ?? 0)} for simple rules',
        'trained ${AppDate.format(trained)}',
        model.inUse ? 'in use' : 'not better than the rules yet',
      ].join(' · ');
    }
    return _Line(model.label, detail);
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label,
                style: TextStyle(fontSize: 13.5, color: t.textSecondary)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: t.textPrimary)),
          ),
        ],
      ),
    );
  }
}
