/// Caches derived values until the data they are computed from changes.
///
/// Values are keyed by a *stamp* — typically `DataController.version`, which
/// changes on every load or write — plus a key for the arguments (a record
/// such as `('orders', businessId)` works well). Asking with a new stamp drops
/// everything computed for the old one, so stale results are never returned.
class StampedMemo {
  Object? _stamp;
  final Map<Object?, Object?> _values = {};

  T get<T>(Object stamp, Object? key, T Function() compute) {
    if (_stamp != stamp) {
      _values.clear();
      _stamp = stamp;
    }
    if (_values.containsKey(key)) return _values[key] as T;
    final value = compute();
    _values[key] = value;
    return value;
  }

  void clear() {
    _values.clear();
    _stamp = null;
  }
}
