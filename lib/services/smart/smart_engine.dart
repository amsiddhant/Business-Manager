import 'dart:typed_data';

import 'smart_types.dart';

/// Runs TensorFlow.js models off the page's thread (a Web Worker on the
/// web; none elsewhere — see `smart_engine_factory.dart`).
///
/// Never throws: a failure or timeout gives null (and stops the worker), and
/// the caller keeps its Dart baseline. Requests carry numbers only — token
/// ids, class numbers and monthly figures — never text.
abstract interface class SmartEngine {
  /// Trains and checks toy models, round-trips IndexedDB and checks no
  /// tensors leaked. The first call starts the worker and loads TensorFlow.js.
  Future<SmartSelfTest?> selfTest();

  /// Forecasts [horizon] months after [y] (monthly values, oldest first);
  /// [months] is each value's calendar month (1–12). A small autoregressive
  /// model (up to 12 lags + month sin/cos), trained per call; backtested on
  /// the last [SmartConfig.holdoutFor] values first.
  Future<SmartSeriesForecast?> forecast(Float64List y, Int32List months,
      {required int horizon});

  /// Seasonal-residual scores for [k] series of [n] months each (row-major,
  /// oldest first; the last month is the current one so far): how far each
  /// series' last value sits above what its own history predicts, in robust
  /// standard deviations. NaN where it can't tell.
  Future<Float64List?> anomaly(Float64List series, Int32List months,
      {required int k, required int n});

  /// Trains a classifier and keeps it (in memory) under [SmartTrainRequest.key].
  Future<SmartTrainResult?> train(SmartTrainRequest request);

  /// Keeps the model under [key] in this browser with [meta]. True when saved
  /// in IndexedDB, false when only for this session.
  Future<bool?> save(String key, String meta);

  /// Loads the saved model under [key] and returns its meta: '' for none.
  Future<String?> load(String key);

  /// The [k] most likely classes per head for [n] rows of token ids.
  Future<Map<String, SmartHeadPrediction>?> predict(String key, Int32List x,
      {required int n, int k = 3});

  /// Forgets the model under [key] (memory and IndexedDB).
  Future<bool> drop(String key);

  /// Stops the worker (it keeps nothing in memory); the next call starts a
  /// new one.
  void dispose();
}
