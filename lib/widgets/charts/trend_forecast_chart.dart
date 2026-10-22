import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/enums.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_x.dart';
import '../../core/utils/money.dart';
import '../../services/profit_calculation_service.dart';
import 'chart_kit.dart';

/// Revenue and net profit over the period: actuals as solid lines and, while
/// the period is running, the run-rate projection for the rest of it as
/// dashed lines from today on.
class TrendForecastChart extends StatefulWidget {
  const TrendForecastChart({
    super.key,
    required this.points,
    required this.currency,
    this.projectionLabel,
  });

  final List<ForecastPoint> points;
  final CurrencyCode currency;

  /// What the dashed lines are called in the legend (default: "Projected at
  /// current pace").
  final String? projectionLabel;

  /// Whether any point carries the 80% range around its projection.
  static bool hasBand(List<ForecastPoint> points) => points.any((p) =>
      (p.projectedRevenueLow != null && p.projectedRevenueHigh != null) ||
      (p.projectedNetProfitLow != null && p.projectedNetProfitHigh != null));

  /// The chart's figures as a table (what "View as table" shows). The range
  /// columns appear only when the points have one.
  static ChartTableData tableOf(
    List<ForecastPoint> points,
    CurrencyCode currency, {
    bool projections = true,
  }) {
    String opt(Money? m) => m == null ? '—' : MoneyFormatter.format(m, currency);
    String range(Money? low, Money? high) => low == null || high == null
        ? '—'
        : '${MoneyFormatter.compact(low, currency)} to '
            '${MoneyFormatter.compact(high, currency)}';
    final band = projections && hasBand(points);
    return ChartTableData(
      headers: [
        'Period',
        'Revenue',
        'Net Profit',
        if (projections) ...['Projected revenue', 'Projected net profit'],
        if (band) ...['Revenue range (80%)', 'Net profit range (80%)'],
      ],
      rows: [
        for (final p in points)
          [
            p.label,
            opt(p.revenue),
            opt(p.netProfit),
            if (projections) ...[
              opt(p.projectedRevenue),
              opt(p.projectedNetProfit),
            ],
            if (band) ...[
              range(p.projectedRevenueLow, p.projectedRevenueHigh),
              range(p.projectedNetProfitLow, p.projectedNetProfitHigh),
            ],
          ],
      ],
    );
  }

  @override
  State<TrendForecastChart> createState() => _TrendForecastChartState();
}

class _TrendForecastChartState extends State<TrendForecastChart> {
  final Set<int> _hidden = {};

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final points = widget.points;
    final currency = widget.currency;
    final metrics = <(String, Color, Money? Function(ForecastPoint),
        Money? Function(ForecastPoint))>[
      ('Revenue', t.chartSeries[0], (p) => p.revenue,
          (p) => p.projectedRevenue),
      ('Net Profit', t.chartSeries[2], (p) => p.netProfit,
          (p) => p.projectedNetProfit),
    ];
    final bands = <(Money? Function(ForecastPoint), Money? Function(ForecastPoint))>[
      ((p) => p.projectedRevenueLow, (p) => p.projectedRevenueHigh),
      ((p) => p.projectedNetProfitLow, (p) => p.projectedNetProfitHigh),
    ];
    bool bandAt(int m, ForecastPoint p) =>
        bands[m].$1(p) != null && bands[m].$2(p) != null;
    bool metricBand(int m) =>
        !_hidden.contains(m) && points.any((p) => bandAt(m, p));
    final hasBand = [for (var m = 0; m < metrics.length; m++) metricBand(m)]
        .any((b) => b);
    final firstProjected = points.indexWhere((p) => p.projectedRevenue != null);
    final hasProjection = firstProjected >= 0;
    final today = hasProjection && points[firstProjected].revenue != null
        ? firstProjected
        : (hasProjection ? firstProjected - 1 : -1);

    var maxV = 0.0, minV = 0.0;
    for (final p in points) {
      for (var m = 0; m < metrics.length; m++) {
        if (_hidden.contains(m)) continue;
        for (final v in [
          metrics[m].$3(p),
          metrics[m].$4(p),
          bands[m].$1(p),
          bands[m].$2(p),
        ]) {
          if (v == null) continue;
          maxV = math.max(maxV, v.major);
          minV = math.min(minV, v.major);
        }
      }
    }
    final maxY = ChartKit.niceMax(maxV);
    final minY = minV < 0 ? -ChartKit.niceMax(-minV) : 0.0;

    // Bars in drawing order, with what each one is called in the tooltip.
    final names = <String>[];
    // The metric of each bar, to look its 80% range up in the tooltip.
    final metricOf = <int>[];
    final fills = <BetweenBarsData>[];
    List<LineChartBarData> bars(double k) {
      names.clear();
      metricOf.clear();
      fills.clear();
      final result = <LineChartBarData>[];
      for (var m = 0; m < metrics.length; m++) {
        if (_hidden.contains(m)) continue;
        final (name, color, actual, projected) = metrics[m];
        names.add(name);
        metricOf.add(m);
        result.add(LineChartBarData(
          spots: [
            for (var i = 0; i < points.length; i++)
              if (actual(points[i]) case final v?)
                FlSpot(i.toDouble(), v.major * k)
              else
                FlSpot.nullSpot,
          ],
          isCurved: true,
          preventCurveOverShooting: true,
          color: color,
          barWidth: 2.5,
          isStrokeCapRound: true,
          dotData: FlDotData(
            show: points.length <= 12,
            getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                radius: 3, color: t.card, strokeWidth: 2, strokeColor: color),
          ),
          belowBarData: m == 0 ? ChartKit.areaUnder(color) : BarAreaData(),
        ));
        if (!hasProjection) continue;
        names.add('$name (projected)');
        metricOf.add(m);
        result.add(LineChartBarData(
          spots: [
            for (var i = 0; i < points.length; i++)
              if (i == firstProjected - 1 && actual(points[i]) != null)
                FlSpot(i.toDouble(), actual(points[i])!.major * k)
              else if (projected(points[i]) case final v?)
                FlSpot(i.toDouble(), v.major * k)
              else
                FlSpot.nullSpot,
          ],
          isCurved: true,
          preventCurveOverShooting: true,
          color: color.withValues(alpha: 0.8),
          barWidth: 2,
          dashArray: const [6, 4],
          dotData: const FlDotData(show: false),
        ));
      }
      // The 80% range: two invisible lines with a faint fill between them,
      // after the visible bars so their indexes stay put.
      for (var m = 0; m < metrics.length; m++) {
        if (!metricBand(m)) continue;
        final color = metrics[m].$2;
        final actual = metrics[m].$3;
        List<FlSpot> edge(Money? Function(ForecastPoint) of) => [
              for (var i = 0; i < points.length; i++)
                if (bandAt(m, points[i]))
                  FlSpot(i.toDouble(), of(points[i])!.major * k)
                else if (i == firstProjected - 1 &&
                    i + 1 < points.length &&
                    bandAt(m, points[i + 1]) &&
                    actual(points[i]) != null)
                  // Starts where the actuals end, with no range yet.
                  FlSpot(i.toDouble(), actual(points[i])!.major * k),
            ];
        LineChartBarData line(List<FlSpot> spots) => LineChartBarData(
              spots: spots,
              isCurved: true,
              preventCurveOverShooting: true,
              color: Colors.transparent,
              barWidth: 0,
              dotData: const FlDotData(show: false),
            );
        final from = result.length;
        names.addAll(const ['', '']);
        metricOf.addAll([m, m]);
        result
          ..add(line(edge((p) => bands[m].$1(p))))
          ..add(line(edge((p) => bands[m].$2(p))));
        fills.add(BetweenBarsData(
          fromIndex: from,
          toIndex: from + 1,
          color: color.withValues(alpha: 0.14),
        ));
      }
      return result;
    }

    /// "80% range ₹1.2L to ₹1.5L" for the projected point of [bar] at [x].
    String? rangeAt(int bar, int x) {
      if (bar >= names.length || !names[bar].endsWith('(projected)')) {
        return null;
      }
      final m = metricOf[bar];
      final p = points[x];
      if (!bandAt(m, p)) return null;
      return '80% range '
          '${MoneyFormatter.compact(bands[m].$1(p)!, currency)} to '
          '${MoneyFormatter.compact(bands[m].$2(p)!, currency)}';
    }

    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(builder: (context, c) {
            final plotWidth = c.maxWidth - 52;
            return ChartReveal(
              id: 'trend-forecast',
              builder: (context, k) => LineChart(
                duration: context.motion.base,
                curve: AppMotion.standard,
                LineChartData(
                  minY: minY,
                  maxY: maxY,
                  minX: 0,
                  maxX: math.max(0, points.length - 1).toDouble(),
                  gridData: ChartKit.grid(context),
                  borderData: FlBorderData(show: false),
                  extraLinesData: ExtraLinesData(
                    horizontalLines: [
                      if (minY < 0)
                        HorizontalLine(
                            y: 0, color: t.borderStrong, strokeWidth: 1),
                    ],
                    verticalLines: [
                      if (today >= 0)
                        VerticalLine(
                          x: today.toDouble(),
                          color: t.textTertiary.withValues(alpha: 0.6),
                          strokeWidth: 1,
                          dashArray: const [2, 3],
                          label: VerticalLineLabel(
                            show: true,
                            alignment: Alignment.topRight,
                            padding: const EdgeInsets.only(left: 4, top: 2),
                            style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: t.textTertiary),
                            labelResolver: (_) => 'Today',
                          ),
                        ),
                    ],
                  ),
                  lineTouchData: LineTouchData(
                    getTouchedSpotIndicator: (bar, indexes) => [
                      for (final _ in indexes)
                        // The range's invisible lines get no marker.
                        if (bar.color == Colors.transparent)
                          const TouchedSpotIndicatorData(
                              FlLine(strokeWidth: 0, color: Colors.transparent),
                              FlDotData(show: false))
                        else
                          TouchedSpotIndicatorData(
                            FlLine(
                                color: t.borderStrong,
                                strokeWidth: 1,
                                dashArray: const [3, 3]),
                            FlDotData(
                              getDotPainter: (_, _, bar, _) =>
                                  FlDotCirclePainter(
                                radius: 4.5,
                                color: bar.color ?? t.primary,
                                strokeWidth: 2,
                                strokeColor: t.card,
                              ),
                            ),
                          ),
                    ],
                    touchTooltipData: ChartKit.lineTooltip(context,
                        items: (spots) {
                      final shown = [
                        for (final s in spots)
                          if (names[s.barIndex].isNotEmpty) s,
                      ];
                      return [
                        for (final s in spots)
                          if (names[s.barIndex].isEmpty)
                            null
                          else
                            LineTooltipItem(
                              identical(s, shown.first)
                                  ? '${points[s.x.toInt()].label}\n'
                                  : '',
                              ChartKit.tooltipTitle(context),
                              textAlign: TextAlign.start,
                              children: [
                                TextSpan(
                                  text: '${names[s.barIndex]}  '
                                      '${MoneyFormatter.format(Money.fromMajor(s.y), currency)}',
                                  style: ChartKit.tooltipBody(context),
                                ),
                                if (rangeAt(s.barIndex, s.x.toInt())
                                    case final r?)
                                  TextSpan(
                                    text: '\n$r',
                                    style: ChartKit.tooltipBody(context),
                                  ),
                              ],
                            ),
                      ];
                    }),
                  ),
                  titlesData: FlTitlesData(
                    topTitles: ChartKit.none,
                    rightTitles: ChartKit.none,
                    leftTitles:
                        ChartKit.valueAxis(context, currency: currency),
                    bottomTitles: ChartKit.labelAxis(
                        context, [for (final p in points) p.label],
                        width: plotWidth),
                  ),
                  lineBarsData: bars(k),
                  betweenBarsData: fills,
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: ChartLegend(
                entries: [for (final m in metrics) LegendEntry(m.$1, m.$2)],
                hidden: _hidden,
                onToggle: (i) => setState(() =>
                    _hidden.contains(i) ? _hidden.remove(i) : _hidden.add(i)),
              ),
            ),
            if (hasProjection)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CustomPaint(
                      size: const Size(18, 2),
                      painter: _DashPainter(t.textTertiary)),
                  const SizedBox(width: 6),
                  Text(
                      widget.projectionLabel ?? 'Projected at current pace',
                      style: TextStyle(fontSize: 12, color: t.textTertiary)),
                ],
              ),
            if (hasBand) ...[
              const SizedBox(width: AppSpacing.md),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 18,
                    height: 10,
                    decoration: BoxDecoration(
                      color: t.chartSeries[0].withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text('80% range',
                      style: TextStyle(fontSize: 12, color: t.textTertiary)),
                ],
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _DashPainter extends CustomPainter {
  const _DashPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = size.height;
    for (var x = 0.0; x < size.width; x += 7) {
      canvas.drawLine(Offset(x, size.height / 2),
          Offset(math.min(x + 4, size.width), size.height / 2), paint);
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}
