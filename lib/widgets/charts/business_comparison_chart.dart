import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/enums.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_x.dart';
import '../../core/utils/money.dart';
import '../../services/profit_calculation_service.dart';
import 'chart_kit.dart';
import 'dashboard_charts.dart';

/// Revenue, total costs and net profit side by side for each business.
class BusinessComparisonChart extends StatefulWidget {
  const BusinessComparisonChart({
    super.key,
    required this.rows,
    required this.currency,
  });

  final List<BusinessSummary> rows;
  final CurrencyCode currency;

  @override
  State<BusinessComparisonChart> createState() =>
      _BusinessComparisonChartState();
}

class _BusinessComparisonChartState extends State<BusinessComparisonChart> {
  final Set<int> _hidden = {};

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final rows = widget.rows;
    final currency = widget.currency;
    final series = <(String, Color, Money Function(ProfitSummary))>[
      ('Revenue', t.chartSeries[0], (s) => s.revenue),
      ('Costs', t.chartSeries[3], (s) => s.totalExpenses),
      ('Net Profit', t.chartSeries[2], (s) => s.netProfit),
    ];
    final visible = [
      for (var i = 0; i < series.length; i++)
        if (!_hidden.contains(i)) i,
    ];
    var maxV = 0.0, minV = 0.0;
    for (final r in rows) {
      for (final i in visible) {
        final v = series[i].$3(r.summary).major;
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
            final rodWidth = (plotWidth /
                    math.max(1, rows.length) *
                    0.6 /
                    math.max(1, visible.length))
                .clamp(6.0, 22.0);
            return ChartReveal(
              id: 'business-comparison',
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
                      final r = rows[group.x];
                      return BarTooltipItem(
                        r.business.name,
                        ChartKit.tooltipTitle(context),
                        textAlign: TextAlign.start,
                        children: [
                          for (final i in visible) ...[
                            TextSpan(
                                text: '\n● ',
                                style: TextStyle(color: series[i].$2)),
                            TextSpan(
                                text: '${series[i].$1}  '
                                    '${MoneyFormatter.format(series[i].$3(r.summary), currency)}',
                                style: ChartKit.tooltipBody(context)),
                          ],
                          TextSpan(
                              text: '\nNet margin '
                                  '${PercentFormatter.format(r.summary.netMargin)}',
                              style: ChartKit.tooltipBody(context)),
                        ],
                      );
                    }),
                  ),
                  titlesData: FlTitlesData(
                    topTitles: ChartKit.none,
                    rightTitles: ChartKit.none,
                    leftTitles:
                        ChartKit.valueAxis(context, currency: currency),
                    bottomTitles: ChartKit.labelAxis(
                        context, [for (final r in rows) r.business.name],
                        width: plotWidth, minGap: 72, maxChars: 12),
                  ),
                  barGroups: [
                    for (var g = 0; g < rows.length; g++)
                      BarChartGroupData(
                        x: g,
                        barsSpace: 3,
                        barRods: [
                          for (final i in visible)
                            moneyRod(series[i].$3(rows[g].summary).major * k,
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
