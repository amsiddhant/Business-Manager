import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/enums.dart';
import '../../core/theme/theme_x.dart';
import '../../core/utils/money.dart';

/// The shared look of every chart: axes, grid, tooltips and the first-time
/// draw-in. Charts build their fl_chart data with these so they all match.
class ChartKit {
  const ChartKit._();

  static TextStyle axisLabel(BuildContext context) => TextStyle(
        color: context.tokens.textTertiary,
        fontSize: 11,
        fontWeight: FontWeight.w500,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// Faint dashed horizontal lines only.
  static FlGridData grid(BuildContext context, {double? interval}) {
    final color = context.tokens.border;
    return FlGridData(
      show: true,
      drawVerticalLine: false,
      horizontalInterval: interval,
      getDrawingHorizontalLine: (_) =>
          FlLine(color: color, strokeWidth: 1, dashArray: const [4, 4]),
    );
  }

  static const AxisTitles none =
      AxisTitles(sideTitles: SideTitles(showTitles: false));

  /// A left axis of compact amounts (₹12.3L) — or plain counts when
  /// [currency] is null.
  static AxisTitles valueAxis(BuildContext context,
      {CurrencyCode? currency, double? interval}) {
    final style = axisLabel(context);
    return AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: currency == null ? 34 : 52,
        interval: interval,
        getTitlesWidget: (value, meta) {
          if (value == meta.max && meta.max != meta.min) {
            return const SizedBox.shrink(); // The padded top looks odd.
          }
          return SideTitleWidget(
            meta: meta,
            child: Text(
                currency == null
                    ? _count(value)
                    : MoneyFormatter.compact(Money.fromMajor(value), currency),
                style: style),
          );
        },
      ),
    );
  }

  /// A bottom axis of [labels], thinned so they never overlap in [width].
  static AxisTitles labelAxis(BuildContext context, List<String> labels,
      {required double width, double minGap = 64, int maxChars = 10}) {
    final style = axisLabel(context);
    final fit = math.max(1, (width / minGap).floor());
    final step = math.max(1, (labels.length / fit).ceil());
    return AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 28,
        interval: 1,
        getTitlesWidget: (value, meta) {
          final i = value.round();
          if (value != i || i < 0 || i >= labels.length || i % step != 0) {
            return const SizedBox.shrink();
          }
          return SideTitleWidget(
            meta: meta,
            child: Text(ellipsize(labels[i], maxChars), style: style),
          );
        },
      ),
    );
  }

  /// A rounded-up axis maximum with headroom, so the top bar never touches
  /// the edge and grid lines land on round numbers.
  static double niceMax(double max) {
    if (max <= 0) return 1;
    final padded = max * 1.12;
    final magnitude =
        math.pow(10, (math.log(padded) / math.ln10).floor()).toDouble();
    for (final f in const [1.0, 1.5, 2.0, 2.5, 3.0, 4.0, 5.0, 6.0, 8.0, 10.0]) {
      if (f * magnitude >= padded) return f * magnitude;
    }
    return 10 * magnitude;
  }

  /// The tooltip box: the theme's inverse surface, so it stands out on both
  /// light and dark cards.
  static Color tooltipColor(BuildContext context) =>
      context.tokens.inverseSurface;

  static TextStyle tooltipTitle(BuildContext context) => TextStyle(
        color: context.tokens.onInverseSurface,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      );

  static TextStyle tooltipBody(BuildContext context, {Color? color}) =>
      TextStyle(
        color: color ?? context.tokens.onInverseSurface,
        fontSize: 12,
        fontWeight: FontWeight.w500,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  static BarTouchTooltipData barTooltip(BuildContext context,
          {required GetBarTooltipItem item}) =>
      BarTouchTooltipData(
        getTooltipColor: (_) => tooltipColor(context),
        tooltipBorderRadius: BorderRadius.circular(8),
        tooltipPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        maxContentWidth: 200,
        fitInsideHorizontally: true,
        fitInsideVertically: true,
        getTooltipItem: item,
      );

  static LineTouchTooltipData lineTooltip(BuildContext context,
          {required GetLineTooltipItems items}) =>
      LineTouchTooltipData(
        getTooltipColor: (_) => tooltipColor(context),
        tooltipBorderRadius: BorderRadius.circular(8),
        tooltipPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        maxContentWidth: 220,
        fitInsideHorizontally: true,
        fitInsideVertically: true,
        getTooltipItems: items,
      );

  /// A vertical bar fill: the colour at the top fading slightly downwards.
  static LinearGradient barGradient(Color color, {bool down = false}) =>
      LinearGradient(
        begin: down ? Alignment.bottomCenter : Alignment.topCenter,
        end: down ? Alignment.topCenter : Alignment.bottomCenter,
        colors: [color, color.withValues(alpha: 0.62)],
      );

  /// The soft fill under a line.
  static BarAreaData areaUnder(Color color, {double alpha = 0.22}) =>
      BarAreaData(
        show: true,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: alpha),
            color.withValues(alpha: 0),
          ],
        ),
      );

  static String ellipsize(String text, int max) =>
      text.length > max ? '${text.substring(0, max - 1)}…' : text;

  static String _count(double v) {
    if (v.abs() >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v.abs() >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    return v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
  }
}

/// Grows a chart in from zero the first time [id] is shown this session —
/// [builder] gets the progress (0 → 1) to scale its values by. Later visits,
/// and reduced or no motion, draw it complete straight away.
class ChartReveal extends StatelessWidget {
  const ChartReveal({super.key, required this.id, required this.builder});

  final String id;
  final Widget Function(BuildContext context, double progress) builder;

  static final Set<String> _shown = {};

  /// For tests.
  @visibleForTesting
  static void reset() => _shown.clear();

  @override
  Widget build(BuildContext context) {
    final motion = context.motion;
    final first = _shown.add(id);
    if (!first || !motion.allowsMovement) return builder(context, 1);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: motion.chart,
      curve: AppMotion.emphasized,
      builder: (context, t, _) => builder(context, t),
    );
  }
}

/// One entry of a [ChartLegend].
class LegendEntry {
  const LegendEntry(this.label, this.color, {this.value});
  final String label;
  final Color color;

  /// An optional figure shown after the label.
  final String? value;
}

/// A row of legend chips. With [onToggle], each chip shows or hides its
/// series; [hidden] holds the hidden indexes.
class ChartLegend extends StatelessWidget {
  const ChartLegend({
    super.key,
    required this.entries,
    this.hidden = const {},
    this.onToggle,
  });

  final List<LegendEntry> entries;
  final Set<int> hidden;
  final ValueChanged<int>? onToggle;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (var i = 0; i < entries.length; i++)
          _chip(context, t, i, entries[i], hidden.contains(i)),
      ],
    );
  }

  Widget _chip(BuildContext context, AppTokens t, int i, LegendEntry e,
      bool off) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: context.motion.fast,
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: off ? t.surfaceAlt : e.color,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: off ? t.borderStrong : e.color),
            ),
          ),
          const SizedBox(width: 6),
          Text(e.label,
              style: TextStyle(
                fontSize: 12,
                color: off ? t.textTertiary : t.textSecondary,
                decoration: off ? TextDecoration.lineThrough : null,
              )),
          if (e.value != null) ...[
            const SizedBox(width: 6),
            Text(e.value!,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: off ? t.textTertiary : t.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                )),
          ],
        ],
      ),
    );
    if (onToggle == null) return content;
    final visible = entries.length - hidden.length;
    return Semantics(
      button: true,
      toggled: !off,
      label: '${e.label} series',
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        // Keep at least one series on screen.
        onTap: !off && visible <= 1 ? null : () => onToggle!(i),
        child: content,
      ),
    );
  }
}

/// A chart's figures as a plain table — the "View as table" side of a
/// `ChartCard`. The first column is the label; the rest are right-aligned.
class ChartTableData {
  const ChartTableData({required this.headers, required this.rows});
  final List<String> headers;
  final List<List<String>> rows;
}

class ChartTable extends StatelessWidget {
  const ChartTable({super.key, required this.data});
  final ChartTableData data;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final head = TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        color: t.textTertiary,
        letterSpacing: 0.3);
    final body = TextStyle(
        fontSize: 12.5,
        color: t.textPrimary,
        fontFeatures: const [FontFeature.tabularFigures()]);

    Widget row(List<String> cells, TextStyle style, {Color? bg}) => Container(
          color: bg,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            children: [
              for (var i = 0; i < cells.length; i++)
                Expanded(
                  flex: i == 0 ? 3 : 2,
                  child: Text(cells[i],
                      textAlign: i == 0 ? TextAlign.start : TextAlign.end,
                      overflow: TextOverflow.ellipsis,
                      style: i == 0 && style == body
                          ? body.copyWith(fontWeight: FontWeight.w600)
                          : style),
                ),
            ],
          ),
        );

    return Column(
      children: [
        row(data.headers, head, bg: t.surfaceAlt),
        Expanded(
          child: data.rows.isEmpty
              ? Center(
                  child: Text('No figures',
                      style: TextStyle(color: t.textTertiary)))
              : ListView.separated(
                  itemCount: data.rows.length,
                  separatorBuilder: (_, _) =>
                      Divider(height: 1, color: t.border),
                  itemBuilder: (_, i) => row(data.rows[i], body),
                ),
        ),
      ],
    );
  }
}
