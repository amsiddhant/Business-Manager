import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/routing/app_routes.dart';
import '../../core/shortcuts.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_x.dart';
import '../../models/app_settings.dart';
import '../../models/app_user.dart';
import '../../state/app_state.dart';
import '../../state/data_controller.dart';
import '../../state/org_settings.dart';
import '../../state/theme_controller.dart';
import '../../state/user_prefs.dart';
import '../common/initials_avatar.dart';
import '../common/status_badge.dart';
import 'shell_nav.dart';

/// The avatar menu: Settings, What's new, shortcuts, theme and sign out.
class ProfileMenu extends StatelessWidget {
  const ProfileMenu({super.key, this.showSync = false});

  /// Adds "Sync now" (for layouts without the sync button).
  final bool showSync;

  @override
  Widget build(BuildContext context) {
    final user = context.select<AppState, AppUser?>((s) => s.currentUser);
    if (user == null) return const SizedBox.shrink();
    final theme = context.watch<ThemeController>();
    final chosen = context.select<UserPrefs, ThemeMode?>((p) => p.themeMode) ??
        theme.org.defaultMode;
    final t = context.tokens;
    final whatsNewOn =
        context.orgSettings((s) => s.features.isOn(AppFeature.whatsNew));

    Widget check(bool on) =>
        Icon(Icons.check, size: 18, color: on ? t.primary : Colors.transparent);

    return MenuAnchor(
      alignmentOffset: const Offset(0, 6),
      builder: (context, controller, _) => Tooltip(
        message: 'Account',
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () =>
              controller.isOpen ? controller.close() : controller.open(),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: InitialsAvatar(name: user.name, size: 34),
          ),
        ),
      ),
      menuChildren: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.md),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 220, maxWidth: 280),
            child: Row(
              children: [
                InitialsAvatar(name: user.name, size: 40),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: t.textPrimary)),
                      Text(user.email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12, color: t.textSecondary)),
                      const SizedBox(height: 4),
                      StatusBadge.role(user.role),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        MenuItemButton(
          leadingIcon: const Icon(Icons.settings_outlined, size: 20),
          onPressed: () => ShellNav.go(context, Routes.settings),
          child: const Text('Settings'),
        ),
        if (whatsNewOn)
          MenuItemButton(
            leadingIcon: const Icon(Icons.new_releases_outlined, size: 20),
            onPressed: () => ShellNav.go(context, Routes.whatsNew),
            child: const Text("What's new"),
          ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.keyboard_outlined, size: 20),
          onPressed: () => showShortcutsHelp(context),
          trailingIcon: Text('?', style: TextStyle(color: t.textTertiary)),
          child: const Text('Keyboard shortcuts'),
        ),
        if (showSync)
          MenuItemButton(
            leadingIcon: const Icon(Icons.sync, size: 20),
            onPressed: () => context.read<DataController>().sync(),
            child: const Text('Sync now'),
          ),
        if (theme.canChooseMode)
          SubmenuButton(
            leadingIcon: const Icon(Icons.contrast, size: 20),
            menuChildren: [
              for (final (mode, label) in const [
                (ThemeMode.light, 'Light'),
                (ThemeMode.dark, 'Dark'),
                (ThemeMode.system, 'Match my device'),
              ])
                MenuItemButton(
                  leadingIcon: check(chosen == mode),
                  onPressed: () =>
                      context.read<UserPrefs>().setThemeMode(mode),
                  child: Text(label),
                ),
            ],
            child: const Text('Theme'),
          ),
        const Divider(height: 1),
        MenuItemButton(
          leadingIcon: const Icon(Icons.logout, size: 20),
          onPressed: () => context.read<AppState>().signOut(),
          child: const Text('Sign out'),
        ),
      ],
    );
  }
}
