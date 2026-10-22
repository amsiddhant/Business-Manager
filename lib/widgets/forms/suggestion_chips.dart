import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_x.dart';
import '../../services/smart/suggestion_service.dart';

/// Up to three one-tap suggestions under a field. Tapping one fills the
/// field; nothing is ever filled without a tap. Hidden when there's nothing
/// to offer or every suggestion equals [current].
class SuggestionChips<T> extends StatelessWidget {
  const SuggestionChips({
    super.key,
    required this.suggestions,
    required this.labelOf,
    required this.onSelected,
    this.current,
  });

  final List<Suggestion<T>> suggestions;
  final String Function(T value) labelOf;
  final ValueChanged<T> onSelected;

  /// The field's value, which isn't offered again.
  final T? current;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final shown = [
      for (final s in suggestions)
        if (s.value != current) s,
    ].take(DartSuggestionProvider.maxSuggestions).toList();

    return AnimatedSize(
      duration: context.motion.fast,
      alignment: Alignment.topLeft,
      child: shown.isEmpty
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.auto_awesome, size: 14, color: t.primary),
                      const SizedBox(width: 4),
                      Text('Suggested',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: t.textTertiary)),
                    ],
                  ),
                  for (final s in shown)
                    Tooltip(
                      message: s.reason,
                      child: ActionChip(
                        label: Text(labelOf(s.value)),
                        labelStyle: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: t.primary),
                        backgroundColor: t.primarySurface,
                        side: BorderSide(
                            color: t.primary.withValues(alpha: 0.25)),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                        onPressed: () => onSelected(s.value),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
