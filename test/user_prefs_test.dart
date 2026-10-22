import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salesforce_business_manager/core/theme/theme_x.dart';
import 'package:salesforce_business_manager/state/user_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  test('preferences are kept per user', () async {
    final p = UserPrefs(prefs)..bindUser('alice');
    await p.setSidebarCollapsed(true);
    await p.setDensity(AppDensity.compact);
    await p.setReduceMotion(true);

    p.bindUser('bob');
    expect(p.sidebarCollapsed, isFalse);
    expect(p.density, isNull);
    expect(p.reduceMotion, isFalse);

    p.bindUser('alice');
    expect(p.sidebarCollapsed, isTrue);
    expect(p.density, AppDensity.compact);
    expect(p.reduceMotion, isTrue);
  });

  test('binding notifies only when the user changes', () {
    final p = UserPrefs(prefs);
    var n = 0;
    p.addListener(() => n++);
    p.bindUser(null);
    p.bindUser('');
    expect(n, 0, reason: 'null and empty are both "signed out"');
    p.bindUser('alice');
    p.bindUser('alice');
    expect(n, 1);
    expect(p.uid, 'alice');
  });

  test("the last theme picked on this device styles the sign-in screen",
      () async {
    final p = UserPrefs(prefs)..bindUser('alice');
    await p.setThemeMode(ThemeMode.dark);
    expect(p.themeMode, ThemeMode.dark);

    p.bindUser(null);
    expect(p.themeMode, ThemeMode.dark, reason: 'device fallback');

    p.bindUser('bob');
    expect(p.themeMode, isNull, reason: 'bob never picked one');

    p.bindUser('alice');
    await p.setThemeMode(null);
    expect(p.themeMode, isNull);
    p.bindUser(null);
    expect(p.themeMode, isNull, reason: 'reset clears the device copy too');
  });

  test('favourites toggle on and off, keeping their labels', () async {
    final p = UserPrefs(prefs)..bindUser('alice');
    await p.toggleFavourite('/orders/ORD-000001', 'Order ORD-000001');
    await p.toggleFavourite('/customers/CUST-00002', 'Acme');
    expect(p.isFavourite('/orders/ORD-000001'), isTrue);
    expect([for (final f in p.favourites) f.label],
        ['Order ORD-000001', 'Acme']);

    await p.toggleFavourite('/orders/ORD-000001', 'ignored');
    expect(p.isFavourite('/orders/ORD-000001'), isFalse);
    expect(p.favourites.single.path, '/customers/CUST-00002');
  });

  test('unreadable stored favourites are ignored, not fatal', () async {
    final p = UserPrefs(prefs)..bindUser('alice');
    await prefs.setString('sbm.u.alice.favourites', '{broken');
    expect(p.favourites, isEmpty);
    await p.writeJson('favourites', [
      {'path': '/orders', 'label': 'Orders'},
      {'nope': true},
      42,
    ]);
    expect(p.favourites.single.label, 'Orders');
  });

  test('recent commands: newest first, no duplicates, capped', () async {
    final p = UserPrefs(prefs)..bindUser('alice');
    for (var i = 0; i < 12; i++) {
      await p.pushRecentCommand('cmd$i');
    }
    await p.pushRecentCommand('cmd5');
    expect(p.recentCommands.length, UserPrefs.maxRecent);
    expect(p.recentCommands.first, 'cmd5');
    expect(p.recentCommands.where((c) => c == 'cmd5').length, 1);
    expect(p.recentCommands[1], 'cmd11');
  });

  test('scope round-trips as JSON without notifying', () async {
    final p = UserPrefs(prefs)..bindUser('alice');
    var n = 0;
    p.addListener(() => n++);
    await p.setScope({'business': 'BIZ-00001', 'fy': 2026});
    expect(p.scope, {'business': 'BIZ-00001', 'fy': 2026});
    expect(n, 0);
  });

  test('last login ID is trimmed, and blank clears it', () async {
    final p = UserPrefs(prefs);
    await p.setLastLoginId('  owner ');
    expect(p.lastLoginId, 'owner');
    p.bindUser('alice');
    expect(p.lastLoginId, 'owner', reason: 'device-wide, not per user');
    await p.setLastLoginId('   ');
    expect(p.lastLoginId, isNull);
  });
}
