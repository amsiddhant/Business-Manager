import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_x.dart';
import '../../models/app_settings.dart';
import '../../widgets/common/status_badge.dart';

/// A small sample of the app drawn with the look being edited, in light and
/// dark side by side (stacked when there isn't room). Nothing in it is
/// interactive.
class ThemePreviewPane extends StatelessWidget {
  const ThemePreviewPane({super.key, required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final light = _PreviewSurface(settings: settings, brightness: Brightness.light);
      final dark = _PreviewSurface(settings: settings, brightness: Brightness.dark);
      if (c.maxWidth < 560) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [light, const SizedBox(height: AppSpacing.lg), dark],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: light),
          const SizedBox(width: AppSpacing.lg),
          Expanded(child: dark),
        ],
      );
    });
  }
}

class _PreviewSurface extends StatelessWidget {
  const _PreviewSurface({required this.settings, required this.brightness});

  final AppSettings settings;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.build(
      brand: settings.branding.brand,
      brightness: brightness,
      density: settings.theme.density,
      motion: settings.theme.motion,
      corners: settings.theme.corners,
      chartPalette: settings.theme.chartPalette,
    );
    final name = brightness == Brightness.dark ? 'Dark' : 'Light';
    return ExcludeSemantics(
      child: IgnorePointer(
        child: ExcludeFocus(
          child: Theme(
            data: theme,
            child: Builder(builder: (context) {
              final t = context.tokens;
              final shape = AppShape.of(context);
              return Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: t.background,
                  borderRadius: shape.md,
                  border: Border.all(color: t.border),
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('$name preview',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.6,
                              color: t.textTertiary)),
                      const SizedBox(height: AppSpacing.md),
                      const _KpiAndChart(),
                      const SizedBox(height: AppSpacing.md),
                      const _SampleTable(),
                      const SizedBox(height: AppSpacing.md),
                      const _SampleControls(),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: AppShape.of(context).md,
        border: Border.all(color: t.border),
      ),
      child: child,
    );
  }
}

class _KpiAndChart extends StatelessWidget {
  const _KpiAndChart();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final series = t.chartSeries;
    LineChartBarData line(List<double> ys, Color color) => LineChartBarData(
          spots: [for (var i = 0; i < ys.length; i++) FlSpot(i.toDouble(), ys[i])],
          isCurved: true,
          color: color,
          barWidth: 2.5,
          dotData: const FlDotData(show: false),
        );
    return _PreviewCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Revenue',
              style: TextStyle(fontSize: 12, color: t.textSecondary)),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('₹12.4L',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: t.textPrimary)),
              const SizedBox(width: AppSpacing.sm),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text('+8.2%',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: t.success)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: 80,
            child: LineChart(
              duration: Duration.zero,
              LineChartData(
                minY: 0,
                maxY: 10,
                gridData: const FlGridData(show: false),
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                lineTouchData: const LineTouchData(enabled: false),
                lineBarsData: [
                  line(const [2, 4, 3, 6, 5, 8, 7], series[0]),
                  line(const [1, 2, 2.5, 3, 4, 3.5, 5], series[1 % series.length]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SampleTable extends StatelessWidget {
  const _SampleTable();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final density = context.density;
    Widget row(String a, String b, Widget last, {bool header = false}) {
      final style = TextStyle(
        fontSize: header ? 11.5 : 13,
        fontWeight: header ? FontWeight.w600 : FontWeight.w500,
        color: header ? t.textTertiary : t.textPrimary,
      );
      return Container(
        height: density.rowHeight,
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: t.border)),
        ),
        child: Row(
          children: [
            Expanded(flex: 3, child: Text(a, style: style)),
            Expanded(flex: 2, child: Text(b, style: style)),
            Expanded(
                flex: 3,
                child: Align(alignment: Alignment.centerLeft, child: last)),
          ],
        ),
      );
    }

    return _PreviewCard(
      child: Column(
        children: [
          row(
              'Customer',
              'Amount',
              Text('Status',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: t.textTertiary)),
              header: true),
          row('Asha Traders', '₹18,400',
              const StatusBadge(label: 'Delivered', tone: BadgeTone.success)),
          row('Kiran Stores', '₹9,250',
              const StatusBadge(label: 'Pending', tone: BadgeTone.warning)),
          row('Meera & Co', '₹4,100',
              const StatusBadge(label: 'Shipped', tone: BadgeTone.info)),
        ],
      ),
    );
  }
}

class _SampleControls extends StatelessWidget {
  const _SampleControls();

  @override
  Widget build(BuildContext context) {
    return _PreviewCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const TextField(
            decoration: InputDecoration(
              labelText: 'Customer name',
              hintText: 'Type to search',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              ElevatedButton(onPressed: () {}, child: const Text('Primary')),
              OutlinedButton(onPressed: () {}, child: const Text('Secondary')),
              const StatusBadge(label: 'Active', tone: BadgeTone.primary),
            ],
          ),
        ],
      ),
    );
  }
}
