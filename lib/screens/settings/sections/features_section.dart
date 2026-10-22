import 'package:flutter/material.dart';

import '../../../models/app_settings.dart';
import '../settings_draft.dart';
import '../settings_widgets.dart';

/// Individual features that can be switched off for everyone.
class FeaturesSection extends StatelessWidget {
  const FeaturesSection({super.key, required this.draft});

  final SettingsDraft draft;

  @override
  Widget build(BuildContext context) {
    final features = draft.settings.features;
    return SettingsPanel(
      title: 'Features',
      subtitle: 'Turn features on or off for everyone',
      onReset: () =>
          draft.resetSection((s, d) => s.copyWith(features: d.features)),
      children: [
        SettingsCard(
          children: [
            for (final f in AppFeature.values)
              SettingSwitch(
                title: f.label,
                subtitle: f.description,
                value: features.isOn(f),
                onChanged: (on) => draft.update(
                    (s) => s.copyWith(features: s.features.toggle(f, enabled: on))),
              ),
          ],
        ),
      ],
    );
  }
}
