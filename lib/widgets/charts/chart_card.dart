import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../common/app_card.dart';
import '../common/state_views.dart';

/// A titled card sized for a chart, with an empty state when there's no data.
class ChartCard extends StatelessWidget {
  const ChartCard({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
    this.height = 280,
    this.isEmpty = false,
    this.emptyMessage = 'No data for the selected period.',
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final double height;
  final bool isEmpty;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 15.5, fontWeight: FontWeight.w600)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!,
                          style: const TextStyle(
                              fontSize: 12.5,
                              color: AppColors.textSecondary)),
                    ],
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            height: height,
            child: isEmpty
                ? EmptyView(
                    icon: Icons.bar_chart_outlined,
                    title: 'Nothing to show',
                    message: emptyMessage,
                  )
                : child,
          ),
        ],
      ),
    );
  }
}

/// A small legend entry (colour swatch + label) for charts.
class ChartLegendDot extends StatelessWidget {
  const ChartLegendDot({super.key, required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(
                fontSize: 12, color: AppColors.textSecondary)),
      ],
    );
  }
}
