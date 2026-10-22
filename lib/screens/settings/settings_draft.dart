import 'package:flutter/foundation.dart';

import '../../models/app_settings.dart';

/// The organisation settings being edited: one [AppSettings] plus the logo,
/// kept across section switches until it's saved or discarded.
class SettingsDraft extends ChangeNotifier {
  SettingsDraft(AppSettings seed, {String? logo})
      : _seed = seed,
        _seedLogo = logo,
        _settings = seed,
        _logo = logo;

  AppSettings _seed;
  String? _seedLogo;
  AppSettings _settings;
  String? _logo;
  bool _logoChanged = false;
  int _revision = 0;

  AppSettings get settings => _settings;

  /// The settings the draft started from (what is saved now).
  AppSettings get seed => _seed;

  /// The draft's logo as a data URL, or null for none.
  String? get logo => _logo;
  bool get logoChanged => _logoChanged;

  /// Bumps when the draft is replaced wholesale (reset, discard), so text
  /// fields know to reload their text.
  int get revision => _revision;

  bool get isDirty => !_settings.sameAs(_seed) || _logoChanged;

  void update(AppSettings Function(AppSettings s) change) {
    _settings = change(_settings);
    notifyListeners();
  }

  void setLogo(String? dataUrl, {required String? hash}) {
    _logo = dataUrl;
    _logoChanged = dataUrl != _seedLogo ||
        (dataUrl == null && _seed.branding.logoHash != null);
    _settings = _settings.copyWith(
        branding: _settings.branding.copyWith(logoHash: () => hash));
    notifyListeners();
  }

  /// Puts one section back to the built-in defaults: [apply] gets the draft
  /// and the defaults and returns the draft with that section replaced.
  void resetSection(
    AppSettings Function(AppSettings draft, AppSettings defaults) apply, {
    bool clearLogo = false,
  }) {
    _settings = apply(_settings, const AppSettings());
    if (clearLogo) {
      _logo = null;
      _logoChanged = _seedLogo != null;
    }
    _revision++;
    notifyListeners();
  }

  /// Everything back to the built-in defaults (the logo is removed too).
  void resetAll() {
    _settings = const AppSettings().copyWith(
        updatedAt: _seed.updatedAt, updatedBy: _seed.updatedBy);
    _logo = null;
    _logoChanged = _seedLogo != null;
    _revision++;
    notifyListeners();
  }

  /// Back to what is saved.
  void discard() {
    _settings = _seed;
    _logo = _seedLogo;
    _logoChanged = false;
    _revision++;
    notifyListeners();
  }

  /// The draft is now what's saved.
  void markSaved(AppSettings saved, {String? logo}) {
    _seed = saved;
    _seedLogo = logo;
    _settings = saved;
    _logo = logo;
    _logoChanged = false;
    _revision++;
    notifyListeners();
  }

  /// Re-seeds from newly loaded settings, unless there are unsaved edits.
  void reseed(AppSettings seed, {String? logo}) {
    if (isDirty) return;
    _seed = seed;
    _seedLogo = logo;
    _settings = seed;
    _logo = logo;
    _revision++;
    notifyListeners();
  }
}
