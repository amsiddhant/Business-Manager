import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/routing/app_routes.dart';
import '../../core/routing/nav_registry.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_x.dart';
import '../../models/app_settings.dart';
import '../../models/app_user.dart';
import '../../state/app_state.dart';
import '../../state/data_controller.dart';
import '../../state/org_settings.dart';
import '../../state/user_prefs.dart';
import 'app_sidebar.dart';

/// The phone navigation bar: up to four sections plus "More", which opens
/// every other section (grouped as in the sidebar) in a sheet.
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.location,
    required this.onSelect,
  });

  final String location;
  final void Function(String route) onSelect;

  @override
  Widget build(BuildContext context) {
    final user = context.select<AppState, AppUser?>((s) => s.currentUser);
    if (user == null) return const SizedBox.shrink();
    final pending = context.select<DataController, int>(pendingOrderCount);
    final modules = context.orgSettings((s) => s.modules);
    final navigation = context.orgSettings((s) => s.navigation);
    final primary = NavRegistry.mobilePrimary(user,
        modules: modules, navigation: navigation);
    final section = Routes.sectionOf(location);
    final index = primary.indexWhere((d) => d.route == section);

    Widget icon(NavDestination d, IconData data) {
      final i = Icon(data);
      if (d.route != Routes.orders || pending == 0) return i;
      return Badge(label: Text(pending > 99 ? '99+' : '$pending'), child: i);
    }

    return NavigationBar(
      selectedIndex: index < 0 ? primary.length : index,
      onDestinationSelected: (i) {
        if (i < primary.length) {
          onSelect(primary[i].route);
        } else {
          _showMore(context, user, section, primary);
        }
      },
      destinations: [
        for (final d in primary)
          NavigationDestination(
            icon: icon(d, d.icon),
            selectedIcon: icon(d, d.selectedIcon),
            label: d.label,
          ),
        const NavigationDestination(
          icon: Icon(Icons.menu),
          selectedIcon: Icon(Icons.menu_open),
          label: 'More',
        ),
      ],
    );
  }

  Future<void> _showMore(BuildContext context, AppUser user, String? section,
      List<NavDestination> bar) {
    final t = context.tokens;
    final settings = context.readOrgSettings();
    final modules = settings.modules;
    final whatsNewOn = settings.features.isOn(AppFeature.whatsNew);
    final pinned = [
      for (final p in context.read<UserPrefs>().favourites)
        if (modules.allows(p.path)) p,
    ];
    final primary = {for (final d in bar) d.route};
    final router = GoRouter.of(context);

    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) {
        Widget header(String label) => Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl, AppSpacing.md, AppSpacing.xl, AppSpacing.xs),
              child: Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.7,
                  color: t.textTertiary,
                ),
              ),
            );
        Widget tile(IconData icon, String label, bool selected,
                VoidCallback onTap) =>
            ListTile(
              leading: Icon(icon, color: selected ? t.primary : null),
              title: Text(label),
              selected: selected,
              onTap: () {
                Navigator.of(sheet).pop();
                onTap();
              },
            );

        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.92,
          builder: (_, scroll) => ListView(
            controller: scroll,
            padding: const EdgeInsets.only(bottom: AppSpacing.xl),
            children: [
              if (pinned.isNotEmpty) ...[
                header('Pinned'),
                for (final p in pinned)
                  tile(
                    NavRegistry.destinationFor(Routes.sectionOf(p.path) ?? '')
                            ?.icon ??
                        Icons.push_pin_outlined,
                    p.label,
                    false,
                    () => router.go(p.path),
                  ),
              ],
              for (final g in NavRegistry.groupsFor(user, modules: modules))
                if (g.items.where((d) => !primary.contains(d.route)).toList()
                    case final rest when rest.isNotEmpty) ...[
                  header(g.group.label),
                  for (final d in rest)
                    tile(d.icon, d.label, d.route == section,
                        () => onSelect(d.route)),
                ],
              header('App'),
              if (!primary.contains(Routes.settings) &&
                  !NavRegistry.visible(user, modules: modules)
                      .any((d) => d.route == Routes.settings))
                tile(Icons.settings_outlined, 'Settings',
                    section == Routes.settings,
                    () => onSelect(Routes.settings)),
              if (whatsNewOn)
                tile(Icons.new_releases_outlined, "What's new",
                    section == Routes.whatsNew,
                    () => onSelect(Routes.whatsNew)),
            ],
          ),
        );
      },
    );
  }
}
