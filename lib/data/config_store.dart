import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/firebase_config.dart';

/// Persists application-level configuration in the browser:
///  * which backend is active (local demo vs Firebase),
///  * the public Firebase web config (if provided),
///  * general app preferences (app name, default currency).
///
/// Only *public* Firebase client values are stored here — never secrets.
class ConfigStore {
  ConfigStore(this._prefs);

  final SharedPreferences _prefs;

  static const _backendKey = 'sbm_backend_mode';
  static const _firebaseConfigKey = 'sbm_firebase_config';
  static const _appNameKey = 'sbm_app_name';
  static const _dateFormatKey = 'sbm_date_format';

  /// Whether the app runs against Firebase. The application ships connected to
  /// Firebase by default: only an explicit switch to demo mode persists
  /// 'local', so a first launch (no stored preference) is Firebase.
  bool get isFirebaseMode => _prefs.getString(_backendKey) != 'local';

  Future<void> setFirebaseMode(bool enabled) =>
      _prefs.setString(_backendKey, enabled ? 'firebase' : 'local');

  /// The active Firebase config: a config saved via the wizard if present,
  /// otherwise the bundled default project the app ships with.
  FirebaseConfig? get firebaseConfig {
    final raw = _prefs.getString(_firebaseConfigKey);
    if (raw == null) return FirebaseConfig.defaultConfig;
    try {
      return FirebaseConfig.fromMap(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return FirebaseConfig.defaultConfig;
    }
  }

  Future<void> saveFirebaseConfig(FirebaseConfig config) =>
      _prefs.setString(_firebaseConfigKey, jsonEncode(config.toMap()));

  Future<void> clearFirebaseConfig() async {
    await _prefs.remove(_firebaseConfigKey);
    await setFirebaseMode(false);
  }

  String get appName => _prefs.getString(_appNameKey) ?? 'Salesforce Business Manager';
  Future<void> setAppName(String name) => _prefs.setString(_appNameKey, name);

  String get dateFormat => _prefs.getString(_dateFormatKey) ?? 'dd-MMM-yyyy';
  Future<void> setDateFormat(String fmt) =>
      _prefs.setString(_dateFormatKey, fmt);
}
