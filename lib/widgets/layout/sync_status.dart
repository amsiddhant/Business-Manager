import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../state/data_controller.dart';
import '../common/responsive.dart';

/// "Synced 5 min ago" for the header, or null before the first sync.
String? syncedAgoLabel(DateTime? syncedAt, DateTime now) {
  if (syncedAt == null) return null;
  final age = now.difference(syncedAt);
  if (age.inMinutes < 1) return 'Synced just now';
  if (age.inHours < 1) return 'Synced ${age.inMinutes} min ago';
  if (age.inDays < 1) {
    return 'Synced ${age.inHours} ${age.inHours == 1 ? 'hr' : 'hrs'} ago';
  }
  return 'Synced ${age.inDays} ${age.inDays == 1 ? 'day' : 'days'} ago';
}

/// Shows when the data was last read from the server, with a "Sync now"
/// button. Saves update the screen by themselves; syncing picks up changes
/// other people made.
class SyncStatus extends StatefulWidget {
  const SyncStatus({super.key});

  @override
  State<SyncStatus> createState() => _SyncStatusState();
}

class _SyncStatusState extends State<SyncStatus> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Keeps "N min ago" current; one cheap rebuild of this widget a minute.
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = context.read<DataController>();
    final syncedAt = context.select<DataController, DateTime?>(
        (d) => d.lastSyncedAt);
    final cached =
        context.select<DataController, bool>((d) => d.showingCachedData);
    final label = cached
        ? 'Showing saved copy · syncing'
        : syncedAgoLabel(syncedAt, DateTime.now());
    final showLabel = Responsive.isDesktop(context) && label != null;

    return ValueListenableBuilder<bool>(
      valueListenable: data.syncing,
      builder: (context, syncing, _) {
        final text = syncing && !cached ? 'Syncing…' : label;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showLabel && text != null)
              Text(
                text,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.textSecondary),
              ),
            const SizedBox(width: AppSpacing.xs),
            IconButton(
              tooltip: syncing ? 'Syncing…' : 'Sync now',
              onPressed: syncing ? null : data.sync,
              icon: syncing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync),
            ),
          ],
        );
      },
    );
  }
}
