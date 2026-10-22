import 'package:flutter/material.dart';

import '../../../core/routing/app_routes.dart';
import '../../../core/routing/nav_registry.dart';
import '../../../core/theme/theme_x.dart';
import '../../../models/app_settings.dart';
import '../settings_draft.dart';
import '../settings_widgets.dart';

/// Which sections of the app are switched on.
class ModulesSection extends StatelessWidget {
  const ModulesSection({super.key, required this.draft});

  final SettingsDraft draft;

  static (String, IconData) _look(String route) {
    final d = NavRegistry.destinationFor(route);
    if (d != null) return (d.label, d.icon);
    return route == Routes.whatsNew
        ? ('What’s new', Icons.new_releases_outlined)
        : (route, Icons.apps_outlined);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final modules = draft.settings.modules;
    return SettingsPanel(
      title: 'Modules',
      subtitle: 'Switch sections on or off for everyone',
      onReset: () =>
          draft.resetSection((s, d) => s.copyWith(modules: d.modules)),
      children: [
        const SettingsNote(
          'Hiding a module only hides its menus and pages. Totals on the '
          'dashboard and in reports still include its data.',
        ),
        SettingsCard(
          title: 'Sections',
          children: [
            for (final route in ModuleSettings.optional)
              Builder(builder: (context) {
                final (label, icon) = _look(route);
                return SettingSwitch(
                  title: label,
                  leading: Icon(icon, color: t.textSecondary),
                  value: modules.isEnabled(route),
                  onChanged: (on) => draft.update((s) => s.copyWith(
                      modules: s.modules.toggle(route, enabled: on))),
                );
              }),
          ],
        ),
        SettingsCard(
          title: 'Always on',
          subtitle: 'These can’t be switched off.',
          children: [
            for (final route in ModuleSettings.alwaysOn)
              Builder(builder: (context) {
                final (label, icon) = _look(route);
                return SettingSwitch(
                  title: label,
                  subtitle: 'Always on',
                  leading: Icon(icon, color: t.textTertiary),
                  value: true,
                  onChanged: null,
                );
              }),
          ],
        ),
      ],
    );
  }
}
