import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme/app_density.dart';

/// A page the user pinned to the sidebar.
@immutable
class PinnedPage {
  const PinnedPage({required this.path, required this.label});

  final String path;
  final String label;

  Map<String, String> toJson() => {'path': path, 'label': label};

  static PinnedPage? fromJson(Object? json) {
    if (json is! Map) return null;
    final path = json['path'];
    final label = json['label'];
    if (path is! String || path.isEmpty) return null;
    return PinnedPage(path: path, label: label is String ? label : path);
  }
}

/// This browser's preferences for the signed-in user: theme, motion, density,
/// sidebar, pinned pages, recent commands and screen state. Stored in
/// shared_preferences only — never in Firestore, so it costs no reads or
/// writes.
///
/// Keys are `sbm.u.<uid>.<name>`, so two people sharing a browser keep their
/// own settings. Before sign-in the scope is `_`. The theme mode is also kept
/// per device (`sbm.d.themeMode`), so the login screen opens in the mode the
/// last person picked.
class UserPrefs extends ChangeNotifier {
  UserPrefs(this._prefs);

  final SharedPreferences _prefs;
  String _scope = '_';

  static const _deviceThemeKey = 'sbm.d.themeMode';
  static const _lastLoginIdKey = 'sbm.d.lastLoginId';
  static const maxRecent = 8;

  String? get uid => _scope == '_' ? null : _scope;

  /// Switches to [uid]'s preferences (or the signed-out scope for null).
  void bindUser(String? uid) {
    final scope = (uid == null || uid.isEmpty) ? '_' : uid;
    if (scope == _scope) return;
    _scope = scope;
    notifyListeners();
  }

  String _key(String name) => 'sbm.u.$_scope.$name';

  // ---------------------------------------------------------------- theme --

  /// The user's chosen theme mode, or null if they never picked one (then the
  /// organisation's default applies).
  ThemeMode? get themeMode =>
      _mode(_prefs.getString(_key('themeMode'))) ??
      (uid == null ? _mode(_prefs.getString(_deviceThemeKey)) : null);

  Future<void> setThemeMode(ThemeMode? mode) async {
    if (mode == null) {
      await _prefs.remove(_key('themeMode'));
      await _prefs.remove(_deviceThemeKey);
    } else {
      await _prefs.setString(_key('themeMode'), mode.name);
      await _prefs.setString(_deviceThemeKey, mode.name);
    }
    notifyListeners();
  }

  static ThemeMode? _mode(String? name) {
    for (final m in ThemeMode.values) {
      if (m.name == name) return m;
    }
    return null;
  }

  bool get reduceMotion => _prefs.getBool(_key('reduceMotion')) ?? false;

  Future<void> setReduceMotion(bool value) =>
      _set(() => _prefs.setBool(_key('reduceMotion'), value));

  /// The user's density override, or null to follow the organisation.
  AppDensity? get density {
    final name = _prefs.getString(_key('density'));
    return name == null ? null : AppDensity.fromName(name);
  }

  Future<void> setDensity(AppDensity? density) => _set(() => density == null
      ? _prefs.remove(_key('density'))
      : _prefs.setString(_key('density'), density.name));

  // -------------------------------------------------------------- shell --

  bool get sidebarCollapsed =>
      _prefs.getBool(_key('sidebarCollapsed')) ?? false;

  Future<void> setSidebarCollapsed(bool value) =>
      _set(() => _prefs.setBool(_key('sidebarCollapsed'), value));

  List<PinnedPage> get favourites {
    final list = readJson('favourites');
    if (list is! List) return const [];
    return [
      for (final e in list) ?PinnedPage.fromJson(e),
    ];
  }

  bool isFavourite(String path) => favourites.any((p) => p.path == path);

  /// Pins [path] if it isn't pinned, otherwise unpins it.
  Future<void> toggleFavourite(String path, String label) {
    final current = favourites;
    final next = current.any((p) => p.path == path)
        ? current.where((p) => p.path != path).toList()
        : [...current, PinnedPage(path: path, label: label)];
    return writeJson('favourites', [for (final p in next) p.toJson()]);
  }

  /// Command-palette entries the user ran recently, newest first.
  List<String> get recentCommands =>
      _prefs.getStringList(_key('recentCommands')) ?? const [];

  Future<void> pushRecentCommand(String id) {
    final next = [id, ...recentCommands.where((e) => e != id)];
    return _set(() => _prefs.setStringList(
        _key('recentCommands'), next.take(maxRecent).toList()));
  }

  /// The business and period last picked in the scope selectors.
  Map<String, dynamic>? get scope {
    final value = readJson('scope');
    return value is Map<String, dynamic> ? value : null;
  }

  Future<void> setScope(Map<String, dynamic> value) =>
      writeJson('scope', value, notify: false);

  /// Alert types (`AlertType` names) this user chose not to see.
  Set<String> get hiddenAlertTypes =>
      {...?_prefs.getStringList(_key('alertTypesHidden'))};

  Future<void> setHiddenAlertTypes(Set<String> types) => _set(() =>
      types.isEmpty
          ? _prefs.remove(_key('alertTypesHidden'))
          : _prefs.setStringList(
              _key('alertTypesHidden'), types.toList()..sort()));

  // ------------------------------------------------------------- device --

  /// The login ID (or email) last used to sign in on this device.
  String? get lastLoginId => _prefs.getString(_lastLoginIdKey);

  Future<void> setLastLoginId(String? value) =>
      value == null || value.trim().isEmpty
          ? _prefs.remove(_lastLoginIdKey)
          : _prefs.setString(_lastLoginIdKey, value.trim());

  // ------------------------------------------------------------ generic --

  /// A JSON value stored under [name] for this user, or null.
  Object? readJson(String name) {
    final raw = _prefs.getString(_key(name));
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } on FormatException {
      return null;
    }
  }

  Future<void> writeJson(String name, Object? value, {bool notify = true}) {
    Future<bool> write() => value == null
        ? _prefs.remove(_key(name))
        : _prefs.setString(_key(name), jsonEncode(value));
    return notify ? _set(write) : write();
  }

  Future<void> _set(Future<bool> Function() write) async {
    await write();
    notifyListeners();
  }
}
