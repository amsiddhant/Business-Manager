import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/enums.dart';
import '../../core/theme/theme_x.dart';
import '../../core/utils/money.dart';
import '../../services/profit_calculation_service.dart';
import 'chart_kit.dart';

/// Revenue stepping down through each cost to net profit: each cost is a
/// floating bar from the running total before it to the one after.
class ProfitWaterfallChart extends StatelessWidget {
  const ProfitWaterfallChart({
    super.key,
    required this.steps,
    required this.currency,
  });

  final List<WaterfallStep> steps;
  final CurrencyCode currency;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    var maxV = 0.0, minV = 0.0;
    for (final s in steps) {
      maxV = math.max(maxV, math.max(s.start.major, s.end.major));
      minV = math.min(minV, math.min(s.start.major, s.end.major));
    }
    final maxY = ChartKit.niceMax(maxV);
    final minY = minV < 0 ? -ChartKit.niceMax(-minV) : 0.0;

    Color colorOf(WaterfallStep s, int i) {
      // The costs keep their colours from Revenue vs Expenses.
      const costSeries = [3, 6, 5];
      if (s.kind == WaterfallKind.decrease) {
        return t.chartSeries[costSeries[(i - 1).clamp(0, 2)]];
      }
      if (i == 0) return t.chartSeries[0];
      return s.end.isNegative ? t.error : t.success;
    }

    String signed(WaterfallStep s) => s.kind == WaterfallKind.decrease
        ? '− ${MoneyFormatter.format(s.amount, currency)}'
        : MoneyFormatter.format(s.amount, currency);

    return LayoutBuilder(builder: (context, c) {
      final plotWidth = c.maxWidth - 52;
      final rodWidth =
          (plotWidth / math.max(1, steps.length) * 0.56).clamp(14.0, 56.0);
      return ChartReveal(
        id: 'profit-waterfall',
        builder: (context, k) => BarChart(
          duration: context.motion.base,
          curve: AppMotion.standard,
          BarChartData(
            alignment: BarChartAlignment.spaceAround,
            maxY: maxY,
            minY: minY,
            gridData: ChartKit.grid(context),
            borderData: FlBorderData(show: false),
            extraLinesData: ExtraLinesData(
              horizontalLines: [
                HorizontalLine(y: 0, color: t.borderStrong, strokeWidth: 1),
              ],
            ),
            barTouchData: BarTouchData(
              touchTooltipData: ChartKit.barTooltip(context,
                  item: (group, _, _, _) {
                final s = steps[group.x];
                return BarTooltipItem(
                  s.label,
                  ChartKit.tooltipTitle(context),
                  children: [
                    TextSpan(
                        text: '\n${signed(s)}',
                        style: ChartKit.tooltipBody(context)),
                    if (s.kind == WaterfallKind.decrease)
                      TextSpan(
                          text: '\nLeaves '
                              '${MoneyFormatter.format(s.end, currency)}',
                          style: ChartKit.tooltipBody(context,
                              color: t.onInverseSurface
                                  .withValues(alpha: 0.7))),
                  ],
                );
              }),
            ),
            titlesData: FlTitlesData(
              topTitles: ChartKit.none,
              rightTitles: ChartKit.none,
              leftTitles: ChartKit.valueAxis(context, currency: currency),
              bottomTitles: ChartKit.labelAxis(
                  context, [for (final s in steps) s.label],
                  width: plotWidth, minGap: 40, maxChars: 12),
            ),
            barGroups: [
              for (var i = 0; i < steps.length; i++)
                BarChartGroupData(
                  x: i,
                  barRods: [
                    _rod(steps[i], colorOf(steps[i], i), rodWidth, k),
                  ],
                ),
            ],
          ),
        ),
      );
    });
  }

  BarChartRodData _rod(WaterfallStep s, Color color, double width, double k) {
    final from = s.start.major * k, to = s.end.major * k;
    final lo = math.min(from, to), hi = math.max(from, to);
    return BarChartRodData(
      fromY: lo,
      toY: hi == lo ? lo + 0.0001 : hi,
      width: width,
      gradient: ChartKit.barGradient(color,
          down: s.kind == WaterfallKind.decrease || s.end.isNegative),
      borderRadius: BorderRadius.circular(4),
    );
  }
}
