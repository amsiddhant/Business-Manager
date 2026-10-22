import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_x.dart';
import 'app_form.dart';

/// A titled group of fields in a form ("Pricing", "Dates"…). Long forms get
/// a row of chips at the top that jump to each section.
class FormSection extends StatefulWidget {
  const FormSection({
    super.key,
    required this.title,
    required this.children,
    this.icon,
    this.description,
    this.first = false,
  });

  final String title;
  final IconData? icon;
  final String? description;
  final List<Widget> children;

  /// The first section: no rule above it.
  final bool first;

  @override
  State<FormSection> createState() => _FormSectionState();
}

class _FormSectionState extends State<FormSection> {
  final _key = GlobalKey();
  FormHooks? _hooks;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final hooks = FormHooksScope.maybeOf(context);
    if (hooks != _hooks) {
      _hooks?.unregisterSection(_key);
      _hooks = hooks;
      hooks?.registerSection(_key, widget.title, widget.icon);
    }
  }

  @override
  void dispose() {
    _hooks?.unregisterSection(_key);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      key: _key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.first) ...[
          const SizedBox(height: AppSpacing.sm),
          Divider(height: 1, color: t.border),
          const SizedBox(height: AppSpacing.xl),
        ],
        Row(
          children: [
            if (widget.icon != null) ...[
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: t.primarySurface,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Icon(widget.icon, size: 16, color: t.primary),
              ),
              const SizedBox(width: AppSpacing.md),
            ],
            Expanded(
              child: Text(widget.title,
                  style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: t.textPrimary)),
            ),
          ],
        ),
        if (widget.description != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(widget.description!,
              style: TextStyle(fontSize: 12.5, color: t.textSecondary)),
        ],
        const SizedBox(height: AppSpacing.lg),
        for (var i = 0; i < widget.children.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.lg),
          widget.children[i],
        ],
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }
}
