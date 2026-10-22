import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/routing/app_routes.dart';
import '../../core/routing/nav_registry.dart';
import '../../core/shortcuts.dart';
import '../../core/theme/app_density.dart';
import '../../models/app_user.dart';
import '../../services/search_index.dart';
import '../../state/app_state.dart';
import '../../state/data_controller.dart';
import '../../state/theme_controller.dart';
import '../../state/user_prefs.dart';
import '../layout/create_actions.dart';
import '../layout/shell_nav.dart';

/// Palette sections, in display order.
enum CommandSection {
  recent('Recent'),
  navigate('Go to'),
  create('Create'),
  records('Records'),
  actions('Actions');

  const CommandSection(this.label);
  final String label;
}

/// One row in the command palette.
class PaletteCommand {
  const PaletteCommand({
    required this.id,
    required this.section,
    required this.title,
    required this.icon,
    required this.run,
    this.subtitle,
    this.hint,
    this.keywords = const [],
  });

  /// Stable id, remembered in "Recent" (`nav:/orders`, `rec:/orders/ORD-1`).
  final String id;
  final CommandSection section;
  final String title;
  final String? subtitle;
  final IconData icon;

  /// Right-aligned hint: a shortcut (`G O`) or the record type.
  final String? hint;

  /// Extra words that find this command ("dark" finds "Dark theme").
  final List<String> keywords;

  /// Runs the command. [context] is the shell's (the palette has closed).
  final void Function(BuildContext context) run;

  PaletteCommand inSection(CommandSection s) => PaletteCommand(
        id: id,
        section: s,
        title: title,
        subtitle: subtitle,
        icon: icon,
        hint: hint,
        keywords: keywords,
        run: run,
      );

  /// Match quality for [query] (lower-case), 0 for none.
  int score(String query) {
    var best = SearchIndex.score(query, title.toLowerCase());
    for (final k in keywords) {
      final s = SearchIndex.score(query, k.toLowerCase()) - 10;
      if (s > best) best = s;
    }
    return best;
  }
}

/// Builds the palette's commands for the signed-in user.
class CommandRegistry {
  CommandRegistry(this.context, {this.nav});

  /// The shell's context: commands run against it after the palette closes.
  final BuildContext context;
  final ShellNav? nav;

  void _go(BuildContext c, String route) =>
      ShellNav.navigate(nav, GoRouter.of(c), route);

  /// Shortcut hints for "Go to" commands (see [kGoShortcuts]).
  static String? _goHint(String route) {
    for (final e in kGoShortcuts.entries) {
      if (e.value == route) return 'G ${e.key.keyLabel.toUpperCase()}';
    }
    return null;
  }

  List<PaletteCommand> navigate(AppUser user) => [
        for (final d in NavRegistry.visible(user))
          PaletteCommand(
            id: 'nav:${d.route}',
            section: CommandSection.navigate,
            title: d.label,
            icon: d.icon,
            hint: _goHint(d.route),
            run: (c) => _go(c, d.route),
          ),
        // Settings (profile, password) is open to everyone.
        if (!NavRegistry.visible(user).any((d) => d.route == Routes.settings))
          PaletteCommand(
            id: 'nav:${Routes.settings}',
            section: CommandSection.navigate,
            title: 'Settings',
            icon: Icons.settings_outlined,
            hint: _goHint(Routes.settings),
            keywords: const ['profile', 'password'],
            run: (c) => _go(c, Routes.settings),
          ),
        PaletteCommand(
          id: 'nav:${Routes.whatsNew}',
          section: CommandSection.navigate,
          title: "What's new",
          icon: Icons.new_releases_outlined,
          keywords: const ['release notes', 'changelog', 'version'],
          run: (c) => _go(c, Routes.whatsNew),
        ),
      ];

  List<PaletteCommand> create(AppUser user) => [
        for (final a in createActionsFor(user))
          PaletteCommand(
            id: 'create:${a.section}',
            section: CommandSection.create,
            title: a.label,
            icon: a.icon,
            keywords: const ['add', 'new', 'create'],
            run: (c) => a.run(c),
          ),
      ];

  List<PaletteCommand> actions() {
    final theme = context.read<ThemeController>();
    final prefs = context.read<UserPrefs>();
    return [
      if (theme.canChooseMode) ...[
        PaletteCommand(
          id: 'act:theme.light',
          section: CommandSection.actions,
          title: 'Light theme',
          icon: Icons.light_mode_outlined,
          keywords: const ['theme', 'appearance', 'mode'],
          run: (c) => c.read<UserPrefs>().setThemeMode(ThemeMode.light),
        ),
        PaletteCommand(
          id: 'act:theme.dark',
          section: CommandSection.actions,
          title: 'Dark theme',
          icon: Icons.dark_mode_outlined,
          keywords: const ['theme', 'appearance', 'night', 'mode'],
          run: (c) => c.read<UserPrefs>().setThemeMode(ThemeMode.dark),
        ),
        PaletteCommand(
          id: 'act:theme.system',
          section: CommandSection.actions,
          title: 'Match device theme',
          icon: Icons.contrast,
          keywords: const ['theme', 'system', 'auto', 'appearance'],
          run: (c) => c.read<UserPrefs>().setThemeMode(ThemeMode.system),
        ),
      ],
      for (final d in AppDensity.values)
        PaletteCommand(
          id: 'act:density.${d.name}',
          section: CommandSection.actions,
          title: '${d.label} density',
          icon: Icons.density_medium,
          keywords: const ['density', 'spacing', 'compact', 'layout'],
          run: (c) => c.read<UserPrefs>().setDensity(d),
        ),
      PaletteCommand(
        id: 'act:motion',
        section: CommandSection.actions,
        title: prefs.reduceMotion ? 'Turn animations back on' : 'Reduce motion',
        icon: Icons.animation,
        keywords: const ['animation', 'motion', 'accessibility'],
        run: (c) {
          final p = c.read<UserPrefs>();
          p.setReduceMotion(!p.reduceMotion);
        },
      ),
      PaletteCommand(
        id: 'act:sync',
        section: CommandSection.actions,
        title: 'Sync now',
        icon: Icons.sync,
        keywords: const ['refresh', 'reload', 'update'],
        run: (c) => c.read<DataController>().sync(),
      ),
      PaletteCommand(
        id: 'act:sidebar',
        section: CommandSection.actions,
        title: prefs.sidebarCollapsed ? 'Expand sidebar' : 'Collapse sidebar',
        icon: Icons.view_sidebar_outlined,
        keywords: const ['sidebar', 'menu', 'navigation'],
        run: (c) {
          final p = c.read<UserPrefs>();
          p.setSidebarCollapsed(!p.sidebarCollapsed);
        },
      ),
      PaletteCommand(
        id: 'act:shortcuts',
        section: CommandSection.actions,
        title: 'Keyboard shortcuts',
        icon: Icons.keyboard_outlined,
        hint: '?',
        keywords: const ['help', 'keys', 'hotkeys'],
        run: showShortcutsHelp,
      ),
      PaletteCommand(
        id: 'act:signout',
        section: CommandSection.actions,
        title: 'Sign out',
        icon: Icons.logout,
        keywords: const ['log out', 'logout', 'exit'],
        run: (c) => c.read<AppState>().signOut(),
      ),
    ];
  }

  /// A record search hit as a command.
  PaletteCommand record(SearchHit hit) => PaletteCommand(
        id: 'rec:${hit.route}',
        section: CommandSection.records,
        title: hit.title,
        subtitle: hit.subtitle,
        icon: hit.icon,
        hint: hit.type,
        run: (c) => _go(c, hit.route),
      );

  /// Every non-record command (navigate, create, actions).
  List<PaletteCommand> all(AppUser user) =>
      [...navigate(user), ...create(user), ...actions()];

  /// The remembered recent commands that still exist, newest first.
  List<PaletteCommand> recent(
      AppUser user, List<String> ids, SearchIndex index) {
    final byId = {for (final c in all(user)) c.id: c};
    return [
      for (final id in ids)
        if (byId[id] case final c?)
          c.inSection(CommandSection.recent)
        else if (id.startsWith('rec:'))
          if (index.byRoute(id.substring(4)) case final hit?)
            record(hit).inSection(CommandSection.recent),
    ];
  }
}
