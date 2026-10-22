import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_x.dart';
import '../../../state/smart_insights_controller.dart';
import '../../../widgets/common/confirm_dialog.dart';
import '../settings_widgets.dart';
import 'smart_section.dart';

/// Your own switch for the on-device AI, and a way to clear what it kept.
/// Only affects this device.
class AiSection extends StatelessWidget {
  const AiSection({super.key});

  @override
  Widget build(BuildContext context) {
    final smart = smartOf(context);
    final t = context.tokens;
    return SettingsPanel(
      title: 'On-device AI',
      subtitle: 'Better forecasts and suggestions, learned on this device',
      children: [
        if (smart == null)
          const SettingsNote('On-device AI isn’t available here.')
        else
          SettingsCard(
            children: [
              SettingSwitch(
                title: 'Use on-device AI',
                subtitle: 'Uses this device to improve forecasts and '
                    'suggestions. Nothing leaves your device.',
                value: smart.userEnabled,
                onChanged: (v) => smart.setUserEnabled(v),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(children: [
                Icon(smartStatusIcon(smart.status),
                    size: 18, color: smartStatusColor(t, smart.status)),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(smart.status.label,
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: smartStatusColor(t, smart.status))),
                ),
              ]),
              if (smart.problem != null) ...[
                const SizedBox(height: AppSpacing.sm),
                SettingsNote(smart.problem!, tone: SettingsNoteTone.warning),
              ],
              const SizedBox(height: AppSpacing.lg),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => _clear(context, smart),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Clear on-device AI data'),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Future<void> _clear(
      BuildContext context, SmartInsightsController smart) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Clear on-device AI data?',
      message: 'This deletes what the on-device AI learned on this device. '
          'It will learn again from your records.',
      confirmLabel: 'Clear',
    );
    if (!ok) return;
    await smart.clearDeviceData();
    if (context.mounted) showSuccessSnack(context, 'On-device AI data cleared');
  }
}
