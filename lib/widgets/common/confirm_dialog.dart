import 'package:flutter/material.dart';

import '../../core/app_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_x.dart';

/// Shows a confirmation dialog for destructive actions and returns true if the
/// user confirms.
Future<bool> showConfirmDialog(
  BuildContext context, {
  String title = 'Are you sure?',
  String message = 'This action cannot be easily undone.',
  String confirmLabel = 'Delete',
  String cancelLabel = 'Cancel',
  bool destructive = true,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) {
      final t = context.tokens;
      final tone = destructive ? t.error : t.primary;
      return AlertDialog(
        icon: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: destructive ? t.errorSurface : t.primaryLight,
            shape: BoxShape.circle,
          ),
          child: Icon(
            destructive ? Icons.delete_outline : Icons.help_outline,
            color: tone,
          ),
        ),
        title: Text(title, textAlign: TextAlign.center),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: t.textSecondary, height: 1.45),
          ),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
        actions: [
          OutlinedButton(
            // Destructive: the safe choice gets Enter.
            autofocus: destructive,
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(cancelLabel),
          ),
          FilledButton(
            autofocus: !destructive,
            onPressed: () => Navigator.of(context).pop(true),
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: t.error,
                    foregroundColor: t.onColor(t.error),
                  )
                : null,
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return result ?? false;
}

/// Shows a success snackbar.
void showSuccessSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Row(children: [
        Icon(Icons.check_circle, color: context.tokens.success, size: 18),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(message)),
      ]),
    ));
}

/// Shows an error snackbar (accepts a raw error and maps it to a friendly one).
void showErrorSnack(BuildContext context, Object error) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      backgroundColor: context.tokens.error,
      content: Row(children: [
        Icon(Icons.error_outline,
            color: context.tokens.onColor(context.tokens.error), size: 18),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            ErrorMapper.friendly(error),
            style: TextStyle(
                color: context.tokens.onColor(context.tokens.error)),
          ),
        ),
      ]),
    ));
}
