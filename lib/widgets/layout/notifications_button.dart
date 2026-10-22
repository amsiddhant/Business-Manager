import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_x.dart';
import '../../state/app_state.dart';
import '../../state/data_controller.dart';

/// The bell in the top bar: demo mode, partial-load warnings and campaigns
/// ending within a week.
class NotificationsButton extends StatelessWidget {
  const NotificationsButton({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final data = context.watch<DataController>();
    final t = context.tokens;
    final notes = notificationsFor(t, appState, data);

    return PopupMenuButton<void>(
      tooltip: 'Notifications',
      offset: const Offset(0, 48),
      constraints: const BoxConstraints(minWidth: 320, maxWidth: 380),
      itemBuilder: (context) => [
        PopupMenuItem<void>(
          enabled: false,
          child: Row(
            children: [
              Text('Notifications',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(color: t.textPrimary)),
              const Spacer(),
              if (notes.isNotEmpty)
                Text('${notes.length}',
                    style: TextStyle(fontSize: 12, color: t.textTertiary)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        if (notes.isEmpty)
          PopupMenuItem<void>(
            enabled: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline, color: t.success, size: 20),
                  const SizedBox(width: AppSpacing.sm),
                  Text('You’re all caught up.',
                      style: TextStyle(color: t.textSecondary)),
                ],
              ),
            ),
          )
        else
          for (final n in notes)
            PopupMenuItem<void>(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: n.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(n.icon, color: n.color, size: 18),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(n.title,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: t.textPrimary)),
                        const SizedBox(height: 2),
                        Text(n.message,
                            style: TextStyle(
                                fontSize: 12, color: t.textSecondary)),
                      ],
                    ),
                  ),
                ],
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
}

/// What the bell shows, newest concerns first.
List<AppNotification> notificationsFor(
    AppTokens t, AppState appState, DataController data) {
  final notes = <AppNotification>[];
  if (!appState.isFirebaseMode) {
    notes.add(AppNotification(
      icon: Icons.cloud_off_outlined,
      color: t.warning,
      title: 'Demo mode active',
      message:
          'Data is stored locally. Configure Firebase in Settings to go live.',
    ));
  }
  // Partial-load failures: one collection was unreadable while the rest of
  // the app loaded fine. Surfaced here (not as a full-screen error) so the
  // user keeps access to everything else.
  for (final w in data.warnings) {
    notes.add(AppNotification(
      icon: Icons.error_outline,
      color: t.warning,
      title: 'Some data could not be loaded',
      message: w,
    ));
  }
  // Campaigns ending within 7 days.
  final now = DateTime.now();
  for (final c in data.campaigns) {
    final end = c.endDate;
    if (end != null && end.isAfter(now) && end.difference(now).inDays <= 7) {
      notes.add(AppNotification(
        icon: Icons.campaign_outlined,
        color: t.info,
        title: 'Campaign ending soon',
        message: '${c.name} ends ${end.day}/${end.month}.',
      ));
    }
  }
  return notes;
}

class AppNotification {
  const AppNotification({
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
