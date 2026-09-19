import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../common/responsive.dart';

/// A responsive modal shell used by all create/edit forms. On desktop/tablet it
/// renders as a centered dialog; on mobile it becomes a full-height sheet.
///
/// Handles the submit lifecycle: shows a spinner on the primary button while
/// [onSubmit] runs and prevents duplicate submissions.
class FormDialog extends StatefulWidget {
  const FormDialog({
    super.key,
    required this.title,
    required this.child,
    required this.onSubmit,
    this.submitLabel = 'Save',
    this.width = 560,
  });

  final String title;
  final Widget child;

  /// Performs the save. Returns true to close the dialog, false to keep it open
  /// (e.g. validation failed). Exceptions are surfaced via a snackbar.
  final Future<bool> Function() onSubmit;
  final String submitLabel;
  final double width;

  @override
  State<FormDialog> createState() => _FormDialogState();
}

class _FormDialogState extends State<FormDialog> {
  bool _submitting = false;

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      final shouldClose = await widget.onSubmit();
      if (shouldClose && mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(context),
        const Divider(height: 1),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: widget.child,
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed:
                    _submitting ? null : () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: AppSpacing.sm),
              ElevatedButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text(widget.submitLabel),
              ),
            ],
          ),
        ),
      ],
    );

    if (isMobile) {
      return Dialog(
        insetPadding: const EdgeInsets.all(AppSpacing.md),
        child: content,
      );
    }
    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: widget.width,
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: content,
      ),
    );
  }

  Widget _header(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl, AppSpacing.lg, AppSpacing.md, AppSpacing.lg),
        child: Row(
          children: [
            Expanded(
              child: Text(widget.title,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            IconButton(
              onPressed:
                  _submitting ? null : () => Navigator.of(context).pop(false),
              icon: const Icon(Icons.close, color: AppColors.textSecondary),
            ),
          ],
        ),
      );
}

/// Two fields side-by-side on wide layouts, stacked on mobile.
class FormRow extends StatelessWidget {
  const FormRow(this.children, {super.key});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (Responsive.isMobile(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.lg),
            children[i],
          ],
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.lg),
          Expanded(child: children[i]),
        ],
      ],
    );
  }
}

/// Vertical spacing between form fields.
class FormGap extends StatelessWidget {
  const FormGap({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox(height: AppSpacing.lg);
}
