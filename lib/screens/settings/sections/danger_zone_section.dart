import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/theme_x.dart';
import '../../../state/app_state.dart';
import '../../../state/data_controller.dart';
import '../../../widgets/common/confirm_dialog.dart';
import '../settings_widgets.dart';

/// Irreversible actions. Owner only.
class DangerZoneSection extends StatelessWidget {
  const DangerZoneSection({super.key});

  Future<void> _reset(BuildContext context, AppState appState) async {
    final data = context.read<DataController>();
    final ok = await showConfirmDialog(
      context,
      title: 'Reset demo data?',
      message: 'This restores the original demo dataset and signs you out. '
          'Any changes made in demo mode will be lost.',
      confirmLabel: 'Reset',
      destructive: true,
    );
    if (ok != true) return;
    try {
      await appState.resetDemoData();
      data.clear();
      if (context.mounted) showSuccessSnack(context, 'Demo data reset');
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final appState = context.watch<AppState>();
    // Demo reset only makes sense while running on the local demo backend.
    final demo = !appState.isFirebaseMode;
    return SettingsPanel(
      title: 'Danger zone',
      subtitle: 'Actions that can’t be undone',
      children: [
        SettingsCard(
          title: 'Demo data',
          children: [
            Text(
              demo
                  ? 'Reset all demo data back to the original seed. This '
                      'clears any changes you have made in demo mode.'
                  : 'Resetting is only available in demo mode. Your data lives '
                      'in Firebase, so nothing here can reset it.',
              style: TextStyle(fontSize: 13, color: t.textSecondary),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: t.error),
                onPressed: demo ? () => _reset(context, appState) : null,
                icon: const Icon(Icons.restart_alt, size: 18),
                label: const Text('Reset demo data'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
