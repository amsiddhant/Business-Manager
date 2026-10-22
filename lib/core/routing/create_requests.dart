import 'package:flutter/foundation.dart';

/// A "create something" request for a screen that isn't on screen yet: the
/// caller navigates to [section] and calls [request]; the screen calls [take]
/// when it builds (and listens, in case it's already open) and opens its
/// create form.
///
/// Only screens whose form lives inside the screen use this (Users). Most
/// sections open their form directly — see `create_actions.dart`.
class CreateRequests extends ChangeNotifier {
  CreateRequests._();

  static final CreateRequests instance = CreateRequests._();

  String? _pending;

  void request(String section) {
    _pending = section;
    notifyListeners();
  }

  /// True (once) if a create request for [section] is waiting.
  bool take(String section) {
    if (_pending != section) return false;
    _pending = null;
    return true;
  }
}
