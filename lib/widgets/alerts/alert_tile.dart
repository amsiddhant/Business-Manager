import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/routing/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_x.dart';
import '../../core/utils/date_utils.dart';
import '../../models/app_user.dart';
import '../../services/alert_service.dart';
import '../../state/alert_controller.dart';
import '../../state/app_state.dart';

/// One alert with its actions: open what it's about, snooze, dismiss — or,
/// once snoozed or dismissed, restore.
class AlertTile extends StatelessWidget {
  const AlertTile({
    super.key,
    required this.alert,
    this.onBeforeOpen,
    this.onDismissed,
    this.now,
  });

  final AppAlert alert;

  /// Runs before navigating (e.g. closes the alerts panel).
  final VoidCallback? onBeforeOpen;

  /// After a dismiss — e.g. to offer an undo.
  final ValueChanged<AppAlert>? onDismissed;
  final DateTime? now;

  static Color colorOf(AppTokens t, AlertSeverity s) => switch (s) {
    AlertSeverity.high => t.error,
    AlertSeverity.medium => t.warning,
    AlertSeverity.info => t.info,
  };

  static IconData iconOf(AlertType type) => switch (type) {
    AlertType.contractExpiring => Icons.event_outlined,
    AlertType.contractOverdue => Icons.event_busy_outlined,
    AlertType.campaignEnding => Icons.campaign_outlined,
    AlertType.lowMargin => Icons.trending_down,
    AlertType.unusualSpend => Icons.bolt_outlined,
    AlertType.dataWarning => Icons.cloud_off_outlined,
    AlertType.demoMode => Icons.science_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final alerts = context.watch<AlertController>();
    final user = context.select<AppState, AppUser?>((s) => s.currentUser);
    final state = alerts.stateOf(alert, now: now);
    final color = colorOf(t, alert.severity);
    final route = alert.route;
    final canOpen = route != null && Routes.canOpen(user, route);
    final until = alerts.snoozedUntil(alert);

    final meta = [
      alert.type.label,
      if (alert.due != null) AppDate.short(alert.due!),
      if (state == AlertState.snoozed && until != null)
        'Snoozed until ${AppDate.short(until)}',
      if (state == AlertState.dismissed) 'Dismissed',
    ].join(' · ');

    void open() {
      final router = GoRouter.of(context);
      onBeforeOpen?.call();
      router.go(route!);
    }

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: canOpen ? open : null,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(iconOf(alert.type), size: 18, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(alert.title,
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                            color: state == AlertState.active
                                ? t.textPrimary
                                : t.textSecondary)),
                    const SizedBox(height: 3),
                    Text(alert.message,
                        style: TextStyle(
                            fontSize: 12.5,
                            height: 1.4,
                            color: t.textSecondary)),
                    const SizedBox(height: 6),
                    Text(meta,
                        style: TextStyle(fontSize: 11.5, color: t.textTertiary)),
                  ],
                ),
              ),
              if (state == AlertState.active) ...[
                PopupMenuButton<Duration>(
                  tooltip: 'Snooze',
                  icon: Icon(Icons.snooze, size: 18, color: t.textTertiary),
                  onSelected: (d) => alerts.snooze(alert.key, d),
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                        value: Duration(days: 1), child: Text('Snooze 1 day')),
                    PopupMenuItem(
                        value: Duration(days: 7),
                        child: Text('Snooze 7 days')),
                  ],
                ),
                IconButton(
                  tooltip: 'Dismiss',
                  icon: Icon(Icons.close, size: 18, color: t.textTertiary),
                  onPressed: () {
                    alerts.dismiss([alert.key]);
                    onDismissed?.call(alert);
                  },
                ),
              ] else
                TextButton(
                  onPressed: () => alerts.restore(alert.key),
                  child: const Text('Restore'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
