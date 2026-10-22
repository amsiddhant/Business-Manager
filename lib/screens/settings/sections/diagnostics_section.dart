import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:provider/provider.dart';

import '../../../core/app_info.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_x.dart';
import '../../../data/backend_capabilities.dart';
import '../../../state/app_state.dart';
import '../../../state/data_controller.dart';
import '../../../services/smart/smart_config.dart';
import '../../../state/settings_controller.dart';
import '../../../state/smart_insights_controller.dart';
import '../../../widgets/common/confirm_dialog.dart';
import '../../../widgets/layout/sync_status.dart';
import '../settings_widgets.dart';

/// What this session has cost and anything that went wrong, for the owner
/// (and for support). Reads nothing: it reports what's already in memory.
class DiagnosticsSection extends StatelessWidget {
  const DiagnosticsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final data = context.watch<DataController>();
    final settings = context.watch<SettingsController>();
    final smart = smartOf(context);
    final repo = app.repository;
    final meter = repo.backend is UsageMeter ? repo.backend as UsageMeter : null;
    final problems = _problems(data, settings, repo.diagnostics);
    final counts = <(String, int)>[
      ('Businesses', data.businesses.length),
      ('Products', data.products.length),
      ('Campaigns', data.campaigns.length),
      ('Orders', data.orders.length),
      ('Expenses', data.expenses.length),
      ('Dealers', data.dealers.length),
      ('Customers', data.customers.length),
      ('Goals', data.goals.length),
    ];
    final session = <(String, String)>[
      ('Version', '$kAppVersion (build $kAppBuild)'),
      ('Data source', app.isFirebaseMode ? 'Firebase' : 'Demo (this browser)'),
      ('Last sync',
          syncedAgoLabel(data.lastSyncedAt, DateTime.now()) ?? 'Not yet'),
      ('Organisation settings',
          settings.hasRemote ? 'Saved' : 'Defaults (never saved)'),
      if (meter != null) ...[
        ('Reads this session', '${meter.readCount}'),
        ('Writes this session', '${meter.writeCount}'),
      ],
      if (smart != null) ...[
        ('On-device AI', smart.status.label),
        if (smart.selfTest case final s?) ...[
          ('TensorFlow.js', '${s.version} (${s.backend})'),
          ('AI self-test',
              '${s.passed ? 'Passed' : 'Failed'} in ${s.ms} ms'),
          ('AI tensors before / after',
              '${s.tensorsBefore} / ${s.tensorsAfter}'),
        ],
        ('AI failures in a row',
            '${smart.failures} of ${SmartConfig.maxFailures}'),
      ],
    ];

    return SettingsPanel(
      title: 'Diagnostics',
      subtitle: 'How this session is doing. Nothing here is read from the '
          'server.',
      children: [
        SettingsCard(
          title: 'This session',
          trailing: TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(
                  text: _report(session, counts, problems)));
              if (context.mounted) {
                showSuccessSnack(context, 'Diagnostics copied');
              }
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Copy'),
          ),
          children: [
            for (final (label, value) in session) _Row(label, value),
            if (meter != null) ...[
              const SizedBox(height: AppSpacing.md),
              const SettingsNote(
                  'Firestore’s free plan allows 50,000 reads and 20,000 '
                  'writes a day across everyone. Saves cost a write each; '
                  'opening the app and syncing cost a read per record.'),
            ],
          ],
        ),
        SettingsCard(
          title: 'Records loaded',
          subtitle: 'What you can see, after access rules.',
          children: [
            for (final (label, n) in counts) _Row(label, '$n'),
          ],
        ),
        SettingsCard(
          title: 'Problems',
          children: [
            if (problems.isEmpty)
              const SettingsNote('Nothing to report.',
                  tone: SettingsNoteTone.success)
            else
              for (final p in problems) ...[
                SettingsNote(p, tone: SettingsNoteTone.warning),
                if (p != problems.last) const SizedBox(height: AppSpacing.sm),
              ],
          ],
        ),
      ],
    );
  }

  static List<String> _problems(
      DataController data, SettingsController settings, List<String> writes) {
    return [
      if (data.error != null) data.error!,
      ...data.warnings,
      if (settings.rulesMissing)
        'Organisation settings couldn’t be read: deploy the latest Firestore '
            'rules (firebase deploy --only firestore:rules).',
      if (settings.error != null) settings.error!,
      if (data.goalsUnavailable)
        'Goals couldn’t be read: deploy the latest Firestore rules.',
      ...writes.reversed,
    ];
  }

  static String _report(List<(String, String)> session,
      List<(String, int)> counts, List<String> problems) {
    return [
      'Business Manager diagnostics',
      for (final (label, value) in session) '$label: $value',
      '',
      'Records loaded',
      for (final (label, n) in counts) '$label: $n',
      '',
      'Problems',
      if (problems.isEmpty) 'None',
      for (final p in problems) '- $p',
    ].join('\n');
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(fontSize: 13.5, color: t.textSecondary)),
          ),
          Text(value,
              style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: t.textPrimary)),
        ],
      ),
    );
  }
}
