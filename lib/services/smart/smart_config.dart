/// On-device AI switches and limits (since 2.0.0).
///
/// Every smart feature has a Dart baseline that shows at once. TensorFlow.js
/// (`web/tfjs/4.22.0/`, run by `web/smart/1/bm_worker.js`) only upgrades a
/// result when it has loaded, passed its self-test, has enough data and
/// backtests better. Nothing here reads or writes Firestore.
abstract final class SmartConfig {
  /// Build-time kill switch: `--dart-define=BM_SMART=false` keeps
  /// TensorFlow.js off for everyone (the Dart baselines stay).
  static const bool buildEnabled =
      bool.fromEnvironment('BM_SMART', defaultValue: true);

  /// `?nosmart=1` in the address keeps TensorFlow.js off for this page load.
  static bool get urlDisabled {
    try {
      return Uri.base.queryParameters['nosmart'] == '1';
    } catch (_) {
      return false;
    }
  }

  // ---- Worker ---------------------------------------------------------------

  /// The worker protocol this app speaks. A changed worker goes in
  /// `web/smart/<protocol>/` (the folder is cached as immutable).
  static const int protocol = 1;
  static const String tfjsVersion = '4.22.0';
  static const String workerPath = 'smart/1/bm_worker.js';

  /// This browser's IndexedDB database for trained models.
  static const String deviceDb = 'bm-smart';

  /// How long after the dashboard's first frame the worker may start.
  static const Duration spawnDelay = Duration(seconds: 2);

  static const Duration loadTimeout = Duration(seconds: 25);
  static const Duration selfTestTimeout = Duration(seconds: 20);
  static const Duration forecastTimeout = Duration(seconds: 20);
  static const Duration anomalyTimeout = Duration(seconds: 15);
  static const Duration trainTimeout = Duration(seconds: 60);
  static const Duration predictTimeout = Duration(seconds: 5);
  static const Duration saveTimeout = Duration(seconds: 10);
  static const Duration forgetTimeout = Duration(seconds: 3);

  /// Failures in a row (timeouts, a failed self-test) before TensorFlow.js
  /// switches itself off for this user on this device.
  static const int maxFailures = 3;

  // ---- Classifiers (expense category, campaign platform) ---------------------

  /// Records needed before a classifier trains (the org can change it:
  /// `settings.smart.minRows`).
  static const int defaultMinRows = 50;

  /// Retrain after this many new records, or once the model is this old.
  static const int retrainAfterRows = 20;
  static const Duration retrainAfter = Duration(days: 7);

  /// Hashed token buckets, tokens per row and embedding size.
  static const int buckets = 4096;
  static const int tokens = 16;
  static const int dims = 16;

  /// Models kept per browser (oldest dropped first).
  static const int maxModels = 6;

  /// A classifier suggestion needs at least this probability.
  static const double minProbability = 0.35;

  // ---- Forecasts -------------------------------------------------------------

  /// Monthly history read for forecasts (complete months, before this one).
  static const int historyMonths = 36;

  /// Fewer complete months than this: no forecast at all.
  static const int forecastMinPoints = 6;

  /// From this many months the Dart baseline also tries seasonality, and
  /// TensorFlow.js may try to beat it.
  static const int seasonalMinPoints = 24;
  static const int tfForecastMinPoints = 24;

  /// Forecasts that backtest worse than this (weighted MAPE) are hidden.
  static const double maxForecastError = 0.35;

  /// Months forecast (the current month first); the chart shows the first
  /// [chartHorizon], period-end projections may use them all.
  static const int forecastHorizon = 12;
  static const int chartHorizon = 3;

  /// z for the ±80% band.
  static const double bandZ = 1.2816;

  /// Held-out months for backtests, the same rule in Dart and the worker:
  /// a quarter of the history, between 3 and 6.
  static int holdoutFor(int points) => (points ~/ 4).clamp(3, 6);

  // ---- Anomalies -------------------------------------------------------------

  /// Monthly spend read for the on-device anomaly model (incl. this month).
  static const int anomalyMonths = 13;

  /// A cost line needs this many months, this many with spend, before the
  /// on-device model scores it.
  static const int anomalyMinMonths = 12;
  static const int anomalyMinSpendMonths = 9;
}
