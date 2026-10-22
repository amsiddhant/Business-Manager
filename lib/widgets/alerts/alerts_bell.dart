import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/theme_x.dart';
import '../../services/alert_service.dart';
import '../../state/alert_controller.dart';
import 'alerts_panel.dart';

/// The top bar's bell: opens the alerts panel. The badge counts active
/// alerts that aren't just informational, in red when one needs action.
class AlertsBell extends StatelessWidget {
  const AlertsBell({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final controller = context.watch<AlertController>();
    final active = controller.active(alertsOf(context));
    final count = controller.badgeCount(active);
    final high = active.any((a) => a.severity == AlertSeverity.high);
    final badge = high ? t.error : t.warning;

    return IconButton(
      tooltip: count == 0 ? 'Alerts' : 'Alerts ($count)',
      onPressed: () => AlertsPanel.open(context),
      icon: Badge(
        isLabelVisible: count > 0,
        backgroundColor: badge,
        textColor: t.onColor(badge),
        label: Text(count > 99 ? '99+' : '$count'),
        child: Icon(count > 0
            ? Icons.notifications_active_outlined
            : Icons.notifications_none_outlined),
      ),
    );
  }
}
