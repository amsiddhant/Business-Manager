import 'package:flutter_test/flutter_test.dart';
import 'package:salesforce_business_manager/core/enums.dart';
import 'package:salesforce_business_manager/core/utils/date_utils.dart';
import 'package:salesforce_business_manager/core/utils/money.dart';
import 'package:salesforce_business_manager/models/order.dart';
import 'package:salesforce_business_manager/services/profit_calculation_service.dart';
import 'package:salesforce_business_manager/services/smart/forecast_service.dart';

const _service = ProfitCalculationService();

Order _order(String id, DateTime date, int revenueMajor) => Order(
      id: id,
      businessId: 'BIZ-1',
      productId: 'PROD-1',
      productName: 'Widget',
      orderDate: date,
      sellingCost: Money.fromMajor(revenueMajor),
      status: OrderStatus.delivered,
    );

SeriesForecast _fc(List<double> mean,
        {double spread = 10, ForecastModel model = ForecastModel.linear}) =>
    SeriesForecast(
      mean: mean,
      lower: [for (final m in mean) m - spread],
      upper: [for (final m in mean) m + spread],
      error: 0.1,
      model: model,
      points: 12,
    );

ProfitSummary _summary(int revenueMajor) => ProfitSummary(
      revenue: Money.fromMajor(revenueMajor),
      productCost: Money.zero,
      marketingCost: Money.zero,
      operatingExpenses: Money.zero,
      orderCount: 1,
      unitsSold: 1,
    );

void main() {
  // Today: 15 Oct 2026. Forecast months start Oct 2026.
  final asOf = DateTime(2026, 10, 15, 14);
  final first = DateTime(2026, 10, 1);

  group('forecastHistory', () {
    final orders = [
      _order('1', DateTime(2026, 3, 10), 100),
      _order('2', DateTime(2026, 4, 10), 200),
      _order('3', DateTime(2026, 9, 10), 300),
      _order('4', DateTime(2026, 10, 3), 999), // current month
    ];

    test('trims leading empty months and excludes the current month', () {
      final h = _service.forecastHistory(
          orders: orders,
          campaigns: const [],
          expenses: const [],
          asOf: asOf,
          months: 12);
      expect(h.first.label, 'Mar 2026');
      expect(h.last.label, 'Sep 2026');
      expect(h.length, 7);
      expect(h.first.revenue, Money.fromMajor(100));
      expect(h.any((p) => p.label == 'Oct 2026'), isFalse);
    });

    test('no activity gives an empty history', () {
      expect(
          _service.forecastHistory(
              orders: const [],
              campaigns: const [],
              expenses: const [],
              asOf: asOf),
          isEmpty);
    });

    test('is limited to the months asked for', () {
      final h = _service.forecastHistory(
          orders: orders,
          campaigns: const [],
          expenses: const [],
          asOf: asOf,
          months: 3);
      // Jul and Aug are before the first activity, so they are trimmed.
      expect(h.map((p) => p.label), ['Sep 2026']);
    });
  });

  group('projectPeriodEnd', () {
    final revenue = _fc([3100, 2800, 3000, 3100], spread: 100);
    final net = _fc([310, 280, 300, 310], spread: 10);

    PeriodProjection? project(DateRange range,
            {int minDays = 1,
            SeriesForecast? rev,
            SeriesForecast? np,
            DateTime? now}) =>
        _service.projectPeriodEnd(
          toDate: _summary(1000),
          range: range,
          asOf: now ?? asOf,
          firstForecastMonth: first,
          revenue: rev ?? revenue,
          netProfit: np ?? net,
          minDays: minDays,
        );

    test('a running month adds the rest of the month', () {
      final p = project(DateRange(DateTime(2026, 10, 1), DateTime(2026, 10, 31)))!;
      // 16 of 31 days left of a 3100 month.
      expect(p.revenue, Money.fromMajor(1000 + 3100 * 16 / 31));
      expect(p.netProfit, Money.fromMajor(1000 + 310 * 16 / 31));
      expect(p.source, ProjectionSource.forecast);
      expect(p.elapsedDays, 15);
      expect(p.totalDays, 31);
      expect(p.revenuePerDay, Money.fromMajor(3100 * 16 / 31) / 16);
      expect(p.enhanced, isFalse);
    });

    test('a running quarter spans the forecast months', () {
      final p = project(DateRange(DateTime(2026, 10, 1), DateTime(2026, 12, 31)))!;
      final extra = 3100 * 16 / 31 + 2800 + 3000;
      expect(p.revenue.minor, Money.fromMajor(1000 + extra).minor);
      expect(p.totalDays, 92);
      expect(p.revenueLow! < p.revenue, isTrue);
      expect(p.revenueHigh! > p.revenue, isTrue);
      expect(p.netProfitLow! < p.netProfit, isTrue);
      expect(p.netProfitHigh! > p.netProfit, isTrue);
      // The band is the sum of the months' bands: 100 × (16/31 + 2).
      expect(p.revenueHigh!.minor - p.revenue.minor,
          Money.fromMajor(100 * (16 / 31 + 2)).minor);
    });

    test('is enhanced when either forecast is', () {
      final p = project(
          DateRange(DateTime(2026, 10, 1), DateTime(2026, 10, 31)),
          np: _fc([1, 1, 1, 1], model: ForecastModel.tfjs))!;
      expect(p.enhanced, isTrue);
    });

    test('is null past the forecast horizon', () {
      expect(project(DateRange(DateTime(2026, 10, 1), DateTime(2027, 3, 31))),
          isNull);
    });

    test('is null when the period is not running', () {
      expect(project(DateRange(DateTime(2026, 11, 1), DateTime(2026, 11, 30))),
          isNull);
      expect(project(DateRange(DateTime(2026, 9, 1), DateTime(2026, 9, 30))),
          isNull);
      // On its last day there is nothing left to project.
      expect(
          project(DateRange(DateTime(2026, 10, 1), DateTime(2026, 10, 15))),
          isNull);
    });

    test('is null before minDays', () {
      final range = DateRange(DateTime(2026, 10, 1), DateTime(2026, 10, 31));
      expect(project(range, minDays: 16), isNull);
      expect(project(range, minDays: 15), isNotNull);
    });

    test('a period that starts mid-month is spread by days in the month', () {
      final p = project(
          DateRange(DateTime(2026, 10, 10), DateTime(2026, 11, 9)))!;
      expect(p.revenue.minor,
          Money.fromMajor(1000 + 3100 * 16 / 31 + 2800 * 9 / 30).minor);
    });
  });

  group('forecastSeries', () {
    final history = _service.forecastHistory(
      orders: [
        for (var m = 1; m <= 9; m++) _order('$m', DateTime(2026, m, 10), 100 * m),
      ],
      campaigns: const [],
      expenses: const [],
      asOf: asOf,
    );

    test('actuals then forecast months with bands', () {
      final points = _service.forecastSeries(
        history: history,
        firstForecastMonth: first,
        revenue: _fc([500, 600, 700, 800], spread: 50),
        netProfit: _fc([50, 60, 70, 80], spread: 5),
        historyMonths: 4,
      );
      expect(points.length, 4 + 3);
      expect(points.first.label, 'Jun 2026');
      expect(points[3].label, 'Sep 2026');
      expect(points[3].revenue, Money.fromMajor(900));
      expect(points[3].projectedRevenue, isNull);
      expect(points[4].label, 'Oct 2026');
      expect(points[4].revenue, isNull);
      expect(points[4].projectedRevenue, Money.fromMajor(500));
      expect(points[4].projectedRevenueLow, Money.fromMajor(450));
      expect(points[4].projectedRevenueHigh, Money.fromMajor(550));
      expect(points[4].projectedNetProfit, Money.fromMajor(50));
      expect(points[6].label, 'Dec 2026');
    });

    test('net profit fields stay empty without a net profit forecast', () {
      final points = _service.forecastSeries(
        history: history,
        firstForecastMonth: first,
        revenue: _fc([500, 600, 700]),
        months: 2,
      );
      expect(points.length, 9 + 2);
      expect(points.last.projectedRevenue, Money.fromMajor(600));
      expect(points.last.projectedNetProfit, isNull);
      expect(points.last.projectedNetProfitLow, isNull);
      expect(points.last.projectedNetProfitHigh, isNull);
    });

    test('labels match the month series labels', () {
      final points = _service.forecastSeries(
        history: history,
        firstForecastMonth: DateTime(2026, 11, 1),
        revenue: _fc([1, 2, 3]),
      );
      expect(points[history.length].label,
          AppDate.monthYear(DateTime(2026, 11, 1)));
      expect(points.last.label, 'Jan 2027');
    });
  });
}
