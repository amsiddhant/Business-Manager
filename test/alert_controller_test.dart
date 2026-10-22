import 'package:flutter_test/flutter_test.dart';
import 'package:salesforce_business_manager/services/alert_service.dart';
import 'package:salesforce_business_manager/state/alert_controller.dart';
import 'package:salesforce_business_manager/state/user_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

AppAlert _alert(String key, [AlertSeverity severity = AlertSeverity.medium]) =>
    AppAlert(
      key: key,
      type: AlertType.campaignEnding,
      severity: severity,
      title: key,
      message: key,
    );

void main() {
  late UserPrefs prefs;
  final now = DateTime(2026, 10, 22, 9);
  final a = _alert('a'), b = _alert('b'), info = _alert('i', AlertSeverity.info);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = UserPrefs(await SharedPreferences.getInstance())..bindUser('alice');
  });

  test('dismissing hides an alert and survives a reload', () async {
    final c = AlertController(prefs);
    await c.dismiss(['a'], now: now);
    expect(c.stateOf(a, now: now), AlertState.dismissed);
    expect(c.active([a, b], now: now), [b]);

    final reloaded = AlertController(prefs);
    expect(reloaded.stateOf(a, now: now), AlertState.dismissed);
  });

  test('a snooze runs out', () async {
    final c = AlertController(prefs);
    await c.snooze('a', const Duration(days: 1), now: now);
    expect(c.stateOf(a, now: now), AlertState.snoozed);
    expect(c.stateOf(a, now: now.add(const Duration(days: 2))),
        AlertState.active);
  });

  test('restore brings an alert back', () async {
    final c = AlertController(prefs);
    await c.dismiss(['a'], now: now);
    await c.restore('a');
    expect(c.stateOf(a, now: now), AlertState.active);
    expect(AlertController(prefs).stateOf(a, now: now), AlertState.active);
  });

  test('the badge leaves informational alerts out', () {
    expect(AlertController(prefs).badgeCount([a, b, info], now: now), 2);
  });

  test('dismissals are kept per user', () async {
    final c = AlertController(prefs);
    await c.dismiss(['a'], now: now);
    prefs.bindUser('bob');
    expect(c.stateOf(a, now: now), AlertState.active);
    prefs.bindUser('alice');
    expect(c.stateOf(a, now: now), AlertState.dismissed);
  });
}
