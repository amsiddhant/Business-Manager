import 'package:flutter/material.dart';

import '../../../core/enums.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_x.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/money.dart';
import '../../../services/smart/forecast_service.dart';
import '../../../services/smart/smart_config.dart';
import '../../../state/smart_insights_controller.dart';
import '../../../widgets/charts/chart_card.dart';
import '../../../widgets/charts/chart_kit.dart';
import '../../../widgets/common/status_badge.dart';

/// Why [ForecastCard] has nothing to show.
enum ForecastGap {
  /// Fewer than [SmartConfig.forecastMinPoints] complete months.
  shortHistory,

  /// Enough history, but past months were too uneven to forecast reliably.
  tooUneven,

  /// All Businesses, and the businesses bill in different currencies.
  mixedCurrencies,
}

/// "Next 3 months": the likely revenue and net profit for each month, with
/// a range, the model behind it and how close it has been. Worked out on
/// this device from the user's own months.
class ForecastCard extends StatelessWidget {
  const ForecastCard({
    super.key,
    required this.currency,
    this.forecast,
    this.gap,
    this.historyMonths = 0,
  });

  final CurrencyCode currency;

  /// Null shows the empty state for [gap].
  final SmartForecast? forecast;
  final ForecastGap? gap;

  /// Complete months of history, for the "you have N" line.
  final int historyMonths;

  static const _months = SmartConfig.chartHorizon;

  /// The empty-state sentence for [gap].
  static String gapMessage(ForecastGap gap, int historyMonths) => switch (gap) {
        ForecastGap.shortHistory =>
          'Forecasts appear after ${SmartConfig.forecastMinPoints} months of '
              'history. You have $historyMonths so far.',
        ForecastGap.tooUneven =>
          'Forecast hidden: past months were too uneven to forecast '
              'reliably. It returns when the pattern settles.',
        ForecastGap.mixedCurrencies =>
          'These businesses bill in different currencies, so their forecasts '
              'can\'t be added up. Pick one business to see its forecast.',
      };

  String _money(Money m) => MoneyFormatter.compact(m, currency);

  /// How many of the next months both series (or the one there is) cover.
  int _count(SmartForecast f) {
    final horizons = [
      ?f.revenue?.horizon,
      ?f.netProfit?.horizon,
    ];
    if (horizons.isEmpty) return 0;
    return horizons.reduce((a, b) => a < b ? a : b).clamp(0, _months);
  }

  String _monthLabel(SmartForecast f, int i) => AppDate.monthYear(
      DateTime(f.firstMonth.year, f.firstMonth.month + i, 1));

  String _range(SeriesForecast s, int i) =>
      '${_money(Money.fromMajor(s.lower[i]))} to '
      '${_money(Money.fromMajor(s.upper[i]))}';

  String _within(SeriesForecast s) => '±${(s.error * 100).round()}%';

  /// "Past months were typically within ±12% for revenue and ±18% for net
  /// profit."
  String accuracyLine(SmartForecast f) {
    final r = f.revenue, n = f.netProfit;
    if (r != null && n != null) {
      return 'Past months were typically within ${_within(r)} for revenue '
          'and ${_within(n)} for net profit.';
    }
    final one = r ?? n;
    if (one == null) return '';
    return 'Past months were typically within ${_within(one)} for '
        '${r != null ? 'revenue' : 'net profit'}.';
  }

  String _modelLine(SmartForecast f) {
    final r = f.revenue?.model, n = f.netProfit?.model;
    if (r != null && n != null && r != n) {
      return 'Method: ${r.label} (revenue), ${n.label} (net profit)';
    }
    return 'Method: ${(r ?? n)?.label ?? '—'}';
  }

  ChartTableData _table(SmartForecast f) {
    final r = f.revenue, n = f.netProfit;
    return ChartTableData(
      headers: [
        'Month',
        if (r != null) ...['Revenue', 'Revenue range (80%)'],
        if (n != null) ...['Net profit', 'Net profit range (80%)'],
      ],
      rows: [
        for (var i = 0; i < _count(f); i++)
          [
            _monthLabel(f, i),
            if (r != null) ...[
              MoneyFormatter.format(Money.fromMajor(r.mean[i]), currency),
              _range(r, i),
            ],
            if (n != null) ...[
              MoneyFormatter.format(Money.fromMajor(n.mean[i]), currency),
              _range(n, i),
            ],
          ],
      ],
    );
  }

  void _explain(BuildContext context, SmartForecast f) {
    final first = f.history.isEmpty ? null : f.history.first.label;
    final last = f.history.isEmpty ? null : f.history.last.label;
    final built = first == null
        ? 'It is built from your own completed months.'
        : 'It is built from your ${f.history.length} completed months, '
            '$first to $last, of revenue and net profit.';
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('How is this calculated?'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(built),
              const SizedBox(height: AppSpacing.md),
              Text('${_modelLine(f)}. Each month is the usual level and '
                  'direction of your past months'
                  '${f.revenue?.model == ForecastModel.seasonal || f.netProfit?.model == ForecastModel.seasonal ? ', allowing for the time of year' : ''}.'),
              const SizedBox(height: AppSpacing.md),
              const Text('The range is where about 8 in 10 outcomes are '
                  'likely to land (80%). It widens the further ahead you '
                  'look.'),
              const SizedBox(height: AppSpacing.md),
              const Text('A forecast is hidden when there are fewer than '
                  '${SmartConfig.forecastMinPoints} months of history or '
                  'when past months were too uneven to forecast reliably.'),
              if (f.enhanced) ...[
                const SizedBox(height: AppSpacing.md),
                const Text('Enhanced: a small neural model on this device '
                    'did better than the built-in method on your past '
                    'months, so it was used.'),
              ],
              const SizedBox(height: AppSpacing.md),
              const Text('It is worked out on this device. Nothing is sent '
                  'anywhere.'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final f = forecast;
    final empty = f == null || f.revenue == null && f.netProfit == null;
    const title = 'Next 3 months';
    const icon = Icons.insights_outlined;

    if (empty) {
      final why = gap ?? ForecastGap.shortHistory;
      return ChartCard(
        icon: icon,
        title: title,
        subtitle: 'Likely revenue and net profit',
        height: 150,
        child: _Notice(text: gapMessage(why, historyMonths)),
      );
    }

    final t = context.tokens;
    final count = _count(f);
    final r = f.revenue, n = f.netProfit;
    final rows = [
      for (var i = 0; i < count; i++)
        _MonthRow(
          label: _monthLabel(f, i),
          revenue: r == null ? null : _money(Money.fromMajor(r.mean[i])),
          revenueRange: r == null ? null : _range(r, i),
          netProfit: n == null ? null : _money(Money.fromMajor(n.mean[i])),
          netProfitRange: n == null ? null : _range(n, i),
          loss: n != null && n.mean[i] < 0,
        ),
    ];

    return ChartCard(
      icon: icon,
      title: title,
      subtitle: 'Likely revenue and net profit, with a range',
      height: 120.0 + 64 * count,
      table: _table(f),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (f.enhanced)
            const Padding(
              padding: EdgeInsets.only(right: AppSpacing.sm),
              child: StatusBadge(label: 'Enhanced', tone: BadgeTone.primary),
            ),
          IconButton(
            tooltip: 'How is this calculated?',
            visualDensity: VisualDensity.compact,
            onPressed: () => _explain(context, f),
            icon: Icon(Icons.help_outline, size: 18, color: t.textSecondary),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HeaderRow(revenue: r != null, netProfit: n != null),
          for (final row in rows) row,
          const Spacer(),
          Text(accuracyLine(f),
              style: TextStyle(fontSize: 12.5, color: t.textSecondary)),
          const SizedBox(height: 2),
          Text(_modelLine(f),
              style: TextStyle(fontSize: 12, color: t.textTertiary)),
          if (r == null || n == null) ...[
            const SizedBox(height: 2),
            Text(
                r == null
                    ? 'Revenue isn\'t shown: past months were too uneven to '
                        'forecast it reliably.'
                    : 'Net profit isn\'t shown: past months were too uneven '
                        'to forecast it reliably.',
                style: TextStyle(fontSize: 12, color: t.textTertiary)),
          ],
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.info_outline, size: 18, color: t.textTertiary),
          const SizedBox(width: AppSpacing.md),
          Flexible(
            child: Text(text,
                style: TextStyle(fontSize: 13.5, color: t.textSecondary)),
          ),
        ],
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.revenue, required this.netProfit});
  final bool revenue, netProfit;

  @override
  Widget build(BuildContext context) {
    final style =
        TextStyle(fontSize: 12, color: context.tokens.textTertiary);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          SizedBox(width: 72, child: Text('Month', style: style)),
          if (revenue) Expanded(child: Text('Revenue', style: style)),
          if (netProfit) Expanded(child: Text('Net profit', style: style)),
        ],
      ),
    );
  }
}

class _MonthRow extends StatelessWidget {
  const _MonthRow({
    required this.label,
    required this.revenue,
    required this.revenueRange,
    required this.netProfit,
    required this.netProfitRange,
    required this.loss,
  });

  final String label;
  final String? revenue, revenueRange, netProfit, netProfitRange;
  final bool loss;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    Widget cell(String? value, String? range, {Color? color}) => Expanded(
          child: value == null
              ? const SizedBox.shrink()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(value,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: color ?? t.textPrimary,
                            fontFeatures: const [
                              FontFeature.tabularFigures()
                            ])),
                    Text(range ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12, color: t.textTertiary)),
                  ],
                ),
        );
    return Container(
      height: 64,
      decoration:
          BoxDecoration(border: Border(top: BorderSide(color: t.border))),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 72,
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: t.textSecondary)),
          ),
          cell(revenue, revenueRange),
          cell(netProfit, netProfitRange, color: loss ? t.error : null),
        ],
      ),
    );
  }
}
