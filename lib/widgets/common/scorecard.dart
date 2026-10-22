import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_x.dart';
import 'app_card.dart';

/// A KPI scorecard: label, big value, icon, and an optional secondary line.
class Scorecard extends StatelessWidget {
  const Scorecard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.accent,
    this.caption,
    this.captionTone,
    this.tooltip,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  /// Icon tint; defaults to the brand colour.
  final Color? accent;
  final String? caption;
  final Color? captionTone;
  final String? tooltip;

  /// Opens the detail behind the figure (e.g. the matching report).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final accent = this.accent ?? t.primary;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      onTap: onTap,
      child: Semantics(
        label: '$label: $value${caption == null ? '' : ', $caption'}',
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: t.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (tooltip != null) ...[
                  Tooltip(
                    message: tooltip!,
                    child: Icon(Icons.info_outline,
                        size: 15, color: t.textTertiary),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                ],
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Color.alphaBlend(
                        accent.withValues(alpha: t.isDark ? 0.2 : 0.12), t.card),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  child: Icon(icon, color: accent, size: 18),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                  letterSpacing: -0.3,
                  color: t.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            if (caption != null) ...[
              const SizedBox(height: 4),
              Text(
                caption!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: captionTone ?? t.textTertiary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
