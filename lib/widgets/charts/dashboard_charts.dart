import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/enums.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_x.dart';
import '../../core/utils/money.dart';
import '../../services/profit_calculation_service.dart';
import 'chart_kit.dart';

/// Grouped bars per period: revenue, product cost, marketing, operating
/// expenses and net profit. Tap a legend entry to hide or show a series;
/// hovering a period lists all of its figures.
class RevenueExpenseChart extends StatefulWidget {
  const RevenueExpenseChart({
    super.key,
    required this.points,
    required this.currency,
  });

  final List<TimeSeriesPoint> points;
  final CurrencyCode currency;

  @override
  State<RevenueExpenseChart> createState() => _RevenueExpenseChartState();
}

class _RevenueExpenseChartState extends State<RevenueExpenseChart> {
  final Set<int> _hidden = {};

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final currency = widget.currency;
    final points = widget.points;
    final series = <(String, Color, Money Function(TimeSeriesPoint))>[
      ('Revenue', t.chartSeries[0], (p) => p.revenue),
      ('Product Cost', t.chartSeries[3], (p) => p.productCost),
      ('Marketing', t.chartSeries[6], (p) => p.marketingCost),
      ('Operating', t.chartSeries[5], (p) => p.operatingExpenses),
      ('Net Profit', t.chartSeries[2], (p) => p.netProfit),
    ];
    final visible = [
      for (var i = 0; i < series.length; i++)
        if (!_hidden.contains(i)) i,
    ];
    var maxV = 0.0, minV = 0.0;
    for (final p in points) {
      for (final i in visible) {
        final v = series[i].$3(p).major;
        maxV = math.max(maxV, v);
        minV = math.min(minV, v);
      }
    }
    final maxY = ChartKit.niceMax(maxV);
    final minY = minV < 0 ? -ChartKit.niceMax(-minV) : 0.0;

    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(builder: (context, c) {
            final plotWidth = c.maxWidth - 52;
            final groupWidth = plotWidth / math.max(1, points.length);
            final rodWidth = (groupWidth * 0.7 / math.max(1, visible.length))
                .clamp(3.0, 14.0);
            return ChartReveal(
              id: 'revenue-expense',
              builder: (context, k) => BarChart(
                duration: context.motion.base,
                curve: AppMotion.standard,
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: maxY,
                  minY: minY,
                  gridData: ChartKit.grid(context),
                  borderData: FlBorderData(show: false),
                  barTouchData: BarTouchData(
                    touchTooltipData: ChartKit.barTooltip(context,
                        item: (group, _, _, _) {
                      final p = points[group.x];
                      return BarTooltipItem(
                        p.label,
                        ChartKit.tooltipTitle(context),
                        textAlign: TextAlign.start,
                        children: [
                          for (final i in visible) ...[
                            TextSpan(
                                text: '\n● ',
                                style: TextStyle(color: series[i].$2)),
                            TextSpan(
                                text: '${series[i].$1}  '
                                    '${MoneyFormatter.format(series[i].$3(p), currency)}',
                                style: ChartKit.tooltipBody(context)),
                          ],
                        ],
                      );
                    }),
                  ),
                  titlesData: FlTitlesData(
                    topTitles: ChartKit.none,
                    rightTitles: ChartKit.none,
                    leftTitles: ChartKit.valueAxis(context, currency: currency),
                    bottomTitles: ChartKit.labelAxis(
                        context, [for (final p in points) p.label],
                        width: plotWidth),
                  ),
                  barGroups: [
                    for (var g = 0; g < points.length; g++)
                      BarChartGroupData(
                        x: g,
                        barsSpace: 2,
                        barRods: [
                          for (final i in visible)
                            moneyRod(series[i].$3(points[g]).major * k,
                                series[i].$2, rodWidth),
                        ],
                      ),
                  ],
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: AppSpacing.md),
        ChartLegend(
          entries: [for (final s in series) LegendEntry(s.$1, s.$2)],
          hidden: _hidden,
          onToggle: (i) => setState(
              () => _hidden.contains(i) ? _hidden.remove(i) : _hidden.add(i)),
        ),
      ],
    );
  }
}

/// A gradient bar from zero to [value] (downwards when negative).
BarChartRodData moneyRod(double value, Color color, double width) {
  final down = value < 0;
  final r = Radius.circular(math.min(4, width / 2));
  return BarChartRodData(
    fromY: 0,
    toY: value,
    gradient: ChartKit.barGradient(color, down: down),
    width: width,
    borderRadius: down
        ? BorderRadius.vertical(bottom: r)
        : BorderRadius.vertical(top: r),
  );
}

/// A donut of amounts by label, with the total (or the touched slice) in the
/// middle and a legend beside or below it.
class ExpenseDonutChart extends StatefulWidget {
  const ExpenseDonutChart({
    super.key,
    required this.slices,
    required this.currency,
    this.centerLabel = 'Total',
    this.revealId = 'expense-donut',
  });

  final List<CategorySlice> slices;
  final CurrencyCode currency;
  final String centerLabel;
  final String revealId;

  @override
  State<ExpenseDonutChart> createState() => _ExpenseDonutChartState();
}

class _ExpenseDonutChartState extends State<ExpenseDonutChart> {
  int? _touched;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final slices = widget.slices;
    final currency = widget.currency;
    final total = slices.fold(Money.zero, (s, e) => s + e.amount);
    Color colorOf(int i) => t.chartSeries[i % t.chartSeries.length];
    String share(Money m) => total.isZero
        ? '0%'
        : PercentFormatter.format(m.major / total.major * 100, decimals: 0);

    final touched = _touched != null && _touched! < slices.length
        ? slices[_touched!]
        : null;

    Widget donut(double side, double k) {
      final ring = side * 0.15;
      final hole = side * 0.31;
      return Stack(
        alignment: Alignment.center,
        children: [
          PieChart(
            duration: context.motion.base,
            curve: AppMotion.standard,
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: hole,
              startDegreeOffset: -90,
              pieTouchData: PieTouchData(
                touchCallback: (event, response) {
                  final i = event.isInterestedForInteractions
                      ? response?.touchedSection?.touchedSectionIndex
                      : null;
                  final next = i != null && i >= 0 ? i : null;
                  if (next != _touched) setState(() => _touched = next);
                },
              ),
              sections: [
                for (var i = 0; i < slices.length; i++)
                  PieChartSectionData(
                    value: math.max(slices[i].amount.major, 0),
                    color: _touched == null || _touched == i
                        ? colorOf(i)
                        : colorOf(i).withValues(alpha: 0.35),
                    radius: _touched == i ? ring + 6 : ring,
                    showTitle: false,
                  ),
              ],
            ),
          ),
          Opacity(
            opacity: k,
            child: SizedBox(
              width: hole * 1.7,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(touched?.label ?? widget.centerLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11.5, color: t.textTertiary)),
                  const SizedBox(height: 2),
                  FittedBox(
                    child: Text(
                      MoneyFormatter.compact(
                          touched?.amount ?? total, currency),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: t.textPrimary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  if (touched != null)
                    Text(share(touched.amount),
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: colorOf(_touched!))),
                ],
              ),
            ),
          ),
        ],
      );
    }

    Widget legend({required bool scroll}) {
      final rows = [
        for (var i = 0; i < slices.length; i++)
          MouseRegion(
            onEnter: (_) => setState(() => _touched = i),
            onExit: (_) => setState(() => _touched = null),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: colorOf(i),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(slices[i].label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12.5,
                            color: _touched == i
                                ? t.textPrimary
                                : t.textSecondary)),
                  ),
                  const SizedBox(width: 6),
                  Text(share(slices[i].amount),
                      style: TextStyle(fontSize: 11.5, color: t.textTertiary)),
                  const SizedBox(width: 8),
                  Text(
                    MoneyFormatter.compact(slices[i].amount, currency),
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ];
      return scroll
          ? ListView(shrinkWrap: true, children: rows)
          : Column(mainAxisSize: MainAxisSize.min, children: rows);
    }

    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 420;
      return ChartReveal(
        id: widget.revealId,
        builder: (context, k) => Opacity(
          opacity: k.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: 0.9 + 0.1 * k,
            child: wide
                ? Row(
                    children: [
                      Expanded(
                        flex: 5,
                        child: LayoutBuilder(
                          builder: (context, d) => donut(
                              math.min(d.maxWidth, d.maxHeight), k),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.lg),
                      Expanded(
                        flex: 5,
                        child: Center(child: legend(scroll: true)),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, d) => donut(
                              math.min(d.maxWidth, d.maxHeight), k),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      ConstrainedBox(
                        constraints:
                            BoxConstraints(maxHeight: c.maxHeight * 0.42),
                        child: legend(scroll: true),
                      ),
                    ],
                  ),
          ),
        ),
      );
    });
  }
}

/// Vertical bars of one amount per label ("Revenue by Product", "Profit by
/// Product"). Negative amounts go below the axis in the error colour.
class CategoryBarChart extends StatelessWidget {
  const CategoryBarChart({
    super.key,
    required this.labels,
    required this.values,
    required this.currency,
    this.color,
    this.revealId,
  });

  final List<String> labels;
  final List<Money> values;
  final CurrencyCode currency;

  /// Series colour; defaults to the brand colour.
  final Color? color;
  final String? revealId;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = this.color ?? t.primary;
    final maxV = values.fold<double>(0, (m, v) => math.max(m, v.major));
    final minV = values.fold<double>(0, (m, v) => math.min(m, v.major));
    final maxY = ChartKit.niceMax(maxV);
    final minY = minV < 0 ? -ChartKit.niceMax(-minV) : 0.0;
    return LayoutBuilder(builder: (context, c) {
      final plotWidth = c.maxWidth - 52;
      final rodWidth =
          (plotWidth / math.max(1, values.length) * 0.5).clamp(8.0, 32.0);
      return ChartReveal(
        id: revealId ?? 'category-${labels.join('|').hashCode}',
        builder: (context, k) => BarChart(
          duration: context.motion.base,
          curve: AppMotion.standard,
          BarChartData(
            alignment: BarChartAlignment.spaceAround,
            maxY: maxY,
            minY: minY,
            gridData: ChartKit.grid(context),
            borderData: FlBorderData(show: false),
            barTouchData: BarTouchData(
              touchTooltipData: ChartKit.barTooltip(context,
                  item: (group, _, _, _) => BarTooltipItem(
                        labels[group.x],
                        ChartKit.tooltipTitle(context),
                        children: [
                          TextSpan(
                              text:
                                  '\n${MoneyFormatter.format(values[group.x], currency)}',
                              style: ChartKit.tooltipBody(context)),
                        ],
                      )),
            ),
            titlesData: FlTitlesData(
              topTitles: ChartKit.none,
              rightTitles: ChartKit.none,
              leftTitles: ChartKit.valueAxis(context, currency: currency),
              bottomTitles: ChartKit.labelAxis(context, labels,
                  width: plotWidth, minGap: 56, maxChars: 9),
            ),
            barGroups: [
              for (var i = 0; i < values.length; i++)
                BarChartGroupData(
                  x: i,
                  barRods: [
                    moneyRod(values[i].major * k,
                        values[i].isNegative ? t.error : color, rodWidth),
                  ],
                ),
            ],
          ),
        ),
      );
    });
  }
}

/// A single-series line over time (orders trend, marketing spend), with a
/// soft gradient fill and a crosshair on hover.
class TrendLineChart extends StatelessWidget {
  const TrendLineChart({
    super.key,
    required this.labels,
    required this.values,
    this.color,
    this.currency,
    this.revealId,
    this.seriesLabel,
  });

  final List<String> labels;

  /// Y values as plain doubles (orders count) — for money pass major units.
  final List<double> values;

  /// Series colour; defaults to the brand colour.
  final Color? color;

  /// When set, the axis and tooltip are formatted as money.
  final CurrencyCode? currency;
  final String? revealId;

  /// Names the figure in the tooltip ("Orders", "Spend").
  final String? seriesLabel;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = this.color ?? t.primary;
    final maxY = ChartKit.niceMax(values.fold<double>(0, math.max));
    String fmt(double v) => currency != null
        ? MoneyFormatter.format(Money.fromMajor(v), currency!)
        : v.round().toString();
    return LayoutBuilder(builder: (context, c) {
      final plotWidth = c.maxWidth - (currency != null ? 52 : 34);
      return ChartReveal(
        id: revealId ?? 'trend-${seriesLabel ?? ''}-${labels.length}',
        builder: (context, k) => LineChart(
          duration: context.motion.base,
          curve: AppMotion.standard,
          LineChartData(
            minY: 0,
            maxY: maxY,
            minX: 0,
            maxX: math.max(0, values.length - 1).toDouble(),
            gridData: ChartKit.grid(context),
            borderData: FlBorderData(show: false),
            lineTouchData: LineTouchData(
              getTouchedSpotIndicator: (bar, indexes) => [
                for (final _ in indexes)
                  TouchedSpotIndicatorData(
                    FlLine(
                        color: t.borderStrong,
                        strokeWidth: 1,
                        dashArray: const [3, 3]),
                    FlDotData(
                      getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                        radius: 5,
                        color: color,
                        strokeWidth: 2,
                        strokeColor: t.card,
                      ),
                    ),
                  ),
              ],
              touchTooltipData: ChartKit.lineTooltip(context,
                  items: (spots) => [
                        for (final s in spots)
                          LineTooltipItem(
                            labels[s.x.toInt()],
                            ChartKit.tooltipTitle(context),
                            children: [
                              TextSpan(
                                text:
                                    '\n${seriesLabel == null ? '' : '$seriesLabel  '}'
                                    '${fmt(values[s.x.toInt()])}',
                                style: ChartKit.tooltipBody(context),
                              ),
                            ],
                          ),
                      ]),
            ),
            titlesData: FlTitlesData(
              topTitles: ChartKit.none,
              rightTitles: ChartKit.none,
              leftTitles: ChartKit.valueAxis(context, currency: currency),
              bottomTitles:
                  ChartKit.labelAxis(context, labels, width: plotWidth),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: [
                  for (var i = 0; i < values.length; i++)
                    FlSpot(i.toDouble(), values[i] * k),
                ],
                isCurved: true,
                preventCurveOverShooting: true,
                color: color,
                barWidth: 2.5,
                isStrokeCapRound: true,
                dotData: FlDotData(
                  show: values.length <= 12,
                  getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                    radius: 3,
                    color: t.card,
                    strokeWidth: 2,
                    strokeColor: color,
                  ),
                ),
                belowBarData: ChartKit.areaUnder(color),
              ),
            ],
          ),
        ),
      );
    });
  }
}
