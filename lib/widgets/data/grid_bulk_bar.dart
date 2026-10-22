import 'package:flutter/material.dart';

import '../../core/app_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_x.dart';
import '../common/confirm_dialog.dart';
import 'grid_column.dart';

/// Replaces the toolbar while rows are ticked: how many, "Select all", and
/// the actions that work on them.
class GridBulkBar<T> extends StatelessWidget {
  const GridBulkBar({
    super.key,
    required this.selected,
    required this.matching,
    required this.onSelectAll,
    required this.onClear,
    this.onExport,
    this.actions = const [],
    this.onAction,
  });

  /// The ticked rows, in the order shown.
  final List<T> selected;

  /// How many rows match the search and filters.
  final int matching;
  final VoidCallback onSelectAll;
  final VoidCallback onClear;
  final VoidCallback? onExport;
  final List<GridBulkAction<T>> actions;
  final void Function(GridBulkAction<T> action)? onAction;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final n = selected.length;
    final buttons = <Widget>[
      if (onExport != null)
        _BarButton(
            icon: Icons.ios_share, label: 'Export', onPressed: onExport!),
      for (final a in actions) _actionButton(context, a),
    ];
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: t.primarySurface,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        border: Border.all(color: t.primary.withValues(alpha: 0.25)),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        children: [
          IconButton(
            tooltip: 'Clear selection',
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.close, size: 20, color: t.primary),
            onPressed: onClear,
          ),
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: Text('$n selected',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: t.primary,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ),
          if (n < matching)
            TextButton(
              onPressed: onSelectAll,
              child: Text('Select all $matching'),
            ),
          ...buttons,
        ],
      ),
    );
  }

  Widget _actionButton(BuildContext context, GridBulkAction<T> a) {
    if (a.children.isEmpty) {
      return _BarButton(
        icon: a.icon,
        label: a.label,
        destructive: a.destructive,
        onPressed: () => onAction?.call(a),
      );
    }
    return MenuAnchor(
      menuChildren: [
        for (final c in a.children)
          MenuItemButton(
            leadingIcon: Icon(c.icon, size: 18),
            onPressed: () => onAction?.call(c),
            child: Text(c.label),
          ),
      ],
      builder: (context, menu, _) => _BarButton(
        icon: a.icon,
        label: a.label,
        trailing: Icons.arrow_drop_down,
        onPressed: () => menu.isOpen ? menu.close() : menu.open(),
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.destructive = false,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool destructive;
  final IconData? trailing;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = destructive ? t.error : t.textPrimary;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 6),
          Text(label),
          if (trailing != null) Icon(trailing, size: 18),
        ],
      ),
    );
  }
}

/// The free plan allows 20,000 writes a day; past this many rows, ask first.
const kBulkConfirmAbove = 200;

/// What [runGridBulk] did.
class BulkOutcome<T> {
  const BulkOutcome({required this.done, required this.failed});

  final List<T> done;
  final List<(T, Object)> failed;
}

/// Runs [task] on each of [rows], 20 at a time, behind a progress dialog,
/// then reports what failed. Asks first when there are more than
/// [kBulkConfirmAbove] rows, because each one costs writes.
///
/// [verb] reads like "Deleting"; [noun] is the plural ("orders");
/// [describe] names a row in the failure report.
Future<BulkOutcome<T>> runGridBulk<T>(
  BuildContext context, {
  required List<T> rows,
  required Future<void> Function(T row) task,
  required String verb,
  required String noun,
  String Function(T row)? describe,
}) async {
  if (rows.isEmpty) return BulkOutcome<T>(done: const [], failed: const []);
  if (rows.length > kBulkConfirmAbove) {
    final ok = await showConfirmDialog(
      context,
      title: '$verb ${rows.length} $noun?',
      message: 'This changes ${rows.length} records at once. Each one counts '
          'towards the free plan\'s daily write limit, so large batches are '
          'best done a few at a time.',
      confirmLabel: 'Continue',
      destructive: false,
    );
    if (!ok || !context.mounted) {
      return BulkOutcome<T>(done: const [], failed: const []);
    }
  }

  final progress = ValueNotifier<int>(0);
  final done = <T>[];
  final failed = <(T, Object)>[];
  final navigator = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text('$verb $noun…'),
        content: SizedBox(
          width: 320,
          child: ValueListenableBuilder<int>(
            valueListenable: progress,
            builder: (context, n, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(value: n / rows.length),
                const SizedBox(height: AppSpacing.md),
                Text('$n of ${rows.length}',
                    style: TextStyle(color: context.tokens.textSecondary)),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  const chunk = 20;
  for (var i = 0; i < rows.length; i += chunk) {
    final part = rows.sublist(i, (i + chunk).clamp(0, rows.length));
    await Future.wait([
      for (final r in part)
        task(r).then((_) => done.add(r)).catchError((Object e) {
          failed.add((r, e));
        }),
    ]);
    progress.value = done.length + failed.length;
  }
  navigator.pop();
  progress.dispose();

  if (!context.mounted) return BulkOutcome<T>(done: done, failed: failed);
  if (failed.isEmpty) {
    showSuccessSnack(context, '${verb.replaceFirst(RegExp(r'ing$'), 'ed')} '
        '${done.length} $noun');
  } else {
    await showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(done.isEmpty
            ? 'Nothing was changed'
            : '${done.length} done, ${failed.length} failed'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (row, error) in failed.take(10))
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Text(
                        '• ${describe?.call(row) ?? '$row'}: '
                        '${ErrorMapper.friendly(error)}',
                        style: const TextStyle(fontSize: 13)),
                  ),
                if (failed.length > 10)
                  Text('…and ${failed.length - 10} more.',
                      style: TextStyle(
                          fontSize: 13,
                          color: dialog.tokens.textSecondary)),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
  return BulkOutcome<T>(done: done, failed: failed);
}
