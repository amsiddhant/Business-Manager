import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../models/app_settings.dart';
import 'settings_controller.dart';

/// Reading the organisation's settings from widgets.
///
/// Both fall back to the defaults where no [SettingsController] is provided
/// (e.g. a widget test of a single screen), so a widget never has to care.
extension OrgSettingsContext on BuildContext {
  /// Picks a part of the settings and rebuilds only when that part changes.
  /// Call from `build`.
  T orgSettings<T>(T Function(AppSettings s) pick) {
    try {
      return select<SettingsController, T>((c) => pick(c.settings));
    } on ProviderNotFoundException {
      return pick(const AppSettings());
    }
  }

  /// The settings now, without listening (for callbacks and `initState`).
  AppSettings readOrgSettings() {
    try {
      return read<SettingsController>().settings;
    } on ProviderNotFoundException {
      return const AppSettings();
    }
  }
}
