import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/routing/app_routes.dart';
import '../../core/routing/nav_registry.dart';
import '../../core/shortcuts.dart';
import '../../core/theme/theme_x.dart';
import '../../models/app_user.dart';
import '../../state/app_state.dart';
import '../../state/user_prefs.dart';
import '../common/responsive.dart';
import 'app_bottom_nav.dart';
import 'app_sidebar.dart';
import 'app_top_bar.dart';
import 'create_actions.dart';
import 'shell_nav.dart';
import 'whats_new_prompt.dart';

/// The signed-in frame around every page:
///
/// * desktop: the grouped sidebar (collapsible) + top bar;
/// * tablet: an icon rail (its menu button opens the full sidebar) + top bar;
/// * phone: top bar + bottom navigation, with a "new" button on list pages.
///
/// [navigationShell] holds one navigator per section, so each section keeps
/// its place while you're elsewhere.
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.navigationShell,
    required this.location,
  });

  final StatefulNavigationShell navigationShell;

  /// The current location (path + query).
  final String location;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final _scaffold = GlobalKey<ScaffoldState>();

  /// Opens a section: back where you left it, or its list if you're in it.
  void _goSection(String route) {
    final i = NavRegistry.branchIndexOf(route);
    if (i == null || Routes.sectionOf(route) != route) {
      context.go(route);
      return;
    }
    final shell = widget.navigationShell;
    shell.goBranch(i, initialLocation: i == shell.currentIndex);
  }

  @override
  Widget build(BuildContext context) {
    final type = Responsive.of(context);
    final location = widget.location;
    final collapsed =
        context.select<UserPrefs, bool>((p) => p.sidebarCollapsed);

    final page = Column(
      children: [
        AppTopBar(location: location, mobile: type == ScreenType.mobile),
        const WhatsNewPrompt(),
        // Each page owns its scrolling (AppPage / DetailPage).
        Expanded(child: widget.navigationShell),
      ],
    );

    final Widget body = switch (type) {
      ScreenType.desktop => Row(
          children: [
            AppSidebar(
              location: location,
              onSelect: _goSection,
              collapsed: collapsed,
              onToggle: () =>
                  context.read<UserPrefs>().setSidebarCollapsed(!collapsed),
            ),
            Expanded(child: page),
          ],
        ),
      ScreenType.tablet => Row(
          children: [
            AppSidebar(
              location: location,
              onSelect: _goSection,
              collapsed: true,
              toggleOpensMenu: true,
              onToggle: () => _scaffold.currentState?.openDrawer(),
            ),
            Expanded(child: page),
          ],
        ),
      ScreenType.mobile => page,
    };

    return ShellNav(
      location: location,
      goSection: _goSection,
      child: AppShortcuts(
        location: location,
        child: Scaffold(
          key: _scaffold,
          backgroundColor: context.tokens.background,
          drawer: type == ScreenType.tablet
              ? Drawer(
                  width: AppSidebar.expandedWidth,
                  child: Builder(
                    builder: (drawer) => AppSidebar(
                      location: location,
                      onSelect: _goSection,
                      onNavigate: () => Navigator.of(drawer).maybePop(),
                    ),
                  ),
                )
              : null,
          body: SafeArea(child: body),
          bottomNavigationBar: type == ScreenType.mobile
              ? AppBottomNav(location: location, onSelect: _goSection)
              : null,
          floatingActionButton: type == ScreenType.mobile
              ? _CreateFab(location: location)
              : null,
        ),
      ),
    );
  }
}

/// The phone's "new" button, on section list pages that have one.
class _CreateFab extends StatelessWidget {
  const _CreateFab({required this.location});

  final String location;

  @override
  Widget build(BuildContext context) {
    if (!NavRegistry.isSectionRoot(location)) return const SizedBox.shrink();
    final user = context.select<AppState, AppUser?>((s) => s.currentUser);
    final action = createActionForLocation(user, location);
    if (action == null) return const SizedBox.shrink();
    return FloatingActionButton(
      tooltip: action.label,
      onPressed: () => action.run(context),
      child: const Icon(Icons.add),
    );
  }
}
