import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:salesforce_business_manager/data/demo_seed.dart';
import 'package:salesforce_business_manager/screens/settings/settings_screen.dart';
import 'package:salesforce_business_manager/screens/settings/settings_widgets.dart';
import 'package:salesforce_business_manager/state/alert_controller.dart';
import 'package:salesforce_business_manager/state/app_state.dart';
import 'package:salesforce_business_manager/state/data_controller.dart';
import 'package:salesforce_business_manager/state/filter_controller.dart';
import 'package:salesforce_business_manager/state/settings_controller.dart';
import 'package:salesforce_business_manager/state/theme_controller.dart';
import 'package:salesforce_business_manager/state/user_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Harness {
  Harness(this.appState, this.settings);
  final AppState appState;
  final SettingsController settings;
}

/// [child] with the app's state, signed in as [email] on demo data.
/// (A bare theme: the real one fetches Inter, which tests can't.)
Future<Harness> pumpAs(WidgetTester tester, Widget Function() child,
    {required String email,
    required double width,
    double height = 2400}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({});
  late AppState appState;
  late DataController data;
  await tester.runAsync(() async {
    appState = await AppState.create();
    await appState.signIn(email, DemoSeed.password);
    // The profile lands just after sign-in; a load before it is discarded.
    while (appState.repository.currentUser == null) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    data = DataController(appState.repository);
    await data.load();
  });
  final userPrefs = UserPrefs(appState.prefs)
    ..bindUser(appState.currentUser?.uid);
  final theme = ThemeController(appState.prefs, userPrefs);
  final settings = SettingsController(appState, theme);
  final alerts = AlertController(userPrefs, settings);

  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<AppState>.value(value: appState),
      ChangeNotifierProvider<DataController>.value(value: data),
      ChangeNotifierProvider(create: (_) => FilterController()),
      ChangeNotifierProvider<UserPrefs>.value(value: userPrefs),
      ChangeNotifierProvider<ThemeController>.value(value: theme),
      ChangeNotifierProvider<SettingsController>.value(value: settings),
      ChangeNotifierProvider<AlertController>.value(value: alerts),
    ],
    child: MaterialApp(home: Scaffold(body: Builder(builder: (_) => child()))),
  ));
  await tester.pumpAndSettle();
  return Harness(appState, settings);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('editing the app name and saving persists it', (tester) async {
    final h = await pumpAs(tester, () => const SettingsScreen(),
        email: DemoSeed.ownerEmail, width: 1280);
    await tester.tap(find.text('Branding').first);
    await tester.pumpAndSettle();
    expect(find.text('Unsaved changes'), findsNothing);

    await tester.enterText(find.byType(TextFormField).first, 'Acme Traders');
    await tester.pumpAndSettle();
    expect(find.text('Unsaved changes'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await _settle(tester);
    expect(find.text('Unsaved changes'), findsNothing);
    expect(h.appState.appName, 'Acme Traders');

    final fresh = SettingsController(
        h.appState, ThemeController(h.appState.prefs, UserPrefs(h.appState.prefs)));
    await tester.runAsync(fresh.load);
    expect(fresh.settings.branding.appName, 'Acme Traders');
  });

  testWidgets('discard puts the saved values back', (tester) async {
    await pumpAs(tester, () => const SettingsScreen(),
        email: DemoSeed.ownerEmail, width: 1280);
    await tester.tap(find.text('Branding').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Temp name');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('Unsaved changes'), findsNothing);
    expect(find.text('Temp name'), findsNothing);
  });

  testWidgets('a module switch plus Save updates the modules',
      (tester) async {
    final h = await pumpAs(tester, () => const SettingsScreen(),
        email: DemoSeed.ownerEmail, width: 1280);
    await tester.tap(find.text('Modules').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Hiding a module only hides'), findsOneWidget);

    final ordersSwitch = find.descendant(
        of: find.widgetWithText(SettingSwitch, 'Orders'),
        matching: find.byType(Switch));
    await tester.tap(ordersSwitch);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await _settle(tester);
    expect(h.settings.settings.modules.isEnabled('/orders'), isFalse);
  });

  testWidgets('the dashboard headline picker enforces exactly four',
      (tester) async {
    await pumpAs(tester, () => const SettingsScreen(),
        email: DemoSeed.ownerEmail, width: 1280);
    await tester.tap(find.text('Dashboard').first);
    await tester.pumpAndSettle();

    List<FilterChip> chips() => tester
        .widgetList<FilterChip>(find.byType(FilterChip))
        .toList();
    expect(chips().where((c) => c.selected), hasLength(4));
    // With four picked, the rest can't be added.
    expect(chips().where((c) => !c.selected && c.onSelected != null), isEmpty);

    // Drop one: a note asks for one more, and nothing is saved yet.
    await tester.tap(find.byWidget(chips().firstWhere((c) => c.selected)));
    await tester.pumpAndSettle();
    expect(find.textContaining('3 of 4 selected'), findsOneWidget);
    expect(chips().where((c) => !c.selected && c.onSelected != null),
        isNotEmpty);
  });

  testWidgets('owner sees Users and access with a rebuild button',
      (tester) async {
    await pumpAs(tester, () => const SettingsScreen(),
        email: DemoSeed.ownerEmail, width: 1280);
    await tester.tap(find.text('Users and access').first);
    await tester.pumpAndSettle();
    expect(find.text('Rebuild sign-in index'), findsOneWidget);
  });

  testWidgets('owner sees diagnostics for the session', (tester) async {
    await pumpAs(tester, () => const SettingsScreen(),
        email: DemoSeed.ownerEmail, width: 1280);
    await tester.tap(find.text('Diagnostics').first);
    await tester.pumpAndSettle();
    expect(find.text('This session'), findsOneWidget);
    expect(find.text('Demo (this browser)'), findsOneWidget);
    expect(find.text('Records loaded'), findsOneWidget);
    expect(find.text('Nothing to report.'), findsOneWidget);
  });

  testWidgets('admins do not see diagnostics', (tester) async {
    await pumpAs(tester, () => const SettingsScreen(),
        email: DemoSeed.adminEmail, width: 1280);
    expect(find.text('Diagnostics'), findsNothing);
  });
}
