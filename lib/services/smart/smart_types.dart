import 'dart:typed_data';

import 'smart_config.dart';

/// What the worker's self-test found.
class SmartSelfTest {
  const SmartSelfTest({
    required this.version,
    required this.backend,
    required this.accuracy,
    required this.forecastError,
    required this.storage,
    required this.tensorsBefore,
    required this.tensorsAfter,
    required this.ms,
  });

  /// TensorFlow.js version and backend ('cpu').
  final String version;
  final String backend;

  /// Toy classifier accuracy (0–1).
  final double accuracy;

  /// Toy forecast backtest error (weighted MAPE, 0–1+).
  final double forecastError;

  /// Whether models can be kept in this browser (IndexedDB round-trip).
  final bool storage;

  /// Live tensors before and after: equal means nothing leaked.
  final int tensorsBefore;
  final int tensorsAfter;
  final int ms;

  bool get passed =>
      version == SmartConfig.tfjsVersion &&
      accuracy >= 0.9 &&
      forecastError <= 0.2 &&
      tensorsAfter <= tensorsBefore;
}

/// The worker's forecast for one monthly series, in the series' units.
class SmartSeriesForecast {
  const SmartSeriesForecast({
    required this.mean,
    required this.lower,
    required this.upper,
    required this.error,
  });

  /// One value per forecast month.
  final Float64List mean;
  final Float64List lower;
  final Float64List upper;

  /// Backtest error on the held-out months ([SmartConfig.holdoutFor]),
  /// weighted MAPE: Σ|actual − forecast| / Σ|actual|.
  final double error;
}

/// Training data for a bag-of-words classifier with one softmax per head.
class SmartTrainRequest {
  const SmartTrainRequest({
    required this.key,
    required this.heads,
    required this.n,
    required this.x,
    required this.y,
    this.hn = 0,
    this.hx,
    this.tokens = SmartConfig.tokens,
    this.buckets = SmartConfig.buckets,
    this.dims = SmartConfig.dims,
    this.epochs = 30,
    this.batch = 32,
    this.learningRate = 0.02,
  });

  /// Where the model is kept (no user text: a hash and a kind).
  final String key;

  /// Head name → number of classes.
  final Map<String, int> heads;

  /// Rows, and their token ids ([n] × [tokens], row-major).
  final int n;
  final Int32List x;

  /// Head name → the class of each row.
  final Map<String, Int32List> y;

  /// Held-out rows to predict after training (for the backtest): [hn] rows
  /// of token ids in [hx] (null when [hn] is 0).
  final int hn;
  final Int32List? hx;

  final int tokens;
  final int buckets;
  final int dims;
  final int epochs;
  final int batch;
  final double learningRate;
}

/// Training time and the held-out rows' predictions.
class SmartTrainResult {
  const SmartTrainResult({required this.ms, required this.heads});

  final int ms;
  final Map<String, SmartHeadPrediction> heads;
}

/// The [k] most likely classes for each row, best first.
class SmartHeadPrediction {
  const SmartHeadPrediction({required this.top, required this.p, required this.k});

  /// rows × [k] class numbers and their probabilities.
  final Int32List top;
  final Float32List p;
  final int k;

  int get rows => k == 0 ? 0 : top.length ~/ k;

  int classAt(int row, [int rank = 0]) => top[row * k + rank];
  double probabilityAt(int row, [int rank = 0]) => p[row * k + rank];
}
