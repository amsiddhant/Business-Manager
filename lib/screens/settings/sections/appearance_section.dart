import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_density.dart';
import '../../../state/theme_controller.dart';
import '../../../state/user_prefs.dart';
import '../settings_widgets.dart';

/// Your own look: light or dark, motion and density. These are saved for you
/// on this device; the organisation's choices apply until you pick yours.
class AppearanceSection extends StatelessWidget {
  const AppearanceSection({super.key});

  static const _modeLabels = {
    ThemeMode.light: 'Light',
    ThemeMode.dark: 'Dark',
    ThemeMode.system: 'System',
  };

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<UserPrefs>();
    final theme = context.watch<ThemeController>();
    final canChooseMode = theme.canChooseMode;
    return SettingsPanel(
      title: 'Appearance',
      subtitle: 'How the app looks for you',
      children: [
        SettingsCard(
          title: 'Colour mode',
          children: [
            ChoiceRow<ThemeMode>(
              label: 'Theme',
              value: theme.mode,
              options: ThemeMode.values,
              labelOf: (m) => _modeLabels[m]!,
              enabled: canChooseMode,
              onChanged: prefs.setThemeMode,
            ),
            if (!canChooseMode) ...[
              const SizedBox(height: 12),
              const SettingsNote(
                  'Your organisation has set the colour mode, so it can’t be '
                  'changed here.'),
            ],
          ],
        ),
        SettingsCard(
          title: 'Motion and spacing',
          children: [
            SettingSwitch(
              title: 'Reduce motion',
              subtitle: 'Fewer animations and no moving transitions.',
              value: prefs.reduceMotion,
              onChanged: prefs.setReduceMotion,
            ),
            const SizedBox(height: 8),
            ChoiceRow<AppDensity?>(
              label: 'Density',
              helper: 'How much room tables and forms take up.',
              value: prefs.density,
              options: [null, ...AppDensity.values],
              labelOf: (d) => d?.label ?? 'Organisation default',
              onChanged: prefs.setDensity,
            ),
          ],
        ),
      ],
    );
  }
}
