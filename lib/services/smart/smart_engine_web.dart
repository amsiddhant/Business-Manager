import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'smart_config.dart';
import 'smart_engine.dart';
import 'smart_types.dart';

SmartEngine? createSmartEngine() => SmartEngineWeb();

/// Deletes the on-device models database ([SmartConfig.deviceDb]). Doesn't
/// wait past [SmartConfig.forgetTimeout]; a blocked delete finishes once the
/// last connection closes.
Future<void> wipeSmartDevice() async {
  final done = Completer<void>();
  void finish(web.Event _) {
    if (!done.isCompleted) done.complete();
  }

  try {
    final r = web.window.indexedDB.deleteDatabase(SmartConfig.deviceDb);
    r.onsuccess = finish.toJS;
    r.onerror = finish.toJS;
    r.onblocked = finish.toJS;
  } catch (_) {
    return;
  }
  await done.future.timeout(SmartConfig.forgetTimeout, onTimeout: () {});
}

/// The on-device AI worker ([SmartConfig.workerPath]), started on the first
/// request; it loads TensorFlow.js from this site on its own first request.
/// Requests carry numbers only (token ids, class numbers, monthly figures),
/// never text, and nothing here logs.
class SmartEngineWeb implements SmartEngine {
  web.Worker? _worker;
  Future<bool>? _hello;
  var _next = 0;
  final _pending = <int, Completer<JSObject?>>{};

  web.Worker _spawn() {
    final url = Uri.parse(web.document.baseURI)
        .resolve(SmartConfig.workerPath)
        .toString();
    final w = web.Worker(url.toJS);
    w.onmessage = ((web.MessageEvent e) => _reply(e.data)).toJS;
    // A missing or broken worker file: stop, and every request gives null.
    w.onerror = ((web.Event e) {
      e.preventDefault();
      dispose();
    }).toJS;
    return w;
  }

  void _reply(JSAny? data) {
    try {
      final d = data as JSObject;
      final c = _pending.remove((d['id'] as JSNumber).toDartInt);
      if (c == null || c.isCompleted) return;
      c.complete((d['ok'] as JSBoolean?)?.toDart == true ? d : null);
    } catch (_) {}
  }

  Future<JSObject?> _send(String op, Duration timeout,
      [void Function(JSObject m)? fill]) async {
    final c = Completer<JSObject?>();
    try {
      final w = _worker ??= _spawn();
      final id = ++_next;
      final m = JSObject()
        ..['id'] = id.toJS
        ..['op'] = op.toJS;
      fill?.call(m);
      _pending[id] = c;
      w.postMessage(m);
    } catch (_) {
      dispose();
      return null;
    }
    return c.future.timeout(timeout, onTimeout: () {
      dispose();
      return null;
    });
  }

  /// The worker answers with the protocol and TensorFlow.js version this app
  /// was built for (a missing file would be the app's index.html).
  Future<bool> _ready() =>
      _hello ??= _send('hello', SmartConfig.loadTimeout).then((r) {
        final ok = r != null &&
            (r['protocol'] as JSNumber?)?.toDartInt == SmartConfig.protocol &&
            (r['version'] as JSString?)?.toDart == SmartConfig.tfjsVersion;
        if (!ok) dispose();
        return ok;
      });

  Future<JSObject?> _call(String op, Duration timeout,
      [void Function(JSObject m)? fill]) async {
    if (!await _ready()) return null;
    return _send(op, timeout, fill);
  }

  static Map<String, SmartHeadPrediction> _heads(JSObject r) {
    final heads = r['heads'] as JSObject;
    final keys = (globalContext['Object'] as JSObject)
        .callMethod<JSArray<JSString>>('keys'.toJS, heads)
        .toDart;
    return {
      for (final k in keys)
        k.toDart: () {
          final h = heads[k.toDart] as JSObject;
          return SmartHeadPrediction(
            top: (h['top'] as JSInt32Array).toDart,
            p: (h['p'] as JSFloat32Array).toDart,
            k: (h['k'] as JSNumber).toDartInt,
          );
        }(),
    };
  }

  @override
  Future<SmartSelfTest?> selfTest() async {
    final r = await _call('selftest', SmartConfig.selfTestTimeout);
    if (r == null) return null;
    try {
      return SmartSelfTest(
        version: (r['version'] as JSString).toDart,
        backend: (r['backend'] as JSString).toDart,
        accuracy: (r['accuracy'] as JSNumber).toDartDouble,
        forecastError: (r['forecastError'] as JSNumber).toDartDouble,
        storage: (r['storage'] as JSBoolean).toDart,
        tensorsBefore: (r['before'] as JSNumber).toDartInt,
        tensorsAfter: (r['after'] as JSNumber).toDartInt,
        ms: (r['ms'] as JSNumber).toDartInt,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<SmartSeriesForecast?> forecast(Float64List y, Int32List months,
      {required int horizon}) async {
    final r = await _call('forecast', SmartConfig.forecastTimeout, (m) {
      m
        ..['y'] = y.toJS
        ..['m'] = months.toJS
        ..['h'] = horizon.toJS;
    });
    if (r == null) return null;
    try {
      return SmartSeriesForecast(
        mean: (r['mean'] as JSFloat64Array).toDart,
        lower: (r['lower'] as JSFloat64Array).toDart,
        upper: (r['upper'] as JSFloat64Array).toDart,
        error: (r['error'] as JSNumber).toDartDouble,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Float64List?> anomaly(Float64List series, Int32List months,
      {required int k, required int n}) async {
    final r = await _call('anomaly', SmartConfig.anomalyTimeout, (m) {
      m
        ..['x'] = series.toJS
        ..['m'] = months.toJS
        ..['k'] = k.toJS
        ..['n'] = n.toJS;
    });
    if (r == null) return null;
    try {
      return (r['scores'] as JSFloat64Array).toDart;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<SmartTrainResult?> train(SmartTrainRequest q) async {
    final r = await _call('train', SmartConfig.trainTimeout, (m) {
      final y = JSObject();
      for (final e in q.y.entries) {
        y[e.key] = e.value.toJS;
      }
      m
        ..['key'] = q.key.toJS
        ..['L'] = q.tokens.toJS
        ..['B'] = q.buckets.toJS
        ..['D'] = q.dims.toJS
        ..['lr'] = q.learningRate.toJS
        ..['epochs'] = q.epochs.toJS
        ..['batch'] = q.batch.toJS
        ..['heads'] = [
          for (final h in q.heads.entries)
            JSObject()
              ..['name'] = h.key.toJS
              ..['classes'] = h.value.toJS,
        ].toJS
        ..['n'] = q.n.toJS
        ..['x'] = q.x.toJS
        ..['y'] = y
        ..['hn'] = q.hn.toJS
        ..['hx'] = q.hx?.toJS;
    });
    if (r == null) return null;
    try {
      return SmartTrainResult(
          ms: (r['ms'] as JSNumber).toDartInt, heads: _heads(r));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool?> save(String key, String meta) async {
    final r = await _call('save', SmartConfig.saveTimeout, (m) {
      m
        ..['key'] = key.toJS
        ..['meta'] = meta.toJS;
    });
    return r == null ? null : (r['persisted'] as JSBoolean?)?.toDart == true;
  }

  @override
  Future<String?> load(String key) async {
    final r = await _call(
        'load', SmartConfig.loadTimeout, (m) => m['key'] = key.toJS);
    if (r == null) return null;
    final meta = r['meta'];
    return meta.isA<JSString>() ? (meta as JSString).toDart : '';
  }

  @override
  Future<Map<String, SmartHeadPrediction>?> predict(String key, Int32List x,
      {required int n, int k = 3}) async {
    final r = await _call('predict', SmartConfig.predictTimeout, (m) {
      m
        ..['key'] = key.toJS
        ..['x'] = x.toJS
        ..['n'] = n.toJS
        ..['k'] = k.toJS;
    });
    if (r == null) return null;
    try {
      return _heads(r);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> drop(String key) async {
    final r = await _call(
        'drop', SmartConfig.forgetTimeout, (m) => m['key'] = key.toJS);
    return r != null;
  }

  @override
  void dispose() {
    try {
      _worker?.terminate();
    } catch (_) {}
    _worker = null;
    _hello = null;
    final waiting = _pending.values.toList();
    _pending.clear();
    for (final c in waiting) {
      if (!c.isCompleted) c.complete(null);
    }
  }
}
