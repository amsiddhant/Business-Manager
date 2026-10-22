import 'package:flutter/material.dart';

import '../../../core/theme/app_density.dart';
import '../../../core/theme/app_motion.dart';
import '../../../models/app_settings.dart';
import '../settings_draft.dart';
import '../settings_widgets.dart';
import '../theme_preview_pane.dart';

/// Light or dark, density, motion, corners and chart colours for everyone.
class ThemeSection extends StatelessWidget {
  const ThemeSection({super.key, required this.draft});

  final SettingsDraft draft;

  static const _modeLabels = {
    ThemeMode.light: 'Light',
    ThemeMode.dark: 'Dark',
    ThemeMode.system: 'Follow the device',
  };

  static const _motionHelp = {
    MotionLevel.full: 'Fades, slides and chart build-ups.',
    MotionLevel.reduced: 'Fades only. Nothing moves across the screen.',
    MotionLevel.off: 'No animation at all.',
  };

  @override
  Widget build(BuildContext context) {
    final theme = draft.settings.theme;
    void set(ThemeSettings Function(ThemeSettings t) change) =>
        draft.update((s) => s.copyWith(theme: change(s.theme)));

    return SettingsPanel(
      title: 'Theme',
      subtitle: 'The look of the app for everyone',
      onReset: () =>
          draft.resetSection((s, d) => s.copyWith(theme: d.theme)),
      children: [
        SettingsCard(
          title: 'Colour mode',
          children: [
            ChoiceRow<ThemeMode>(
              label: 'Default mode',
              value: theme.defaultMode,
              options: ThemeMode.values,
              labelOf: (m) => _modeLabels[m]!,
              onChanged: (m) => set((t) => t.copyWith(defaultMode: m)),
            ),
            SettingSwitch(
              title: 'Let people choose their own mode',
              subtitle: 'When off, everyone sees the default mode.',
              value: theme.allowUserOverride,
              onChanged: (v) => set((t) => t.copyWith(allowUserOverride: v)),
            ),
          ],
        ),
        SettingsCard(
          title: 'Feel',
          children: [
            ChoiceRow<AppDensity>(
              label: 'Density',
              helper: 'How much room tables, forms and buttons take up.',
              value: theme.density,
              options: AppDensity.values,
              labelOf: (d) => d.label,
              onChanged: (d) => set((t) => t.copyWith(density: d)),
            ),
            const SizedBox(height: 20),
            ChoiceRow<MotionLevel>(
              label: 'Motion',
              helper: _motionHelp[theme.motion],
              value: theme.motion,
              options: MotionLevel.values,
              labelOf: (m) => m.label,
              onChanged: (m) => set((t) => t.copyWith(motion: m)),
            ),
            const SizedBox(height: 20),
            ChoiceRow<CornerStyle>(
              label: 'Corners',
              value: theme.corners,
              options: CornerStyle.values,
              labelOf: (c) => c.label,
              onChanged: (c) => set((t) => t.copyWith(corners: c)),
            ),
            const SizedBox(height: 20),
            ChoiceRow<ChartPaletteStyle>(
              label: 'Chart colours',
              helper: 'Brand uses your brand colour first. Monochrome uses '
                  'shades of it.',
              value: theme.chartPalette,
              options: ChartPaletteStyle.values,
              labelOf: (p) => p.label,
              onChanged: (p) => set((t) => t.copyWith(chartPalette: p)),
            ),
          ],
        ),
        SettingsCard(
          title: 'Preview',
          subtitle: 'How the app looks with these choices.',
          children: [ThemePreviewPane(settings: draft.settings)],
        ),
      ],
    );
  }
}
