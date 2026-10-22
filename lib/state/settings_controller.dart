import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/app_exception.dart';
import '../core/permissions.dart';
import '../core/utils/date_utils.dart';
import '../core/utils/money.dart';
import '../models/app_settings.dart';
import '../models/app_user.dart';
import 'app_state.dart';
import 'theme_controller.dart';

/// The organisation's settings (`settings/app`), as everyone sees them.
///
/// One read after sign-in, plus one for the logo only when it changed. The
/// last copy is cached in shared_preferences so the brand, theme, FY start
/// and login branding are right on the very first frame.
///
/// When nothing has been saved yet the defaults apply, merged with the older
/// per-browser app name and date format, and nothing is written.
class SettingsController extends ChangeNotifier {
  SettingsController(this._app, this._theme) {
    _readCache();
    FinancialYear.configureStartMonth(_settings.defaults.fyStartMonth);
    if (_hasRemote) {
      AppDate.configureDisplayFormat(_settings.defaults.dateFormat);
    } else {
      _settings = _withLegacy(_settings);
    }
  }

  final AppState _app;
  final ThemeController _theme;

  static const _cacheKey = 'sbm_org_settings_v1';
  static const _logoKey = 'sbm_org_logo_v1';

  AppSettings _settings = const AppSettings();

  /// The settings in effect.
  AppSettings get settings => _settings;

  bool _hasRemote = false;

  /// Whether the organisation has saved settings (false = defaults).
  bool get hasRemote => _hasRemote;

  String? _logo;

  /// The logo as a data URL, or null.
  String? get logo => _logo;

  bool _loading = false;
  bool get loading => _loading;

  bool _loaded = false;

  /// Whether a load has finished this session (successfully or not).
  bool get loaded => _loaded;

  String? _error;

  /// Why the last load failed, if it did.
  String? get error => _error;

  bool _rulesMissing = false;

  /// True when the rules refused the read: they haven't been deployed yet.
  bool get rulesMissing => _rulesMissing;

  /// Whether [user] may change the organisation's settings.
  bool canEdit(AppUser? user) => user?.can(Permission.manageSettings) ?? false;

  /// What the Settings editor starts from: the saved settings, or (none
  /// saved yet) the defaults with this browser's old name and date format.
  AppSettings get editorSeed => _settings;

  /// Reads the settings (and the logo, if it changed). Failures keep the
  /// cached copy.
  Future<void> load() async {
    if (_app.currentUser == null || _loading) return;
    _loading = true;
    _error = null;
    _rulesMissing = false;
    notifyListeners();
    try {
      final remote = await _app.repository.fetchAppSettings();
      if (remote == null) {
        await _set(_withLegacy(const AppSettings()),
            hasRemote: false, logo: null);
      } else {
        var logo = _logo;
        final hash = remote.branding.logoHash;
        if (hash == null) {
          logo = null;
        } else if (hash != _cachedLogoHash || logo == null) {
          try {
            logo = await _app.repository.fetchLogo();
          } catch (e) {
            debugPrint('Settings: logo not loaded: $e');
          }
        }
        await _set(remote, hasRemote: true, logo: logo);
      }
    } catch (e) {
      if (_isPermissionDenied(e)) {
        _rulesMissing = true;
      } else {
        _error = ErrorMapper.friendly(e);
      }
    } finally {
      _loading = false;
      _loaded = true;
      notifyListeners();
    }
  }

  /// Saves [draft] for everyone (one write, plus the logo when
  /// [logoChanged]: [logoDataUrl] sets it, null removes it).
  Future<void> save(
    AppSettings draft, {
    bool logoChanged = false,
    String? logoDataUrl,
  }) async {
    final saved = await _app.repository.saveAppSettings(
      draft,
      logoChanged: logoChanged,
      logoDataUrl: logoDataUrl,
    );
    await _set(saved,
        hasRemote: true, logo: logoChanged ? logoDataUrl : _logo);
    _rulesMissing = false;
    notifyListeners();
  }

  static bool _isPermissionDenied(Object e) =>
      (e is AppException && e.code == 'permission-denied') ||
      e.toString().contains('permission-denied');

  /// Defaults for the parts that older versions kept per browser.
  AppSettings _withLegacy(AppSettings s) {
    final store = _app.configStore;
    return s.copyWith(
      branding: s.branding.copyWith(appName: store.appName),
      defaults: s.defaults.copyWith(dateFormat: store.dateFormat),
    );
  }

  String? _cachedLogoHash;

  Future<void> _set(
    AppSettings next, {
    required bool hasRemote,
    required String? logo,
  }) async {
    _settings = next;
    _hasRemote = hasRemote;
    _logo = logo;
    _cachedLogoHash = logo == null ? null : next.branding.logoHash;
    await _writeCache();
    await _apply();
  }

  /// Pushes the settings into the parts of the app that read them globally.
  Future<void> _apply() async {
    final s = _settings;
    FinancialYear.configureStartMonth(s.defaults.fyStartMonth);
    MoneyFormatter.configureGrouping(s.defaults.numberGrouping);
    if (_hasRemote) {
      // Keep the older per-browser values in step, so everything that still
      // reads them (window title, sign-in page) shows the organisation's.
      if (_app.dateFormat != s.defaults.dateFormat) {
        await _app.setDateFormat(s.defaults.dateFormat);
      } else {
        AppDate.configureDisplayFormat(s.defaults.dateFormat);
      }
      if (_app.appName != s.branding.appName) {
        await _app.setAppName(s.branding.appName);
      }
    }
    await _theme.applyOrgTheme(orgThemeOf(s));
  }

  /// The organisation-wide look that [s] describes.
  static OrgTheme orgThemeOf(AppSettings s) => OrgTheme(
        brand: s.branding.brand,
        defaultMode: s.theme.defaultMode,
        allowUserOverride: s.theme.allowUserOverride,
        density: s.theme.density,
        motion: s.theme.motion,
        corners: s.theme.corners,
        chartPalette: s.theme.chartPalette,
      );

  void _readCache() {
    final prefs = _app.prefs;
    final raw = prefs.getString(_cacheKey);
    if (raw == null) return;
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return;
      _settings = AppSettings.fromMap(json);
      _hasRemote = true;
      final logo = prefs.getString(_logoKey);
      final sep = logo?.indexOf('|') ?? -1;
      if (logo != null && sep > 0) {
        _cachedLogoHash = logo.substring(0, sep);
        if (_cachedLogoHash == _settings.branding.logoHash) {
          _logo = logo.substring(sep + 1);
        }
      }
    } on FormatException {
      return;
    }
  }

  Future<void> _writeCache() async {
    final prefs = _app.prefs;
    if (_hasRemote) {
      await prefs.setString(_cacheKey, jsonEncode(_settings.toMap()));
    } else {
      await prefs.remove(_cacheKey);
    }
    final hash = _settings.branding.logoHash;
    if (_logo != null && hash != null) {
      await prefs.setString(_logoKey, '$hash|$_logo');
    } else {
      await prefs.remove(_logoKey);
    }
  }
}
