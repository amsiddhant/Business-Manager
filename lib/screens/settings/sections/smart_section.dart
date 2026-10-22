import 'package:flutter/material.dart';

import '../settings_draft.dart';
import '../settings_widgets.dart';

/// Settings for on-device smart features.
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
        const SettingsNote(
          'On-device AI arrives in a later update. These choices are saved '
          'now and apply when it does.',
        ),
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
