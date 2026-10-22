import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme/app_density.dart';
import '../core/theme/app_motion.dart';
import '../core/theme/app_palette.dart';
import '../core/theme/app_theme.dart';
import 'user_prefs.dart';

/// The organisation-wide look, set by the Owner or an Admin (Settings, P4).
@immutable
class OrgTheme {
  const OrgTheme({
    this.brand = AppPalette.defaultBrand,
    this.defaultMode = ThemeMode.light,
    this.allowUserOverride = true,
    this.density = AppDensity.comfortable,
    this.motion = MotionLevel.full,
  });

  final Color brand;
  final ThemeMode defaultMode;

  /// Whether people may pick their own light/dark mode.
  final bool allowUserOverride;
  final AppDensity density;
  final MotionLevel motion;

  Map<String, dynamic> toJson() => {
        'brand': brand.toARGB32(),
        'defaultMode': defaultMode.name,
        'allowUserOverride': allowUserOverride,
        'density': density.name,
        'motion': motion.name,
      };

  /// Tolerant: anything missing or unknown falls back to the default.
  factory OrgTheme.fromJson(Map<String, dynamic> json) {
    final brand = json['brand'];
    return OrgTheme(
      brand: brand is int ? Color(brand | 0xFF000000) : AppPalette.defaultBrand,
      defaultMode: ThemeMode.values.firstWhere(
        (m) => m.name == json['defaultMode'],
        orElse: () => ThemeMode.light,
      ),
      allowUserOverride: json['allowUserOverride'] != false,
      density: AppDensity.fromName(json['density'] as String?),
      motion: MotionLevel.fromName(json['motion'] as String?),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is OrgTheme &&
      other.brand.toARGB32() == brand.toARGB32() &&
      other.defaultMode == defaultMode &&
      other.allowUserOverride == allowUserOverride &&
      other.density == density &&
      other.motion == motion;

  @override
  int get hashCode => Object.hash(
      brand.toARGB32(), defaultMode, allowUserOverride, density, motion);
}

/// Resolves the theme the app should use right now from the organisation's
/// look and the signed-in user's own choices, and builds (and caches) the
/// light and dark [ThemeData].
///
/// The org theme is cached in shared_preferences, so the right brand and mode
/// paint on the very first frame — before anything is fetched.
class ThemeController extends ChangeNotifier {
  ThemeController(this._prefs, this._user) {
    _org = _readCachedOrg();
    _user.addListener(_resolve);
    _resolve(notify: false);
  }

  final SharedPreferences _prefs;
  final UserPrefs _user;

  static const _orgKey = 'sbm_org_theme_v1';

  late OrgTheme _org;
  OrgTheme get org => _org;

  late ThemeMode _mode;
  late AppDensity _density;
  late MotionLevel _motion;

  ThemeMode get mode => _mode;
  AppDensity get density => _density;
  MotionLevel get motion => _motion;

  /// Whether the user may switch light/dark themselves.
  bool get canChooseMode => _org.allowUserOverride;

  ThemeData? _light;
  ThemeData? _dark;
  ThemeData get light => _light ??= _build(Brightness.light);
  ThemeData get dark => _dark ??= _build(Brightness.dark);

  /// Light or dark as it resolves for [platform] (used for "System").
  Brightness brightnessFor(Brightness platform) => switch (_mode) {
        ThemeMode.light => Brightness.light,
        ThemeMode.dark => Brightness.dark,
        ThemeMode.system => platform,
      };

  /// Applies (and caches) a new organisation theme.
  Future<void> applyOrgTheme(OrgTheme theme) async {
    if (theme == _org) return;
    _org = theme;
    await _prefs.setString(_orgKey, jsonEncode(theme.toJson()));
    _resolve();
  }

  OrgTheme _readCachedOrg() {
    final raw = _prefs.getString(_orgKey);
    if (raw == null) return const OrgTheme();
    try {
      final json = jsonDecode(raw);
      return json is Map<String, dynamic>
          ? OrgTheme.fromJson(json)
          : const OrgTheme();
    } on FormatException {
      return const OrgTheme();
    }
  }

  Color? _builtBrand;

  void _resolve({bool notify = true}) {
    final mode = (_org.allowUserOverride ? _user.themeMode : null) ??
        _org.defaultMode;
    final density = _user.density ?? _org.density;
    final motion = _user.reduceMotion
        ? _org.motion.atMost(MotionLevel.reduced)
        : _org.motion;

    final first = _builtBrand == null;
    final looksChanged = first ||
        _builtBrand!.toARGB32() != _org.brand.toARGB32() ||
        density != _density ||
        motion != _motion;
    final changed = looksChanged || mode != _mode;

    _mode = mode;
    _density = density;
    _motion = motion;
    if (looksChanged) {
      _builtBrand = _org.brand;
      _light = null;
      _dark = null;
    }
    if (changed && notify && !first) notifyListeners();
  }

  ThemeData _build(Brightness brightness) => AppTheme.build(
        brand: _org.brand,
        brightness: brightness,
        density: _density,
        motion: _motion,
      );

  @override
  void dispose() {
    _user.removeListener(_resolve);
    super.dispose();
  }
}
