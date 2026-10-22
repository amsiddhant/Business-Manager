import 'package:flutter/foundation.dart';

import '../core/enums.dart';
import '../core/utils/date_utils.dart';
import '../models/app_settings.dart';
import '../services/alert_service.dart';
import 'data_controller.dart';
import 'memo.dart';
import 'settings_controller.dart';
import 'user_prefs.dart';

enum AlertState { active, snoozed, dismissed }

/// The alerts center's state: which alerts the current user dismissed or
/// snoozed (kept per user on this device), plus the alerts themselves,
/// computed from the loaded data and cached until it changes.
///
/// Thresholds and switched-off types come from the organisation's settings
/// ([SettingsController]); each user can also hide types for themselves.
class AlertController extends ChangeNotifier {
  AlertController(this._prefs, [this._settings]) {
    _load();
    _alertSettings = _orgAlerts();
    _prefs.addListener(_onPrefs);
    _settings?.addListener(_onSettings);
  }

  final UserPrefs _prefs;
  final SettingsController? _settings;
  late AlertSettings _alertSettings;
  Set<String> _hidden = const {};

  /// The alert types this user has hidden for themselves.
  Set<String> get hiddenTypes => _hidden;

  Future<void> setHiddenTypes(Set<String> types) =>
      _prefs.setHiddenAlertTypes(types);

  /// The organisation's alert settings with this user's hidden types added.
  AlertSettings get effectiveSettings => _hidden.isEmpty
      ? _alertSettings
      : _alertSettings.copyWith(
          disabledTypes: {..._alertSettings.disabledTypes, ..._hidden});
  static const _service = AlertService();
  static const _prefsName = 'alerts';

  /// Dismissed alerts are forgotten after this long (their keys are specific
  /// to an occurrence, so they'd never match again anyway).
  static const keepDismissed = Duration(days: 180);

  final StampedMemo _memo = StampedMemo();
  String? _uid;
  Map<String, DateTime> _dismissed = {};
  Map<String, DateTime> _snoozedUntil = {};

  /// Every alert for the loaded data, most urgent first.
  List<AppAlert> alertsFor(
    DataController data, {
    required bool demoMode,
    DateTime? now,
  }) {
    final n = now ?? DateTime.now();
    final settings = effectiveSettings;
    return _memo.get(
      data.version,
      (AppDate.iso(n), demoMode, data.warnings.join('\n'), settings),
      () => _service.build(
        customers: data.customers,
        campaigns: data.campaigns,
        orders: data.orders,
        expenses: data.expenses,
        products: data.products,
        warnings: List.of(data.warnings),
        demoMode: demoMode,
        now: n,
        currencyOf: (id) => data.businessById(id)?.currency ?? CurrencyCode.inr,
        settings: settings,
        goals: data.goals,
      ),
    );
  }

  AlertState stateOf(AppAlert alert, {DateTime? now}) {
    if (_dismissed.containsKey(alert.key)) return AlertState.dismissed;
    final until = _snoozedUntil[alert.key];
    if (until != null && until.isAfter(now ?? DateTime.now())) {
      return AlertState.snoozed;
    }
    return AlertState.active;
  }

  DateTime? snoozedUntil(AppAlert alert) => _snoozedUntil[alert.key];

  /// [alerts] that are neither dismissed nor snoozed.
  List<AppAlert> active(List<AppAlert> alerts, {DateTime? now}) => [
        for (final a in alerts)
          if (stateOf(a, now: now) == AlertState.active) a,
      ];

  /// What the bell's badge counts: active alerts, informational ones aside.
  int badgeCount(List<AppAlert> alerts, {DateTime? now}) => active(alerts,
          now: now)
      .where((a) => a.severity != AlertSeverity.info)
      .length;

  Future<void> dismiss(Iterable<String> keys, {DateTime? now}) {
    final at = now ?? DateTime.now();
    for (final k in keys) {
      _dismissed[k] = at;
      _snoozedUntil.remove(k);
    }
    return _save();
  }

  Future<void> snooze(String key, Duration duration, {DateTime? now}) {
    _snoozedUntil[key] = (now ?? DateTime.now()).add(duration);
    _dismissed.remove(key);
    return _save();
  }

  /// Brings a dismissed or snoozed alert back.
  Future<void> restore(String key) {
    _dismissed.remove(key);
    _snoozedUntil.remove(key);
    return _save();
  }

  void _onPrefs() {
    if (_prefs.uid == _uid) {
      final hidden = _prefs.hiddenAlertTypes;
      if (setEquals(hidden, _hidden)) return;
      _hidden = hidden;
    } else {
      _load();
    }
    notifyListeners();
  }

  /// The organisation's alert settings; with anomaly detection switched off,
  /// unusual-spend alerts go too.
  AlertSettings _orgAlerts() {
    final s = _settings?.settings;
    if (s == null) return const AlertSettings();
    if (s.features.isOn(AppFeature.anomalies)) return s.alerts;
    return s.alerts.copyWith(
        disabledTypes: {...s.alerts.disabledTypes, AlertType.unusualSpend.name});
  }

  void _onSettings() {
    final next = _orgAlerts();
    if (next == _alertSettings) return;
    _alertSettings = next;
    notifyListeners();
  }

  void _load({DateTime? now}) {
    _uid = _prefs.uid;
    _hidden = _prefs.hiddenAlertTypes;
    final n = now ?? DateTime.now();
    final json = _prefs.readJson(_prefsName);
    Map<String, DateTime> read(String name, bool Function(DateTime) keep) {
      final raw = json is Map ? json[name] : null;
      final result = <String, DateTime>{};
      if (raw is! Map) return result;
      for (final MapEntry(:key, :value) in raw.entries) {
        final date = value is String ? DateTime.tryParse(value) : null;
        if (key is String && date != null && keep(date)) result[key] = date;
      }
      return result;
    }

    _dismissed = read('dismissed', (d) => n.difference(d) < keepDismissed);
    _snoozedUntil = read('snoozed', (d) => d.isAfter(n));
  }

  Future<void> _save() async {
    notifyListeners();
    await _prefs.writeJson(
      _prefsName,
      {
        'dismissed': {
          for (final e in _dismissed.entries)
            e.key: e.value.toIso8601String(),
        },
        'snoozed': {
          for (final e in _snoozedUntil.entries)
            e.key: e.value.toIso8601String(),
        },
      },
      notify: false,
    );
  }

  @override
  void dispose() {
    _prefs.removeListener(_onPrefs);
    _settings?.removeListener(_onSettings);
    super.dispose();
  }
}
