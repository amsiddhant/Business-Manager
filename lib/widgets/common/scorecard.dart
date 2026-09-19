import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import 'app_card.dart';

/// A KPI scorecard: label, big value, icon, and an optional secondary line.
class Scorecard extends StatelessWidget {
  const Scorecard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.accent = AppColors.primary,
    this.caption,
    this.captionTone,
    this.tooltip,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accent;
  final String? caption;
  final Color? captionTone;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final card = AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Icon(icon, color: accent, size: 20),
              ),
              const Spacer(),
              if (tooltip != null)
                Tooltip(
                  message: tooltip!,
                  child: const Icon(Icons.info_outline,
                      size: 16, color: AppColors.textTertiary),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            label,
            style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12.5,
                fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w700, height: 1.1),
            ),
          ),
          if (caption != null) ...[
            const SizedBox(height: 4),
            Text(
              caption!,
              style: TextStyle(
                  color: captionTone ?? AppColors.textTertiary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500),
            ),
          ],
        ],
      ),
    );
    return card;
  }
}
