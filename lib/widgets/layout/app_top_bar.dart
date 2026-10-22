import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/routing/nav_registry.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_x.dart';
import '../../models/app_user.dart';
import '../../state/app_state.dart';
import '../../state/data_controller.dart';
import '../../state/user_prefs.dart';
import '../command_palette/command_palette.dart';
import 'create_actions.dart';
import 'notifications_button.dart';
import 'page_title.dart';
import 'profile_menu.dart';
import 'scope_selectors.dart';
import 'shell_nav.dart';
import 'sync_status.dart';

/// The bar above every page: where you are (breadcrumbs), the scope the page
/// uses, search (command palette), quick create, sync, alerts and account.
class AppTopBar extends StatelessWidget {
  const AppTopBar({super.key, required this.location, this.mobile = false});

  final String location;

  /// Phone layout: back/title, icons, and the scope as a pill underneath.
  final bool mobile;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final title = context.select<DataController, PageTitle>(
      (d) => PageTitle.of(d, location),
    );
    final scope = NavRegistry.scopeFor(location);

    final bar = mobile
        ? _MobileBar(title: title, scope: scope)
        : LayoutBuilder(
            builder: (context, c) => _WideBar(
              title: title,
              scope: scope,
              location: location,
              width: c.maxWidth,
            ),
          );

    return Material(
      color: t.card,
      child: Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: t.border)),
        ),
        child: bar,
      ),
    );
  }
}

class _WideBar extends StatelessWidget {
  const _WideBar({
    required this.title,
    required this.scope,
    required this.location,
    required this.width,
  });

  final PageTitle title;
  final ScopeUse scope;
  final String location;
  final double width;

  @override
  Widget build(BuildContext context) {
    final wide = width >= 1100;
    final inlineScope = width >= 820;
    return SizedBox(
      height: 64,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Row(
          children: [
            Expanded(child: _Breadcrumbs(title: title, location: location)),
            if (scope != ScopeUse.none) ...[
              const SizedBox(width: AppSpacing.md),
              inlineScope
                  ? ScopeSelectors(use: scope)
                  // Shrinks (with ellipses) before the actions do.
                  : Flexible(flex: 2, child: ScopePill(use: scope)),
            ],
            const SizedBox(width: AppSpacing.md),
            wide
                ? const _PaletteField()
                : IconButton(
                    tooltip: 'Search ($paletteShortcutLabel)',
                    icon: const Icon(Icons.search),
                    onPressed: () => CommandPalette.show(context),
                  ),
            const SizedBox(width: AppSpacing.xs),
            _CreateMenu(location: location, compact: !wide),
            SyncStatus(showLabel: width >= 1400),
            const NotificationsButton(),
            const SizedBox(width: AppSpacing.xs),
            const ProfileMenu(),
          ],
        ),
      ),
    );
  }
}

class _MobileBar extends StatelessWidget {
  const _MobileBar({required this.title, required this.scope});

  final PageTitle title;
  final ScopeUse scope;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 56,
          child: Row(
            children: [
              if (title.isDetail && title.sectionRoute != null)
                IconButton(
                  tooltip: 'Back to ${title.section}',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => context.go(title.sectionRoute!),
                )
              else
                const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Text(
                  title.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: t.textPrimary,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Search',
                icon: const Icon(Icons.search),
                onPressed: () => CommandPalette.show(context),
              ),
              const NotificationsButton(),
              const ProfileMenu(showSync: true),
              const SizedBox(width: AppSpacing.xs),
            ],
          ),
        ),
        if (scope != ScopeUse.none)
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.sm),
            child: ScopePill(use: scope, expand: true),
          ),
      ],
    );
  }
}

class _Breadcrumbs extends StatelessWidget {
  const _Breadcrumbs({required this.title, required this.location});

  final PageTitle title;
  final String location;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final strong = TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w700,
      color: t.textPrimary,
    );
    if (!title.isDetail) {
      return Text(title.section,
          maxLines: 1, overflow: TextOverflow.ellipsis, style: strong);
    }
    final path = Uri.tryParse(location)?.path ?? location;
    return Row(
      children: [
        Flexible(
          flex: 0,
          child: TextButton(
            onPressed: () => ShellNav.go(context, title.sectionRoute!),
            style: TextButton.styleFrom(
              foregroundColor: t.textSecondary,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              textStyle:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            ),
            child: Text(title.section),
          ),
        ),
        Icon(Icons.chevron_right, size: 18, color: t.textTertiary),
        const SizedBox(width: AppSpacing.xs),
        Flexible(
          child: Text(title.record!,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: strong),
        ),
        _PinButton(path: path, label: title.label),
      ],
    );
  }
}

class _PinButton extends StatelessWidget {
  const _PinButton({required this.path, required this.label});

  final String path;
  final String label;

  @override
  Widget build(BuildContext context) {
    final pinned = context.select<UserPrefs, bool>((p) => p.isFavourite(path));
    final t = context.tokens;
    return IconButton(
      tooltip: pinned ? 'Unpin from sidebar' : 'Pin to sidebar',
      onPressed: () => context.read<UserPrefs>().toggleFavourite(path, label),
      icon: Icon(
        pinned ? Icons.push_pin : Icons.push_pin_outlined,
        size: 18,
        color: pinned ? t.primary : t.textTertiary,
      ),
    );
  }
}

class _PaletteField extends StatelessWidget {
  const _PaletteField();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      button: true,
      label: 'Search or jump to, $paletteShortcutLabel',
      excludeSemantics: true,
      child: Material(
        color: t.surfaceAlt,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: t.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => CommandPalette.show(context),
          child: SizedBox(
            width: 230,
            height: 38,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Row(
                children: [
                  Icon(Icons.search, size: 18, color: t.textTertiary),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Search or jump to…',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13.5, color: t.textTertiary),
                    ),
                  ),
                  KeyHint(paletteShortcutLabel),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "+ New": every create action the user may use, this section's first.
class _CreateMenu extends StatelessWidget {
  const _CreateMenu({required this.location, required this.compact});

  final String location;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final user = context.select<AppState, AppUser?>((s) => s.currentUser);
    final actions = createActionsFor(user);
    if (actions.isEmpty) return const SizedBox.shrink();
    final primary = createActionForLocation(user, location);
    final ordered = [?primary, ...actions.where((a) => a != primary)];

    return MenuAnchor(
      alignmentOffset: const Offset(0, 6),
      menuChildren: [
        for (final a in ordered)
          MenuItemButton(
            leadingIcon: Icon(a.icon, size: 20),
            shortcut: a == primary
                ? const SingleActivator(LogicalKeyboardKey.keyN)
                : null,
            onPressed: () => a.run(context),
            child: Text(a.label),
          ),
      ],
      builder: (context, controller, _) {
        void toggle() =>
            controller.isOpen ? controller.close() : controller.open();
        return compact
            ? IconButton.filledTonal(
                tooltip: 'Create',
                onPressed: toggle,
                icon: const Icon(Icons.add),
              )
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                child: FilledButton.tonalIcon(
                  onPressed: toggle,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('New'),
                ),
              );
      },
    );
  }
}
