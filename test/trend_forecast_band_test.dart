import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salesforce_business_manager/core/enums.dart';
import 'package:salesforce_business_manager/core/utils/money.dart';
import 'package:salesforce_business_manager/services/profit_calculation_service.dart';
import 'package:salesforce_business_manager/widgets/charts/chart_kit.dart';
import 'package:salesforce_business_manager/widgets/charts/trend_forecast_chart.dart';

Money _m(int major) => Money.fromMajor(major.toDouble());

/// Three actual months, then two projected ones; [band] adds the 80% range.
List<ForecastPoint> _points({required bool band}) => [
      for (final (i, l) in ['Jan 26', 'Feb 26', 'Mar 26'].indexed)
        ForecastPoint(
            label: l,
            revenue: _m(100000 + i * 10000),
            netProfit: _m(20000 + i * 2000)),
      ForecastPoint(
        label: 'Apr 26',
        projectedRevenue: _m(125000),
        projectedNetProfit: _m(26000),
        projectedRevenueLow: band ? _m(110000) : null,
        projectedRevenueHigh: band ? _m(140000) : null,
        projectedNetProfitLow: band ? _m(22000) : null,
        projectedNetProfitHigh: band ? _m(30000) : null,
      ),
      ForecastPoint(
        label: 'May 26',
        projectedRevenue: _m(130000),
        projectedNetProfit: _m(27000),
        projectedRevenueLow: band ? _m(105000) : null,
        projectedRevenueHigh: band ? _m(155000) : null,
        projectedNetProfitLow: band ? _m(21000) : null,
        projectedNetProfitHigh: band ? _m(33000) : null,
      ),
    ];

Future<void> _pump(WidgetTester tester, List<ForecastPoint> points) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 700,
        height: 360,
        child: TrendForecastChart(points: points, currency: CurrencyCode.inr),
      ),
    ),
  ));
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 500));
  }
}

void main() {
  setUp(ChartReveal.reset);

  testWidgets('with a range: the 80% legend item and a fill between lines',
      (tester) async {
    await _pump(tester, _points(band: true));
    expect(tester.takeException(), isNull);
    expect(find.text('80% range'), findsOneWidget);

    final chart = tester.widget<LineChart>(find.byType(LineChart));
    final data = chart.data;
    // Revenue and net profit: each a line, its projection, and two edges.
    expect(data.lineBarsData, hasLength(8));
    expect(data.betweenBarsData, hasLength(2));
    for (final b in data.betweenBarsData) {
      expect(data.lineBarsData[b.fromIndex].color, Colors.transparent);
      expect(data.lineBarsData[b.toIndex].color, Colors.transparent);
    }
  });

  testWidgets('without a range: exactly as before', (tester) async {
    await _pump(tester, _points(band: false));
    expect(tester.takeException(), isNull);
    expect(find.text('80% range'), findsNothing);
    expect(find.text('Projected at current pace'), findsOneWidget);

    final data = tester.widget<LineChart>(find.byType(LineChart)).data;
    expect(data.lineBarsData, hasLength(4));
    expect(data.betweenBarsData, isEmpty);
  });

  testWidgets('a custom projection label replaces the default',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 700,
          height: 360,
          child: TrendForecastChart(
            points: _points(band: true),
            currency: CurrencyCode.inr,
            projectionLabel: 'Projected · on-device',
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Projected · on-device'), findsOneWidget);
    expect(find.text('Projected at current pace'), findsNothing);
  });

  group('table', () {
    test('shows each projected range', () {
      final t = TrendForecastChart.tableOf(
          _points(band: true), CurrencyCode.inr);
      expect(t.headers,
          containsAll(['Revenue range (80%)', 'Net profit range (80%)']));
      final apr = t.rows.firstWhere((r) => r.first == 'Apr 26');
      final col = t.headers.indexOf('Revenue range (80%)');
      expect(apr[col], contains(' to '));
      expect(apr[col], contains('1.1')); // ₹1.1L low end, compact
      // Past months have no range.
      expect(t.rows.first[col], '—');
    });

    test('has no range columns without a range', () {
      final t = TrendForecastChart.tableOf(
          _points(band: false), CurrencyCode.inr);
      expect(t.headers, [
        'Period',
        'Revenue',
        'Net Profit',
        'Projected revenue',
        'Projected net profit',
      ]);
      expect(t.rows.every((r) => r.length == 5), isTrue);
    });

    test('projections: false drops the projected columns', () {
      final t = TrendForecastChart.tableOf(
          _points(band: true), CurrencyCode.inr,
          projections: false);
      expect(t.headers, ['Period', 'Revenue', 'Net Profit']);
    });
  });
}
