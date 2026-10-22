import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/app_info.dart';
import '../../core/enums.dart';
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
import '../common/initials_avatar.dart';
import '../common/org_logo.dart';
import '../common/status_badge.dart';
import 'theme_toggle_button.dart';

/// Pending orders, for the Orders badge.
int pendingOrderCount(DataController d) =>
    d.orders.where((o) => o.status == OrderStatus.pending).length;

/// The grouped side navigation: inline on desktop (collapsible to an icon
/// rail), a rail on tablet, and the drawer body.
class AppSidebar extends StatelessWidget {
  const AppSidebar({
    super.key,
    required this.location,
    required this.onSelect,
    this.collapsed = false,
    this.onToggle,
    this.toggleOpensMenu = false,
    this.onNavigate,
  });

  /// The current location; its section is highlighted.
  final String location;

  /// Opens a section root (e.g. `/orders`).
  final void Function(String route) onSelect;

  /// Icon-only rail (72 px) instead of the full sidebar (248 px).
  final bool collapsed;

  /// Collapses / expands the sidebar, or opens the full menu (tablet).
  final VoidCallback? onToggle;

  /// The toggle opens the full menu (tablet) rather than expanding in place.
  final bool toggleOpensMenu;

  /// Called after any navigation, e.g. to close a drawer.
  final VoidCallback? onNavigate;

  static const double expandedWidth = 248;
  static const double collapsedWidth = 72;

  @override
  Widget build(BuildContext context) {
    final user = context.select<AppState, AppUser?>((s) => s.currentUser);
    if (user == null) return const SizedBox.shrink();
    final appName = context.select<AppState, String>((s) => s.appName);
    final pending = context.select<DataController, int>(pendingOrderCount);
    final modules = context.orgSettings((s) => s.modules);
    final shortName = context.orgSettings((s) => s.branding.shortName);
    final whatsNewOn =
        context.orgSettings((s) => s.features.isOn(AppFeature.whatsNew));
    final pinned = context
        .select<UserPrefs, List<PinnedPage>>((p) => p.favourites)
        .where((p) => modules.allows(p.path))
        .toList();
    final t = context.tokens;
    final section = Routes.sectionOf(location);
    final path = Uri.tryParse(location)?.path ?? location;

    return AnimatedContainer(
      duration: context.motion.base,
      curve: AppMotion.standard,
      width: collapsed ? collapsedWidth : expandedWidth,
      decoration: BoxDecoration(
        color: t.sidebar,
        border: Border(right: BorderSide(color: t.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Labels appear once there's room (also mid-animation).
          final wide = constraints.maxWidth >= 200;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(
                appName: appName,
                shortName: shortName,
                wide: wide,
                onToggle: onToggle,
                toggleOpensMenu: toggleOpensMenu,
              ),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.symmetric(
                    horizontal: wide ? AppSpacing.md : AppSpacing.sm,
                    vertical: AppSpacing.sm,
                  ),
                  children: [
                    if (pinned.isNotEmpty) ...[
                      _GroupLabel('Pinned', wide: wide),
                      for (final p in pinned)
                        _NavTile(
                          icon: NavRegistry.destinationFor(
                                      Routes.sectionOf(p.path) ?? '')
                                  ?.icon ??
                              Icons.push_pin_outlined,
                          selectedIcon: Icons.push_pin,
                          label: p.label,
                          wide: wide,
                          selected: path == p.path,
                          onTap: () {
                            onNavigate?.call();
                            context.go(p.path);
                          },
                          onRemove: () => context
                              .read<UserPrefs>()
                              .toggleFavourite(p.path, p.label),
                        ),
                    ],
                    for (final g in NavRegistry.groupsFor(user, modules: modules)) ...[
                      _GroupLabel(g.group.label, wide: wide),
                      for (final d in g.items)
                        _NavTile(
                          icon: d.icon,
                          selectedIcon: d.selectedIcon,
                          label: d.label,
                          wide: wide,
                          selected: section == d.route,
                          badge: d.route == Routes.orders && pending > 0
                              ? pending
                              : null,
                          badgeTooltip: '$pending pending',
                          onTap: () {
                            onNavigate?.call();
                            onSelect(d.route);
                          },
                        ),
                    ],
                  ],
                ),
              ),
              Divider(height: 1, color: t.border),
              _Footer(
                user: user,
                wide: wide,
                showWhatsNew: whatsNewOn,
                onWhatsNew: () {
                  onNavigate?.call();
                  onSelect(Routes.whatsNew);
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.appName,
    required this.shortName,
    required this.wide,
    required this.onToggle,
    required this.toggleOpensMenu,
  });

  final String appName;

  /// Shown under the mark when the sidebar is collapsed (empty = nothing).
  final String shortName;
  final bool wide;
  final VoidCallback? onToggle;
  final bool toggleOpensMenu;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final logo = OrgLogo.has(context)
        ? const OrgLogo(size: 34)
        : null;
    final mark = logo ??
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [t.primary, t.primaryDark],
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child:
              Icon(Icons.insights_rounded, color: t.textOnPrimary, size: 20),
        );
    final toggle = onToggle == null
        ? null
        : IconButton(
            tooltip: toggleOpensMenu
                ? 'Open menu'
                : (wide ? 'Collapse sidebar' : 'Expand sidebar'),
            onPressed: onToggle,
            icon: Icon(
              toggleOpensMenu
                  ? Icons.menu
                  : (wide
                      ? Icons.keyboard_double_arrow_left
                      : Icons.keyboard_double_arrow_right),
              size: 20,
              color: t.textSecondary,
            ),
          );

    if (!wide) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Column(
          children: [
            Tooltip(message: appName, child: mark),
            if (shortName.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(
                    top: AppSpacing.xs, left: AppSpacing.xs, right: AppSpacing.xs),
                child: Text(
                  shortName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: t.textSecondary,
                  ),
                ),
              ),
            if (toggle != null) ...[
              const SizedBox(height: AppSpacing.xs),
              toggle,
            ],
          ],
        ),
      );
    }
    return SizedBox(
      height: 64,
      child: Padding(
        padding: const EdgeInsets.only(left: AppSpacing.lg, right: 4),
        child: Row(
          children: [
            mark,
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                appName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                  color: t.textPrimary,
                ),
              ),
            ),
            ?toggle,
          ],
        ),
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.label, {required this.wide});

  final String label;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    if (!wide) {
      return Padding(
        padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.sm, horizontal: AppSpacing.md),
        child: Divider(height: 1, color: t.border),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xs),
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
  }
}

class _NavTile extends StatefulWidget {
  const _NavTile({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.wide,
    required this.selected,
    required this.onTap,
    this.badge,
    this.badgeTooltip,
    this.onRemove,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool wide;
  final bool selected;
  final VoidCallback onTap;
  final int? badge;
  final String? badgeTooltip;

  /// Shows an unpin button on hover.
  final VoidCallback? onRemove;

  @override
  State<_NavTile> createState() => _NavTileState();
}

class _NavTileState extends State<_NavTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final selected = widget.selected;
    final fg = selected ? t.primary : t.textSecondary;
    final bg = selected
        ? t.primaryLight
        : (_hover ? t.hover : t.primaryLight.withValues(alpha: 0));
    final badge = widget.badge;

    Widget icon = Icon(selected ? widget.selectedIcon : widget.icon,
        size: 20, color: fg);
    if (badge != null && !widget.wide) {
      icon = Badge(smallSize: 8, backgroundColor: t.warning, child: icon);
    }

    final content = widget.wide
        ? Row(
            children: [
              icon,
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? t.primary : t.textPrimary,
                  ),
                ),
              ),
              if (widget.onRemove != null && _hover)
                Tooltip(
                  message: 'Unpin',
                  child: InkResponse(
                    onTap: widget.onRemove,
                    radius: 14,
                    child: Icon(Icons.close, size: 16, color: t.textTertiary),
                  ),
                )
              else if (badge != null)
                Tooltip(
                  message: widget.badgeTooltip ?? '',
                  child: _CountPill(count: badge),
                ),
            ],
          )
        : Center(child: icon);

    final tile = Semantics(
      button: true,
      selected: selected,
      label: badge == null ? widget.label : '${widget.label}, $badge pending',
      excludeSemantics: true,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: AnimatedContainer(
          duration: context.motion.fast,
          height: 40,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: widget.wide ? AppSpacing.md : 0),
                child: content,
              ),
            ),
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: widget.wide
          ? tile
          : Tooltip(
              message: widget.label,
              waitDuration: const Duration(milliseconds: 300),
              child: tile,
            ),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      constraints: const BoxConstraints(minWidth: 22),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: t.warningSurface,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: t.warning,
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.user,
    required this.wide,
    required this.onWhatsNew,
    this.showWhatsNew = true,
  });

  final AppUser user;
  final bool wide;
  final VoidCallback onWhatsNew;

  /// False when the organisation switched "What's new" off: the version
  /// stays, the link goes.
  final bool showWhatsNew;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final signOut = IconButton(
      tooltip: 'Sign out',
      icon: const Icon(Icons.logout, size: 19),
      onPressed: () => context.read<AppState>().signOut(),
    );

    if (!wide) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Column(
          children: [
            const ThemeToggleButton(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Tooltip(
                message: '${user.name} · ${user.role.label}',
                child: InitialsAvatar(name: user.name, size: 34),
              ),
            ),
            signOut,
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xs),
      child: Column(
        children: [
          Row(
            children: [
              InitialsAvatar(name: user.name, size: 36),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: t.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    StatusBadge.role(user.role),
                  ],
                ),
              ),
              const ThemeToggleButton(size: 19),
              signOut,
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          if (showWhatsNew)
            TextButton(
              onPressed: onWhatsNew,
              style: TextButton.styleFrom(
                foregroundColor: t.textTertiary,
                textStyle: const TextStyle(fontSize: 12),
                visualDensity: VisualDensity.compact,
              ),
              child: const Text("Version $kAppVersion · What's new"),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Text('Version $kAppVersion',
                  style: TextStyle(fontSize: 12, color: t.textTertiary)),
            ),
        ],
      ),
    );
  }
}
