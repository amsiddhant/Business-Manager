import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/theme_x.dart';
import '../../../core/utils/date_utils.dart';
import '../../../models/audit_log.dart';
import '../../../state/app_state.dart';
import '../../../core/app_exception.dart';
import '../settings_widgets.dart';

/// The most recent changes made in the app.
class AuditSection extends StatefulWidget {
  const AuditSection({super.key});

  @override
  State<AuditSection> createState() => _AuditSectionState();
}

class _AuditSectionState extends State<AuditSection> {
  List<AuditLog>? _logs;
  Object? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    final repo = context.read<AppState>().repository;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final logs = await repo.fetchAuditLogs(limit: 100);
      if (mounted) setState(() => _logs = logs);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final logs = _logs;
    return SettingsPanel(
      title: 'Audit log',
      subtitle: 'The last 100 changes, newest first',
      children: [
        SettingsCard(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _loading ? null : _load,
                icon: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh, size: 18),
                label: const Text('Refresh'),
              ),
            ),
            const SizedBox(height: 12),
            if (_error != null)
              SettingsNote(ErrorMapper.friendly(_error!), tone: SettingsNoteTone.error)
            else if (logs == null)
              Text('Loading…',
                  style: TextStyle(fontSize: 13, color: t.textSecondary))
            else if (logs.isEmpty)
              Text('Nothing has been recorded yet.',
                  style: TextStyle(fontSize: 13, color: t.textSecondary))
            else
              for (final log in logs)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                '${log.action.label} · ${log.entityType}'
                                '${log.summary.isEmpty ? '' : ' · ${log.summary}'}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w500, fontSize: 13.5)),
                            Text(
                                '${log.userName}'
                                '${log.timestamp == null ? '' : ' · ${AppDate.format(log.timestamp)}'}',
                                style: TextStyle(
                                    fontSize: 12, color: t.textSecondary)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ],
    );
  }
}
