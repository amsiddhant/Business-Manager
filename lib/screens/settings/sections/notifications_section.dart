import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/theme_x.dart';
import '../../../services/alert_service.dart';
import '../../../state/alert_controller.dart';
import '../../../state/org_settings.dart';
import '../settings_widgets.dart';

/// Which kinds of alert you want to see. Hiding one only affects you.
class NotificationsSection extends StatelessWidget {
  const NotificationsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AlertController>();
    final orgOff = context.orgSettings((s) => s.alerts.disabledTypes);
    final hidden = controller.hiddenTypes;
    final t = context.tokens;
    return SettingsPanel(
      title: 'Notifications',
      subtitle: 'Choose the alerts you see in the bell and the alerts page',
      children: [
        SettingsCard(
          title: 'Alert types',
          subtitle: 'Turn a type off to hide it for you only.',
          children: [
            for (final type in AlertType.values)
              Builder(builder: (context) {
                final off = orgOff.contains(type.name);
                return SettingSwitch(
                  title: type.label,
                  subtitle: off ? 'Turned off by your organisation' : null,
                  value: !off && !hidden.contains(type.name),
                  onChanged: off
                      ? null
                      : (on) => controller.setHiddenTypes({
                            for (final h in hidden)
                              if (h != type.name) h,
                            if (!on) type.name,
                          }),
                );
              }),
            Text('Dismissed and snoozed alerts are managed on the Alerts page.',
                style: TextStyle(fontSize: 12, color: t.textTertiary)),
          ],
        ),
      ],
    );
  }
}
