import 'smart_engine.dart';
import 'smart_engine_stub.dart'
    if (dart.library.js_interop) 'smart_engine_web.dart' as impl;

/// This platform's smart engine: the TensorFlow.js worker in the browser,
/// none elsewhere (VM tests). Making one starts nothing and downloads
/// nothing; the worker starts on the first request.
SmartEngine? smartEngine() => impl.createSmartEngine();

/// Deletes this browser's saved models. Stop the engine first.
Future<void> wipeSmartDevice() => impl.wipeSmartDevice();
