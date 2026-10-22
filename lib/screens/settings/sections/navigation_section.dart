import 'package:flutter/material.dart';

import '../../../core/routing/app_routes.dart';
import '../../../core/routing/nav_registry.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_x.dart';
import '../../../models/app_settings.dart';
import '../../../widgets/forms/form_fields.dart';
import '../settings_draft.dart';
import '../settings_widgets.dart';

/// Where people land, and what's on the phone's bottom bar.
class NavigationSection extends StatelessWidget {
  const NavigationSection({super.key, required this.draft});

  final SettingsDraft draft;

  static String _label(String route) =>
      NavRegistry.destinationFor(route)?.label ?? route;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final s = draft.settings;
    final nav = s.navigation;

    // Sections people can land on or pin: on, and not the admin pages.
    final choices = [
      for (final d in kNavDestinations)
        if (d.route != Routes.settings &&
            !d.ownerOnly &&
            s.modules.isEnabled(d.route))
          d.route,
    ];
    final landing =
        choices.contains(nav.landingRoute) ? nav.landingRoute : Routes.dashboard;
    final bar = nav.mobilePrimary;

    void set(NavigationSettings Function(NavigationSettings n) change) =>
        draft.update((s) => s.copyWith(navigation: change(s.navigation)));

    void move(int from, int to) {
      final next = [...bar];
      next.insert(to, next.removeAt(from));
      set((n) => n.copyWith(mobilePrimary: next));
    }

    return SettingsPanel(
      title: 'Navigation',
      subtitle: 'Where people land and what is on the phone’s bottom bar',
      onReset: () =>
          draft.resetSection((s, d) => s.copyWith(navigation: d.navigation)),
      children: [
        SettingsCard(
          title: 'Landing page',
          subtitle: 'The page people see right after signing in.',
          children: [
            SettingsGrid(children: [
              AppDropdown<String>(
                label: 'Landing page',
                value: landing,
                items: choices,
                itemLabel: _label,
                onChanged: (v) =>
                    set((n) => n.copyWith(landingRoute: v ?? Routes.dashboard)),
              ),
            ]),
            if (nav.landingRoute != landing) ...[
              const SizedBox(height: AppSpacing.md),
              SettingsNote(
                '${_label(nav.landingRoute)} is switched off, so people land on '
                'the dashboard instead.',
                tone: SettingsNoteTone.warning,
              ),
            ],
          ],
        ),
        SettingsCard(
          title: 'Phone bottom bar',
          subtitle: 'Pick up to ${NavigationSettings.maxMobileItems} sections, '
              'in order. Everything else is under “More”.',
          trailing: bar.isEmpty
              ? null
              : TextButton(
                  onPressed: () => set((n) => n.copyWith(mobilePrimary: [])),
                  child: const Text('Use default'),
                ),
          children: [
            if (bar.isEmpty)
              Text(
                'Using the built-in bar: '
                '${kMobilePrimaryRoutes.map(_label).join(', ')}.',
                style: TextStyle(fontSize: 13, color: t.textSecondary),
              )
            else
              for (var i = 0; i < bar.length; i++)
                _BarItem(
                  label: _label(bar[i]),
                  icon: NavRegistry.destinationFor(bar[i])?.icon ??
                      Icons.apps_outlined,
                  onUp: i == 0 ? null : () => move(i, i - 1),
                  onDown: i == bar.length - 1 ? null : () => move(i, i + 1),
                  onRemove: () => set((n) => n.copyWith(
                      mobilePrimary: [...bar]..removeAt(i))),
                ),
            const SizedBox(height: AppSpacing.md),
            Text('Add a section',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: t.textSecondary)),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final route in choices)
                  if (!bar.contains(route))
                    ActionChip(
                      avatar: const Icon(Icons.add, size: 16),
                      label: Text(_label(route)),
                      onPressed:
                          bar.length >= NavigationSettings.maxMobileItems
                              ? null
                              : () => set((n) =>
                                  n.copyWith(mobilePrimary: [...bar, route])),
                    ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class _BarItem extends StatelessWidget {
  const _BarItem({
    required this.label,
    required this.icon,
    required this.onUp,
    required this.onDown,
    required this.onRemove,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        color: t.surfaceAlt,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: t.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: t.textSecondary),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text(label)),
          IconButton(
            tooltip: 'Move $label up',
            onPressed: onUp,
            icon: const Icon(Icons.arrow_upward, size: 18),
          ),
          IconButton(
            tooltip: 'Move $label down',
            onPressed: onDown,
            icon: const Icon(Icons.arrow_downward, size: 18),
          ),
          IconButton(
            tooltip: 'Remove $label',
            onPressed: onRemove,
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }
}
