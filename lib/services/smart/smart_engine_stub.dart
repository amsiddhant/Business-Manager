import 'smart_engine.dart';

/// No smart engine off the web (VM tests): the Dart baselines are used.
SmartEngine? createSmartEngine() => null;

Future<void> wipeSmartDevice() async {}
