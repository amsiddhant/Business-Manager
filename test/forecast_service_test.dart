import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:salesforce_business_manager/services/smart/forecast_service.dart';
import 'package:salesforce_business_manager/services/smart/smart_config.dart';
import 'package:salesforce_business_manager/services/smart/smart_types.dart';

const _service = ForecastService();
final _first = DateTime(2023, 1, 1);

List<double> _seasonal(int n) => [
      for (var t = 0; t < n; t++)
        1000 + 10 * t + 200 * math.sin(2 * math.pi * (t % 12) / 12),
    ];

SmartSeriesForecast _engine({
  List<double> mean = const [1, 2, 3],
  List<double>? lower,
  List<double>? upper,
  double error = 0.1,
}) =>
    SmartSeriesForecast(
      mean: Float64List.fromList(mean),
      lower: Float64List.fromList(lower ?? [for (final m in mean) m - 1]),
      upper: Float64List.fromList(upper ?? [for (final m in mean) m + 1]),
      error: error,
    );

SeriesForecast _fc(double error) => SeriesForecast(
      mean: const [1],
      lower: const [1],
      upper: const [1],
      error: error,
      model: ForecastModel.linear,
      points: 10,
    );

void main() {
  group('forecast', () {
    test('a perfect line is continued exactly', () {
      final history = [for (var t = 0; t < 12; t++) 100.0 + 5 * t];
      final f = _service.forecast(history, firstMonth: _first, horizon: 4)!;
      expect(f.model, ForecastModel.linear);
      expect(f.points, 12);
      expect(f.horizon, 4);
      expect(f.error, closeTo(0, 1e-9));
      for (var k = 0; k < 4; k++) {
        expect(f.mean[k], closeTo(100 + 5 * (12 + k), 1e-9));
      }
    });

    test('picks seasonality on a seasonal series and beats linear', () {
      final f = _service.forecast(_seasonal(36), firstMonth: _first)!;
      expect(f.model, ForecastModel.seasonal);
      expect(f.horizon, SmartConfig.forecastHorizon);
      // The next 12 months follow the pattern, not a straight line.
      final expected = _seasonal(48).sublist(36);
      var diff = 0.0, total = 0.0;
      for (var i = 0; i < 12; i++) {
        diff += (f.mean[i] - expected[i]).abs();
        total += expected[i];
      }
      expect(diff / total, lessThan(0.05));
      // A straight line through this data misses the swings by far more.
      expect(f.error, lessThan(0.05));
      final line = [for (var t = 0; t < 12; t++) f.mean[0] + 10.0 * t];
      expect(ForecastService.weightedError(expected, line)!, greaterThan(diff / total));
    });

    test('fewer than six points gives nothing', () {
      expect(_service.forecast([1, 2, 3, 4, 5], firstMonth: _first), isNull);
      expect(_service.forecast(const [], firstMonth: _first), isNull);
    });

    test('an erratic series is hidden by the gate', () {
      final erratic = [
        for (var t = 0; t < 12; t++) t.isEven ? 10.0 : 1000.0,
      ];
      expect(_service.forecast(erratic, firstMonth: _first), isNull);
    });

    test('an all-zero history cannot be measured', () {
      expect(_service.forecast(List.filled(12, 0.0), firstMonth: _first),
          isNull);
    });

    test('the band widens with the horizon and brackets the mean', () {
      final noisy = [
        for (var t = 0; t < 18; t++) 1000.0 + 20 * t + (t % 3 - 1) * 15,
      ];
      final f = _service.forecast(noisy, firstMonth: _first)!;
      for (var k = 0; k < f.horizon; k++) {
        expect(f.lower[k], lessThanOrEqualTo(f.mean[k]));
        expect(f.upper[k], greaterThanOrEqualTo(f.mean[k]));
      }
      final w1 = f.upper[0] - f.lower[0];
      final w4 = f.upper[3] - f.lower[3];
      expect(w1, greaterThan(0));
      expect(w4, closeTo(w1 * 2, w1 * 1e-9)); // √4 = 2
      expect(f.upper[11] - f.lower[11], greaterThan(w4));
    });
  });

  group('better', () {
    test('takes the lower error and keeps the baseline on a tie', () {
      final a = _fc(0.2), b = _fc(0.1), c = _fc(0.2);
      expect(ForecastService.better(a, b), same(b));
      expect(ForecastService.better(b, a), same(b));
      expect(ForecastService.better(a, c), same(a));
    });

    test('handles missing sides', () {
      final a = _fc(0.2);
      expect(ForecastService.better(null, a), same(a));
      expect(ForecastService.better(a, null), same(a));
      expect(ForecastService.better(null, null), isNull);
    });
  });

  group('fromEngine', () {
    test('passes a good result through as the tfjs model', () {
      final f = _service.fromEngine(_engine(), points: 30)!;
      expect(f.model, ForecastModel.tfjs);
      expect(f.model.enhanced, isTrue);
      expect(f.points, 30);
      expect(f.mean, [1, 2, 3]);
    });

    test('gates on error and points', () {
      expect(_service.fromEngine(_engine(error: 0.5), points: 30), isNull);
      expect(_service.fromEngine(_engine(error: double.nan), points: 30),
          isNull);
      expect(
          _service.fromEngine(_engine(error: double.infinity), points: 30),
          isNull);
      expect(_service.fromEngine(_engine(), points: 5), isNull);
    });

    test('rejects malformed input', () {
      expect(
          _service.fromEngine(_engine(lower: const [1, 2]), points: 30),
          isNull);
      expect(
          _service.fromEngine(_engine(mean: const [1, double.nan, 3]),
              points: 30),
          isNull);
      expect(_service.fromEngine(_engine(mean: const []), points: 30), isNull);
    });

    test('fixes a band that does not bracket the mean', () {
      final f = _service.fromEngine(
          _engine(mean: const [10], lower: const [12], upper: const [8]),
          points: 30)!;
      expect(f.lower[0], lessThanOrEqualTo(10));
      expect(f.upper[0], greaterThanOrEqualTo(10));
    });
  });

  group('helpers', () {
    test('weightedError', () {
      expect(ForecastService.weightedError([100, 100], [90, 120]),
          closeTo(30 / 200, 1e-12));
      expect(ForecastService.weightedError([0, 0], [1, 1]), isNull);
    });

    test('calendarMonths wraps at the year end', () {
      expect(ForecastService.calendarMonths(DateTime(2025, 11, 1), 5),
          [11, 12, 1, 2, 3]);
    });
  });
}
