import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../models/app_settings.dart';
import '../../../services/alert_service.dart';
import '../settings_draft.dart';
import '../settings_widgets.dart';

/// Which alerts are raised for everyone, and when.
class AlertsSection extends StatelessWidget {
  const AlertsSection({super.key, required this.draft});

  final SettingsDraft draft;

  @override
  Widget build(BuildContext context) {
    final a = draft.settings.alerts;
    void set(AlertSettings Function(AlertSettings a) change) =>
        draft.update((s) => s.copyWith(alerts: change(s.alerts)));

    return SettingsPanel(
      title: 'Alerts',
      subtitle: 'What raises an alert, and when',
      onReset: () => draft.resetSection((s, d) => s.copyWith(alerts: d.alerts)),
      children: [
        SettingsCard(
          title: 'Alert types',
          subtitle: 'Turn a type off to stop it for everyone. People can also '
              'hide types just for themselves.',
          children: [
            for (final type in AlertType.values)
              SettingSwitch(
                title: type.label,
                value: a.isOn(type.name),
                onChanged: (on) => set((x) => x.copyWith(disabledTypes: {
                      for (final n in x.disabledTypes)
                        if (n != type.name) n,
                      if (!on) type.name,
                    })),
              ),
          ],
        ),
        SettingsCard(
          title: 'Contracts',
          children: [
            SettingsGrid(children: [
              NumberStepper(
                label: 'Warn this many days before a contract ends',
                helper: 'Contracts ending sooner than this raise an alert.',
                value: a.contractWindowDays,
                min: 7,
                max: 120,
                step: 7,
                suffix: ' days',
                onChanged: (v) =>
                    set((x) => x.copyWith(contractWindowDays: v.toInt())),
              ),
              NumberStepper(
                label: 'Mark as urgent within',
                helper: 'Never longer than the warning window.',
                value: a.contractUrgentDays,
                min: 1,
                max: math.min(30, a.contractWindowDays),
                suffix: ' days',
                onChanged: (v) =>
                    set((x) => x.copyWith(contractUrgentDays: v.toInt())),
              ),
              NumberStepper(
                label: 'Keep expired contracts listed for',
                helper: 'After this long they drop off the list. 0 hides them '
                    'straight away.',
                value: a.overdueLookbackDays,
                min: 0,
                max: 365,
                step: 15,
                suffix: ' days',
                onChanged: (v) =>
                    set((x) => x.copyWith(overdueLookbackDays: v.toInt())),
              ),
            ]),
          ],
        ),
        SettingsCard(
          title: 'Campaigns and goals',
          children: [
            SettingsGrid(children: [
              NumberStepper(
                label: 'Warn when a campaign ends within',
                value: a.campaignEndingDays,
                min: 1,
                max: 30,
                suffix: ' days',
                onChanged: (v) =>
                    set((x) => x.copyWith(campaignEndingDays: v.toInt())),
              ),
              NumberStepper(
                label: 'Goal is at risk below',
                helper: 'A goal projected to finish under this share of its '
                    'target is flagged.',
                value: a.goalAtRiskPercent,
                min: 50,
                max: 100,
                step: 5,
                suffix: '%',
                onChanged: (v) =>
                    set((x) => x.copyWith(goalAtRiskPercent: v.toInt())),
              ),
            ]),
          ],
        ),
        SettingsCard(
          title: 'Margins and spending',
          children: [
            SettingsGrid(children: [
              NumberStepper(
                label: 'Low margin below',
                helper: 'Products with a net margin under this are flagged.',
                value: a.lowMarginPercent,
                min: 0,
                max: 50,
                suffix: '%',
                onChanged: (v) =>
                    set((x) => x.copyWith(lowMarginPercent: v.toDouble())),
              ),
              NumberStepper(
                label: 'Orders needed before judging a margin',
                helper: 'Avoids flagging products that have barely sold.',
                value: a.minOrdersForMargin,
                min: 1,
                max: 50,
                onChanged: (v) =>
                    set((x) => x.copyWith(minOrdersForMargin: v.toInt())),
              ),
              NumberStepper(
                label: 'Unusual spend sensitivity',
                helper: 'Lower flags more. Higher flags only big outliers.',
                value: a.spendZ,
                min: 1.5,
                max: 6,
                step: 0.5,
                decimals: 1,
                onChanged: (v) =>
                    set((x) => x.copyWith(spendZ: v.toDouble())),
              ),
              NumberStepper(
                label: 'Mark unusual spend as urgent above',
                helper: 'Never lower than the sensitivity above.',
                value: a.spendZHigh,
                min: a.spendZ,
                max: 10,
                step: 0.5,
                decimals: 1,
                onChanged: (v) =>
                    set((x) => x.copyWith(spendZHigh: v.toDouble())),
              ),
            ]),
          ],
        ),
      ],
    );
  }
}
