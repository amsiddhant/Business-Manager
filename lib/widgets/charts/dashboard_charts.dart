import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/enums.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../services/profit_calculation_service.dart';

/// Shared axis/label styling for the dashboard charts.
const _axisLabelStyle = TextStyle(
  color: AppColors.textTertiary,
  fontSize: 10.5,
  fontWeight: FontWeight.w500,
);

FlLine _gridLine(double _) =>
    const FlLine(color: AppColors.border, strokeWidth: 1);

/// A grouped bar chart comparing revenue, product cost, marketing, operating
/// expenses and net profit across time buckets.
class RevenueExpenseChart extends StatelessWidget {
  const RevenueExpenseChart({
    super.key,
    required this.points,
    required this.currency,
  });

  final List<TimeSeriesPoint> points;
  final CurrencyCode currency;

  @override
  Widget build(BuildContext context) {
    // Build one group per point, with rods for each component.
    final maxValue = points.fold<double>(1, (m, p) {
      final localMax = [
        p.revenue.major,
        p.productCost.major,
        p.marketingCost.major,
        p.operatingExpenses.major,
        p.netProfit.major,
      ].reduce((a, b) => a > b ? a : b);
      return localMax > m ? localMax : m;
    });

    return Column(
      children: [
        Expanded(
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: maxValue * 1.15,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: _gridLine,
              ),
              borderData: FlBorderData(show: false),
              barTouchData: BarTouchData(enabled: true),
              titlesData: FlTitlesData(
                show: true,
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 44,
                    getTitlesWidget: (value, meta) => SideTitleWidget(
                      meta: meta,
                      child: Text(
                        MoneyFormatter.compact(
                            Money.fromMajor(value), currency),
                        style: _axisLabelStyle,
                      ),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    getTitlesWidget: (value, meta) {
                      final i = value.toInt();
                      if (i < 0 || i >= points.length) {
                        return const SizedBox.shrink();
                      }
                      return SideTitleWidget(
                        meta: meta,
                        child: Text(points[i].label,
                            style: _axisLabelStyle),
                      );
                    },
                  ),
                ),
              ),
              barGroups: [
                for (var i = 0; i < points.length; i++)
                  BarChartGroupData(
                    x: i,
                    barsSpace: 2,
                    barRods: [
                      _rod(points[i].revenue, AppColors.chartSeries[0]),
                      _rod(points[i].productCost, AppColors.chartSeries[3]),
                      _rod(points[i].marketingCost, AppColors.chartSeries[6]),
                      _rod(points[i].operatingExpenses, AppColors.chartSeries[5]),
                      _rod(points[i].netProfit, AppColors.chartSeries[2]),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: 6,
          children: [
            _Legend(color: AppColors.chartSeries[0], label: 'Revenue'),
            _Legend(color: AppColors.chartSeries[3], label: 'Product Cost'),
            _Legend(color: AppColors.chartSeries[6], label: 'Marketing'),
            _Legend(color: AppColors.chartSeries[5], label: 'Operating'),
            _Legend(color: AppColors.chartSeries[2], label: 'Net Profit'),
          ],
        ),
      ],
    );
  }

  BarChartRodData _rod(Money value, Color color) => BarChartRodData(
        toY: value.major < 0 ? 0 : value.major,
        color: color,
        width: 7,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
      );
}

/// A donut chart for the expense breakdown.
class ExpenseDonutChart extends StatelessWidget {
  const ExpenseDonutChart({
    super.key,
    required this.slices,
    required this.currency,
  });

  final List<CategorySlice> slices;
  final CurrencyCode currency;

  @override
  Widget build(BuildContext context) {
    final total = slices.fold<double>(0, (s, e) => s + e.amount.major);
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 52,
              sections: [
                for (var i = 0; i < slices.length; i++)
                  PieChartSectionData(
                    value: slices[i].amount.major,
                    color: AppColors
                        .chartSeries[i % AppColors.chartSeries.length],
                    radius: 48,
                    title: total == 0
                        ? ''
                        : '${(slices[i].amount.major / total * 100).round()}%',
                    titleStyle: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.lg),
        Expanded(
          flex: 2,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < slices.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: AppColors.chartSeries[
                              i % AppColors.chartSeries.length],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(slices[i].label,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary)),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        MoneyFormatter.compact(slices[i].amount, currency),
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A vertical bar chart mapping a label to a single monetary value, used for
/// "Revenue by Product" and "Profit by Product".
class CategoryBarChart extends StatelessWidget {
  const CategoryBarChart({
    super.key,
    required this.labels,
    required this.values,
    required this.currency,
    this.color = AppColors.primary,
  });

  final List<String> labels;
  final List<Money> values;
  final CurrencyCode currency;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final maxValue = values.fold<double>(
        1, (m, v) => v.major > m ? v.major : m);
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxValue * 1.15,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: _gridLine,
        ),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(enabled: true),
        titlesData: FlTitlesData(
          show: true,
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              getTitlesWidget: (value, meta) => SideTitleWidget(
                meta: meta,
                child: Text(
                  MoneyFormatter.compact(Money.fromMajor(value), currency),
                  style: _axisLabelStyle,
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 34,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= labels.length) {
                  return const SizedBox.shrink();
                }
                final label = labels[i];
                final short =
                    label.length > 10 ? '${label.substring(0, 9)}…' : label;
                return SideTitleWidget(
                  meta: meta,
                  child: Text(short, style: _axisLabelStyle),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < values.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: values[i].major < 0 ? 0 : values[i].major,
                  color: color,
                  width: 18,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(4)),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// A single-series line chart used for orders trend and marketing spend.
class TrendLineChart extends StatelessWidget {
  const TrendLineChart({
    super.key,
    required this.labels,
    required this.values,
    this.color = AppColors.primary,
    this.currency,
  });

  final List<String> labels;

  /// Y values as plain doubles (orders count) — for money pass major units.
  final List<double> values;
  final Color color;

  /// When set, the left axis is formatted as money.
  final CurrencyCode? currency;

  @override
  Widget build(BuildContext context) {
    final maxValue =
        values.fold<double>(1, (m, v) => v > m ? v : m);
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxValue * 1.2,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: _gridLine,
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: true),
        titlesData: FlTitlesData(
          show: true,
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: currency != null ? 44 : 32,
              getTitlesWidget: (value, meta) => SideTitleWidget(
                meta: meta,
                child: Text(
                  currency != null
                      ? MoneyFormatter.compact(
                          Money.fromMajor(value), currency!)
                      : value.toInt().toString(),
                  style: _axisLabelStyle,
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= labels.length) {
                  return const SizedBox.shrink();
                }
                return SideTitleWidget(
                  meta: meta,
                  child: Text(labels[i], style: _axisLabelStyle),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < values.length; i++)
                FlSpot(i.toDouble(), values[i]),
            ],
            isCurved: true,
            color: color,
            barWidth: 3,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(
              show: true,
              color: color.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
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
