import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/routing/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_x.dart';
import '../../services/alert_service.dart';
import '../../state/alert_controller.dart';
import '../../state/app_state.dart';
import '../../state/org_settings.dart';
import '../../state/data_controller.dart';
import '../common/responsive.dart';
import 'alert_tile.dart';

/// The user's alerts for the loaded data (0 reads: computed on the device).
List<AppAlert> alertsOf(BuildContext context, {bool listen = true}) {
  final data = listen
      ? context.watch<DataController>()
      : context.read<DataController>();
  final demo = listen
      ? context.select<AppState, bool>((s) => !s.isFirebaseMode)
      : !context.read<AppState>().isFirebaseMode;
  final controller = listen
      ? context.watch<AlertController>()
      : context.read<AlertController>();
  return controller.alertsFor(data, demoMode: demo);
}

/// The active alerts, grouped by severity: a panel from the right on wider
/// screens, a sheet from the bottom on phones.
class AlertsPanel extends StatelessWidget {
  const AlertsPanel({super.key, this.sheet = false});

  /// Laid out as a bottom sheet (drag handle, no side border).
  final bool sheet;

  static const width = 420.0;

  static Future<void> open(BuildContext context) {
    if (Responsive.isMobile(context)) {
      return showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => const FractionallySizedBox(
            heightFactor: 0.88, child: AlertsPanel(sheet: true)),
      );
    }
    final motion = context.motion;
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close alerts',
      barrierColor: context.tokens.scrim,
      transitionDuration: motion.slow,
      pageBuilder: (_, _, _) => const Align(
        alignment: Alignment.centerRight,
        child: AlertsPanel(),
      ),
      transitionBuilder: (context, animation, _, child) {
        final curved =
            CurvedAnimation(parent: animation, curve: AppMotion.emphasized);
        if (!motion.allowsMovement) {
          return FadeTransition(opacity: curved, child: child);
        }
        return SlideTransition(
          position: Tween(begin: const Offset(0.25, 0), end: Offset.zero)
              .animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final controller = context.watch<AlertController>();
    final active = controller.active(alertsOf(context));
    final urgent = active.where((a) => a.severity != AlertSeverity.info).length;
    void close() => Navigator.of(context).maybePop();

    final groups = [
      for (final s in AlertSeverity.values)
        if (active.where((a) => a.severity == s).toList()
            case final items when items.isNotEmpty)
          (severity: s, items: items),
    ];

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
              AppSpacing.xl, sheet ? 0 : AppSpacing.xl, AppSpacing.md, 0),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text('Alerts',
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.3,
                              color: t.textPrimary)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                        urgent == 0
                            ? 'Nothing needs your attention'
                            : '$urgent need${urgent == 1 ? 's' : ''} your '
                                'attention',
                        style:
                            TextStyle(fontSize: 12.5, color: t.textSecondary)),
                  ],
                ),
              ),
              if (!sheet)
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close),
                  onPressed: close,
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Divider(height: 1, color: t.border),
        Expanded(
          child: groups.isEmpty
              ? _CaughtUp(color: t.success)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.sm, AppSpacing.sm, AppSpacing.sm,
                      AppSpacing.lg),
                  children: [
                    for (final g in groups) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: AlertTile.colorOf(t, g.severity),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                                '${g.severity.label.toUpperCase()} · '
                                '${g.items.length}',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.8,
                                    color: t.textTertiary)),
                          ],
                        ),
                      ),
                      for (final a in g.items)
                        AlertTile(key: ValueKey(a.key), alert: a,
                            onBeforeOpen: close),
                    ],
                  ],
                ),
        ),
        Divider(height: 1, color: t.border),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Expanded(
                child: Text('Snoozed and dismissed alerts are in the alerts '
                    'center.',
                    style: TextStyle(fontSize: 12, color: t.textTertiary)),
              ),
              if (context.orgSettings((s) => s.modules.isEnabled(Routes.alerts)))
                TextButton.icon(
                  iconAlignment: IconAlignment.end,
                  icon: const Icon(Icons.arrow_forward, size: 16),
                  label: const Text('Alerts center'),
                  onPressed: () {
                    final router = GoRouter.of(context);
                    close();
                    router.go(Routes.alerts);
                  },
                ),
            ],
          ),
        ),
      ],
    );

    if (sheet) return body;
    final screen = MediaQuery.sizeOf(context);
    return Material(
      color: t.card,
      elevation: 0,
      child: Container(
        width: screen.width < width ? screen.width : width,
        height: screen.height,
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: t.border)),
          boxShadow: t.raisedShadow,
        ),
        child: SafeArea(left: false, child: body),
      ),
    );
  }
}

class _CaughtUp extends StatelessWidget {
  const _CaughtUp({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.check_rounded, size: 30, color: color),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('All caught up',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: t.textPrimary)),
            const SizedBox(height: 4),
            Text("We'll flag expiring contracts, ending campaigns, thin "
                'margins and unusual spend here.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12.5, height: 1.4, color: t.textSecondary)),
          ],
        ),
      ),
    );
  }
}
