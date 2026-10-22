import 'dart:math' as math;

import 'smart_config.dart';
import 'smart_types.dart';

/// Which model produced a forecast.
enum ForecastModel {
  linear('Linear trend'),
  seasonal('Trend and seasonality'),
  tfjs('On-device neural model');

  const ForecastModel(this.label);
  final String label;

  bool get enhanced => this == ForecastModel.tfjs;
}

/// A monthly forecast: one value per month from the current month on, with
/// a ±80% band that widens with the horizon. Values are in the series' units
/// (major currency units for money).
class SeriesForecast {
  const SeriesForecast({
    required this.mean,
    required this.lower,
    required this.upper,
    required this.error,
    required this.model,
    required this.points,
  });

  final List<double> mean;
  final List<double> lower;
  final List<double> upper;

  /// Backtest error on the held-out months, weighted MAPE (0.12 = 12%).
  final double error;
  final ForecastModel model;

  /// Months of history it was built from.
  final int points;

  int get horizon => mean.length;
}

/// A fitted model: its fitted one-step residuals and a way to extend it.
class _Fit {
  _Fit(this.residuals, this._ahead);

  /// In-sample one-step errors (actual − fitted).
  final List<double> residuals;
  final double Function(int step) _ahead;

  /// The forecast [step] months after the last fitted point (1 = next).
  double ahead(int step) => _ahead(step);

  double get sigma {
    if (residuals.length < 2) return 0;
    var sse = 0.0;
    for (final r in residuals) {
      sse += r * r;
    }
    return math.sqrt(sse / residuals.length);
  }
}

/// The Dart forecasting baseline (pure; 0 reads). TensorFlow.js results come
/// in through [fromEngine] and are only used when [better].
class ForecastService {
  const ForecastService();

  static const _period = 12;
  static const _alphas = [0.2, 0.4, 0.6];
  static const _betas = [0.05, 0.1, 0.2];
  static const _gammas = [0.1, 0.3];

  /// Forecasts [horizon] months after [history] (monthly values, oldest
  /// first; [firstMonth] is the month of `history[0]`).
  ///
  /// Linear trend for 6–23 points; from [SmartConfig.seasonalMinPoints] on,
  /// trend + seasonality (Holt with seasonal indices) too, keeping whichever
  /// backtests better on the last [SmartConfig.holdoutFor] points. Null with
  /// fewer than [SmartConfig.forecastMinPoints] points, or when the backtest
  /// error is over [SmartConfig.maxForecastError] (or can't be measured).
  SeriesForecast? forecast(
    List<double> history, {
    required DateTime firstMonth,
    int horizon = SmartConfig.forecastHorizon,
  }) {
    final n = history.length;
    if (n < SmartConfig.forecastMinPoints || horizon < 1) return null;
    if (history.any((v) => !v.isFinite)) return null;
    final hold = SmartConfig.holdoutFor(n);
    final train = history.sublist(0, n - hold);
    final actual = history.sublist(n - hold);

    double? backtest(_Fit? Function(List<double>) fit) {
      final f = fit(train);
      if (f == null) return null;
      return weightedError(actual, [for (var k = 1; k <= hold; k++) f.ahead(k)]);
    }

    final candidates = <ForecastModel, double?>{
      ForecastModel.linear: backtest(_linear),
      if (n >= SmartConfig.seasonalMinPoints)
        ForecastModel.seasonal: backtest(_seasonal),
    };
    ForecastModel? best;
    double? bestError;
    candidates.forEach((model, error) {
      if (error == null || !error.isFinite) return;
      if (bestError == null || error < bestError!) {
        best = model;
        bestError = error;
      }
    });
    final model = best, error = bestError;
    if (model == null || error == null || error > SmartConfig.maxForecastError) {
      return null;
    }
    final fit = model == ForecastModel.seasonal ? _seasonal(history) : _linear(history);
    if (fit == null) return null;
    final sigma = fit.sigma;
    final mean = <double>[], lower = <double>[], upper = <double>[];
    for (var k = 1; k <= horizon; k++) {
      final m = fit.ahead(k);
      final band = SmartConfig.bandZ * sigma * math.sqrt(k);
      mean.add(m);
      lower.add(m - band);
      upper.add(m + band);
    }
    if (mean.any((v) => !v.isFinite)) return null;
    return SeriesForecast(
      mean: mean,
      lower: lower,
      upper: upper,
      error: error,
      model: model,
      points: n,
    );
  }

  /// Ordinary least squares on t = 0..n-1.
  static _Fit? _linear(List<double> y) {
    final n = y.length;
    if (n < 2) return null;
    final tMean = (n - 1) / 2;
    final yMean = y.reduce((a, b) => a + b) / n;
    var sxy = 0.0, sxx = 0.0;
    for (var t = 0; t < n; t++) {
      sxy += (t - tMean) * (y[t] - yMean);
      sxx += (t - tMean) * (t - tMean);
    }
    final slope = sxy / sxx;
    final intercept = yMean - slope * tMean;
    final residuals = [
      for (var t = 0; t < n; t++) y[t] - (intercept + slope * t),
    ];
    // Two parameters were fitted, so spread the error over n - 2.
    final scale = n > 2 ? math.sqrt(n / (n - 2)) : 1.0;
    return _Fit(
      [for (final r in residuals) r * scale],
      (k) => intercept + slope * (n - 1 + k),
    );
  }

  /// Additive Holt-Winters (period 12), the smoothing weights picked by
  /// in-sample one-step squared error.
  static _Fit? _seasonal(List<double> y) {
    final n = y.length;
    if (n < _period) return null;
    double mean(int from, int to) {
      var s = 0.0;
      for (var i = from; i < to; i++) {
        s += y[i];
      }
      return s / (to - from);
    }

    final year1 = mean(0, _period);
    double trend0;
    if (n >= 2 * _period) {
      trend0 = (mean(_period, 2 * _period) - year1) / _period;
    } else {
      final lin = _linear(y)!;
      trend0 = lin.ahead(1) - lin.ahead(0);
    }
    // Level at t = -1, and each month's deviation from the first-year trend.
    final level0 = year1 - trend0 * ((_period - 1) / 2 + 1);
    final season0 = [
      for (var i = 0; i < _period; i++)
        y[i] - (year1 + trend0 * (i - (_period - 1) / 2)),
    ];

    List<double>? bestResiduals;
    double? bestSse;
    late double bestLevel, bestTrend;
    late List<double> bestSeason;
    for (final a in _alphas) {
      for (final b in _betas) {
        for (final g in _gammas) {
          var level = level0, trend = trend0;
          final season = [...season0];
          final res = <double>[];
          var sse = 0.0;
          for (var t = 0; t < n; t++) {
            final s = t % _period;
            final err = y[t] - (level + trend + season[s]);
            res.add(err);
            sse += err * err;
            level += trend + a * err;
            trend += a * b * err;
            season[s] += g * (1 - a) * err;
          }
          if (bestSse == null || sse < bestSse) {
            bestSse = sse;
            bestResiduals = res;
            bestLevel = level;
            bestTrend = trend;
            bestSeason = season;
          }
        }
      }
    }
    if (bestResiduals == null) return null;
    return _Fit(
      bestResiduals,
      (k) => bestLevel + k * bestTrend + bestSeason[(n - 1 + k) % _period],
    );
  }

  /// A worker result as a [SeriesForecast] ([ForecastModel.tfjs]), under the
  /// same error gate; null when it fails the gate or is malformed.
  SeriesForecast? fromEngine(SmartSeriesForecast result, {required int points}) {
    final h = result.mean.length;
    if (h == 0 || result.lower.length != h || result.upper.length != h) {
      return null;
    }
    if (points < SmartConfig.forecastMinPoints) return null;
    final error = result.error;
    if (!error.isFinite || error > SmartConfig.maxForecastError) return null;
    final mean = <double>[], lower = <double>[], upper = <double>[];
    for (var i = 0; i < h; i++) {
      final m = result.mean[i], l = result.lower[i], u = result.upper[i];
      if (!m.isFinite || !l.isFinite || !u.isFinite) return null;
      mean.add(m);
      lower.add(math.min(math.min(l, u), m));
      upper.add(math.max(math.max(l, u), m));
    }
    return SeriesForecast(
      mean: mean,
      lower: lower,
      upper: upper,
      error: error,
      model: ForecastModel.tfjs,
      points: points,
    );
  }

  /// [enhanced] when it backtests better than [baseline], else [baseline].
  static SeriesForecast? better(
          SeriesForecast? baseline, SeriesForecast? enhanced) =>
      enhanced != null && (baseline == null || enhanced.error < baseline.error)
          ? enhanced
          : baseline;

  /// The calendar month (1–12) of each of [n] months from [firstMonth].
  static List<int> calendarMonths(DateTime firstMonth, int n) =>
      [for (var i = 0; i < n; i++) (firstMonth.month - 1 + i) % 12 + 1];

  /// Weighted MAPE: Σ|actual − forecast| / Σ|actual|; null when Σ|actual|
  /// is 0.
  static double? weightedError(List<double> actual, List<double> forecast) {
    final n = math.min(actual.length, forecast.length);
    var diff = 0.0, total = 0.0;
    for (var i = 0; i < n; i++) {
      diff += (actual[i] - forecast[i]).abs();
      total += actual[i].abs();
    }
    return total == 0 ? null : diff / total;
  }
}
