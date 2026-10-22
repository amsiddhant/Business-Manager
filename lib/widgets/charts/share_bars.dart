import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_x.dart';
import 'chart_kit.dart';

/// One row of a [ShareBars] chart.
class ShareBar {
  const ShareBar({
    required this.label,
    required this.value,
    required this.display,
    this.caption,
    this.color,
  });

  final String label;

  /// Drives the bar's length, relative to the largest row (or [ShareBars.max]).
  final double value;

  /// The figure printed at the end of the row.
  final String display;

  /// Small text under the label (a share, a count).
  final String? caption;
  final Color? color;
}

/// Labelled horizontal bars — readable at any width, so they suit long names
/// (platforms, campaigns, businesses) better than a vertical bar chart. A
/// dashed [reference] marks a threshold (e.g. ROAS 1×).
class ShareBars extends StatelessWidget {
  const ShareBars({
    super.key,
    required this.id,
    required this.rows,
    this.max,
    this.reference,
    this.referenceLabel,
    this.onTap,
  });

  /// For the first-time draw-in.
  final String id;
  final List<ShareBar> rows;
  final double? max;
  final double? reference;
  final String? referenceLabel;
  final ValueChanged<int>? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    var top = max ?? 0;
    for (final r in rows) {
      if (r.value > top) top = r.value;
    }
    if (reference != null && reference! * 1.25 > top) top = reference! * 1.25;
    if (top <= 0) top = 1;

    return ChartReveal(
      id: id,
      builder: (context, k) => LayoutBuilder(builder: (context, c) {
        final labelWidth = (c.maxWidth * 0.34).clamp(90.0, 200.0);
        const valueWidth = 84.0;
        final barWidth = c.maxWidth - labelWidth - valueWidth - AppSpacing.md * 2;
        return Stack(
          children: [
            ListView.separated(
              padding: EdgeInsets.only(top: referenceLabel != null ? 18 : 0),
              itemCount: rows.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final r = rows[i];
                final color = r.color ?? t.chartSeries[i % t.chartSeries.length];
                final fraction = (r.value / top).clamp(0.0, 1.0) * k;
                final row = Row(
                  children: [
                    SizedBox(
                      width: labelWidth,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(r.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                  color: t.textPrimary)),
                          if (r.caption != null)
                            Text(r.caption!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 11, color: t.textTertiary)),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    SizedBox(
                      width: barWidth,
                      height: 12,
                      child: Stack(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: t.surfaceAlt,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          FractionallySizedBox(
                            widthFactor: fraction,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(colors: [
                                  color.withValues(alpha: 0.7),
                                  color,
                                ]),
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    SizedBox(
                      width: valueWidth,
                      child: Text(r.display,
                          textAlign: TextAlign.end,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: t.textPrimary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          )),
                    ),
                  ],
                );
                if (onTap == null) return row;
                return InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => onTap!(i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: row,
                  ),
                );
              },
            ),
            if (reference != null)
              Positioned(
                top: 0,
                bottom: 0,
                left: labelWidth +
                    AppSpacing.md +
                    barWidth * (reference! / top).clamp(0.0, 1.0),
                child: IgnorePointer(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (referenceLabel != null)
                        Text(referenceLabel!,
                            style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: t.textTertiary)),
                      Expanded(
                        child: CustomPaint(
                          size: const Size(1, double.infinity),
                          painter: _VDash(t.textTertiary),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      }),
    );
  }
}

class _VDash extends CustomPainter {
  const _VDash(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var y = 0.0; y < size.height; y += 6) {
      canvas.drawLine(Offset(0, y), Offset(0, y + 3), paint);
    }
  }

  @override
  bool shouldRepaint(_VDash old) => old.color != color;
}
