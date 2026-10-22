import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_x.dart';
import '../../services/alert_service.dart';
import '../../state/alert_controller.dart';
import '../../widgets/alerts/alert_tile.dart';
import '../../widgets/alerts/alerts_panel.dart';
import '../../widgets/common/app_card.dart';
import '../../widgets/common/confirm_dialog.dart';
import '../../widgets/common/page_header.dart';
import '../../widgets/common/state_views.dart';
import '../../widgets/layout/app_page.dart';

/// Every alert, with what you've snoozed and dismissed: filter by state,
/// severity and type, and act on them.
class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  AlertState _state = AlertState.active;
  final Set<AlertSeverity> _severities = {};
  final Set<AlertType> _types = {};

  void _undoable(AppAlert alert) {
    final controller = context.read<AlertController>();
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Dismissed "${alert.title}"'),
        action: SnackBarAction(
            label: 'Undo', onPressed: () => controller.restore(alert.key)),
      ));
  }

  Future<void> _dismissAll(List<AppAlert> shown) async {
    final controller = context.read<AlertController>();
    final ok = await showConfirmDialog(
      context,
      title: 'Dismiss ${shown.length} alerts?',
      message: 'They move to Dismissed, where you can restore them.',
      confirmLabel: 'Dismiss all',
      destructive: false,
    );
    if (ok) await controller.dismiss([for (final a in shown) a.key]);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final controller = context.watch<AlertController>();
    final all = alertsOf(context);
    int countIn(AlertState s) =>
        all.where((a) => controller.stateOf(a) == s).length;
    final inState = [
      for (final a in all)
        if (controller.stateOf(a) == _state) a,
    ];
    final shown = [
      for (final a in inState)
        if ((_severities.isEmpty || _severities.contains(a.severity)) &&
            (_types.isEmpty || _types.contains(a.type)))
          a,
    ];
    final types = {for (final a in all) a.type}.toList()
      ..sort((a, b) => a.index.compareTo(b.index));

    return AppPage(
      children: [
        PageHeader(
          title: 'Alerts',
          subtitle: 'Worked out on this device from your data — snoozes and '
              'dismissals are kept for you only.',
          actions: [
            if (_state == AlertState.active && shown.length > 1)
              OutlinedButton.icon(
                onPressed: () => _dismissAll(shown),
                icon: const Icon(Icons.done_all, size: 18),
                label: const Text('Dismiss all shown'),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SegmentedButton<AlertState>(
              showSelectedIcon: false,
              segments: [
                for (final s in AlertState.values)
                  ButtonSegment(
                    value: s,
                    label: Text('${switch (s) {
                      AlertState.active => 'Active',
                      AlertState.snoozed => 'Snoozed',
                      AlertState.dismissed => 'Dismissed',
                    }} (${countIn(s)})'),
                  ),
              ],
              selected: {_state},
              onSelectionChanged: (s) => setState(() => _state = s.first),
            ),
            for (final s in AlertSeverity.values)
              FilterChip(
                label: Text(s.label),
                avatar: Icon(Icons.circle,
                    size: 10, color: AlertTile.colorOf(t, s)),
                selected: _severities.contains(s),
                onSelected: (on) => setState(
                    () => on ? _severities.add(s) : _severities.remove(s)),
              ),
          ],
        ),
        if (types.length > 1) ...[
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final type in types)
                FilterChip(
                  label: Text(type.label),
                  avatar: Icon(AlertTile.iconOf(type), size: 16),
                  selected: _types.contains(type),
                  onSelected: (on) => setState(
                      () => on ? _types.add(type) : _types.remove(type)),
                ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        if (shown.isEmpty)
          AppCard(
            child: EmptyView(
              icon: _state == AlertState.active
                  ? Icons.check_circle_outline
                  : Icons.inbox_outlined,
              title: switch (_state) {
                AlertState.active => inState.isEmpty
                    ? 'All caught up'
                    : 'No alerts match these filters',
                AlertState.snoozed => 'Nothing snoozed',
                AlertState.dismissed => 'Nothing dismissed',
              },
              message: _state == AlertState.active && inState.isEmpty
                  ? "We'll flag expiring contracts, ending campaigns, thin "
                      'margins and unusual spend here.'
                  : null,
            ),
          )
        else
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Column(
              children: [
                for (var i = 0; i < shown.length; i++) ...[
                  if (i > 0)
                    Divider(height: 1, indent: 58, color: t.border),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                    child: AlertTile(
                      key: ValueKey(shown[i].key),
                      alert: shown[i],
                      onDismissed: _undoable,
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
