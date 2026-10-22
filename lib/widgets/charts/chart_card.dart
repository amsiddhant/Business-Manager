import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_x.dart';
import '../common/app_card.dart';
import '../common/state_views.dart';
import 'chart_kit.dart';

/// A titled card sized for a chart, with an empty state when there's no data.
///
/// With [table], a toggle in the header switches between the chart and its
/// figures as a table (also what screen readers get).
class ChartCard extends StatefulWidget {
  const ChartCard({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
    this.height = 280,
    this.isEmpty = false,
    this.emptyMessage = 'No data for the selected period.',
    this.icon,
    this.table,
    this.footer,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final double height;
  final bool isEmpty;
  final String emptyMessage;

  /// A small icon badge before the title.
  final IconData? icon;
  final ChartTableData? table;

  /// Shown under the chart (e.g. a legend), outside its fixed height.
  final Widget? footer;

  @override
  State<ChartCard> createState() => _ChartCardState();
}

class _ChartCardState extends State<ChartCard> {
  bool _asTable = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final table = widget.table;
    final showTable = _asTable && table != null && !widget.isEmpty;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (widget.icon != null) ...[
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: t.primarySurface,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  child: Icon(widget.icon, size: 18, color: t.primary),
                ),
                const SizedBox(width: AppSpacing.md),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                    if (widget.subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(widget.subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12.5, color: t.textSecondary)),
                    ],
                  ],
                ),
              ),
              ?widget.trailing,
              if (table != null && !widget.isEmpty)
                IconButton(
                  tooltip: _asTable ? 'View as chart' : 'View as table',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _asTable = !_asTable),
                  icon: Icon(
                      _asTable
                          ? Icons.insert_chart_outlined
                          : Icons.table_rows_outlined,
                      size: 18,
                      color: t.textSecondary),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            height: widget.height,
            child: widget.isEmpty
                ? EmptyView(
                    icon: Icons.bar_chart_outlined,
                    title: 'Nothing to show',
                    message: widget.emptyMessage,
                  )
                : AnimatedSwitcher(
                    duration: context.motion.base,
                    child: showTable
                        ? KeyedSubtree(
                            key: const ValueKey('table'),
                            child: ChartTable(data: table),
                          )
                        : KeyedSubtree(
                            key: const ValueKey('chart'),
                            child: RepaintBoundary(child: widget.child),
                          ),
                  ),
          ),
          if (widget.footer != null && !widget.isEmpty && !showTable) ...[
            const SizedBox(height: AppSpacing.md),
            widget.footer!,
          ],
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
            style: TextStyle(
                fontSize: 12, color: context.tokens.textSecondary)),
      ],
    );
  }
}
