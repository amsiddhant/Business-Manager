import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/routing/nav_registry.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_x.dart';
import '../../state/data_controller.dart';
import '../../state/filter_controller.dart';
import 'business_selector.dart';
import 'period_selector.dart';

/// The business and/or period selectors a page uses, side by side.
class ScopeSelectors extends StatelessWidget {
  const ScopeSelectors({super.key, required this.use});

  final ScopeUse use;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (use.usesBusiness) const BusinessSelector(),
        if (use.usesBusiness && use.usesPeriod)
          const SizedBox(width: AppSpacing.sm),
        if (use.usesPeriod) const PeriodSelector(),
      ],
    );
  }
}

/// One compact pill summarising the scope ("Acme · FY 2026-27"); tapping it
/// opens a sheet with the selectors. Used where the selectors don't fit.
class ScopePill extends StatelessWidget {
  const ScopePill({super.key, required this.use, this.expand = false});

  final ScopeUse use;

  /// Fill the available width (mobile) instead of hugging the content.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final filter = context.watch<FilterController>();
    final bizName = context.select<DataController, String>((d) {
      final id = filter.selectedBusinessId;
      return (id == null ? null : d.businessById(id)?.name) ??
          'All businesses';
    });

    final parts = <(IconData, String)>[
      if (use.usesBusiness) (Icons.apartment, bizName),
      if (use.usesPeriod) (Icons.calendar_month_outlined, filter.periodLabel),
    ];

    return Semantics(
      button: true,
      label: 'Change scope: ${parts.map((p) => p.$2).join(', ')}',
      excludeSemantics: true,
      child: Material(
        color: t.card,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: t.border),
          borderRadius: BorderRadius.circular(999),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => showScopeSheet(context, use),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            child: Row(
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              children: [
                for (var i = 0; i < parts.length; i++) ...[
                  if (i > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text('·', style: TextStyle(color: t.textTertiary)),
                    ),
                  Icon(parts[i].$1, size: 16, color: t.textSecondary),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      parts[i].$2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: t.textPrimary,
                      ),
                    ),
                  ),
                ],
                if (expand) const Spacer(),
                const SizedBox(width: 4),
                Icon(Icons.expand_more, size: 18, color: t.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A bottom sheet with the scope selectors [use] needs.
Future<void> showScopeSheet(BuildContext context, ScopeUse use) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Showing data for',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.lg),
            if (use.usesBusiness) ...[
              const _SheetLabel('Business'),
              const BusinessSelector(),
              const SizedBox(height: AppSpacing.lg),
            ],
            if (use.usesPeriod) ...[
              const _SheetLabel('Period'),
              const Align(
                alignment: Alignment.centerLeft,
                child: PeriodSelector(),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SheetLabel extends StatelessWidget {
  const _SheetLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: context.tokens.textSecondary,
          ),
        ),
      );
}
