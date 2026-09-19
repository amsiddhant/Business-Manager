import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../state/app_state.dart';
import '../../state/data_controller.dart';
import '../common/responsive.dart';
import 'business_selector.dart';
import 'global_search.dart';
import 'period_selector.dart';

/// The top application bar: menu (mobile), business selector, period selector,
/// search, notifications and the user profile menu (spec §4).
class AppHeader extends StatelessWidget implements PreferredSizeWidget {
  const AppHeader({super.key, this.onMenuTap});

  final VoidCallback? onMenuTap;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);
    final isMobile = Responsive.isMobile(context);

    return Container(
      height: 64,
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Row(
        children: [
          if (!isDesktop)
            IconButton(
              icon: const Icon(Icons.menu),
              onPressed: onMenuTap,
              tooltip: 'Menu',
            ),
          if (!isMobile) ...[
            const BusinessSelector(),
            const SizedBox(width: AppSpacing.sm),
            const PeriodSelector(),
          ],
          const Spacer(),
          IconButton(
            tooltip: 'Search',
            icon: const Icon(Icons.search),
            onPressed: () => _openSearch(context),
          ),
          _NotificationsButton(),
          const SizedBox(width: AppSpacing.xs),
          _ProfileMenu(),
        ],
      ),
    );
  }

  void _openSearch(BuildContext context) {
    final data = context.read<DataController>();
    showSearch<void>(
      context: context,
      delegate: GlobalSearchDelegate(
        data,
        businessName: (id) => data.businessById(id)?.name,
      ),
    );
  }
}

/// A compact secondary bar shown on mobile with the business + period selectors
/// (which don't fit in the top bar on small screens).
class MobileFilterBar extends StatelessWidget {
  const MobileFilterBar({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Responsive.isMobile(context)) return const SizedBox.shrink();
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.sm),
      child: Row(
        children: const [
          Expanded(child: BusinessSelector()),
          SizedBox(width: AppSpacing.sm),
          PeriodSelector(),
        ],
      ),
    );
  }
}

class _NotificationsButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final data = context.watch<DataController>();
    final notes = _notifications(appState, data);

    return PopupMenuButton<void>(
      tooltip: 'Notifications',
      offset: const Offset(0, 48),
      constraints: const BoxConstraints(minWidth: 300, maxWidth: 360),
      itemBuilder: (context) => [
        PopupMenuItem<void>(
          enabled: false,
          child: Text('Notifications',
              style: Theme.of(context).textTheme.titleSmall),
        ),
        if (notes.isEmpty)
          const PopupMenuItem<void>(
            enabled: false,
            child: Text('You’re all caught up.'),
          )
        else
          for (final n in notes)
            PopupMenuItem<void>(
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(n.icon, color: n.color, size: 20),
                title: Text(n.title,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                subtitle: Text(n.message,
                    style: const TextStyle(fontSize: 12)),
              ),
            ),
      ],
      icon: Badge(
        isLabelVisible: notes.isNotEmpty,
        label: Text('${notes.length}'),
        child: const Icon(Icons.notifications_outlined),
      ),
    );
  }

  List<_Note> _notifications(AppState appState, DataController data) {
    final notes = <_Note>[];
    if (!appState.isFirebaseMode) {
      notes.add(const _Note(
        icon: Icons.cloud_off_outlined,
        color: AppColors.warning,
        title: 'Demo mode active',
        message:
            'Data is stored locally. Configure Firebase in Settings to go live.',
      ));
    }
    // Campaigns ending within 7 days.
    final now = DateTime.now();
    for (final c in data.campaigns) {
      final end = c.endDate;
      if (end != null &&
          end.isAfter(now) &&
          end.difference(now).inDays <= 7) {
        notes.add(_Note(
          icon: Icons.campaign_outlined,
          color: AppColors.info,
          title: 'Campaign ending soon',
          message: '${c.name} ends ${end.day}/${end.month}.',
        ));
      }
    }
    return notes;
  }
}

class _Note {
  const _Note({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String message;
}

class _ProfileMenu extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final user = appState.currentUser;
    if (user == null) return const SizedBox.shrink();

    return PopupMenuButton<String>(
      tooltip: 'Account',
      offset: const Offset(0, 48),
      onSelected: (value) {
        switch (value) {
          case 'settings':
            context.go(Routes.settings);
          case 'signout':
            appState.signOut();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(user.name,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              Text(user.email,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'settings',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.settings_outlined, size: 20),
            title: Text('Settings'),
          ),
        ),
        const PopupMenuItem<String>(
          value: 'signout',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.logout, size: 20),
            title: Text('Sign out'),
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        child: CircleAvatar(
          radius: 17,
          backgroundColor: AppColors.primary,
          child: Text(
            _initials(user.name),
            style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}
