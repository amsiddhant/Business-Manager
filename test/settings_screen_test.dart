import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:salesforce_business_manager/data/demo_seed.dart';
import 'package:salesforce_business_manager/screens/settings/settings_screen.dart';
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

void main() {
  for (final width in [400.0, 1280.0]) {
    testWidgets('owner sees Personal, Organisation and System at $width px',
        (tester) async {
      await pumpAs(tester, () => const SettingsScreen(),
          email: DemoSeed.ownerEmail, width: width);
      expect(tester.takeException(), isNull);
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Personal'), findsOneWidget);
      expect(find.text('Organisation'), findsOneWidget);
      expect(find.text('System'), findsOneWidget);
      expect(find.text('Firebase'), findsOneWidget);
      expect(find.text('Danger zone'), findsOneWidget);
    });
  }

  testWidgets('admin sees Organisation but not System', (tester) async {
    await pumpAs(tester, () => const SettingsScreen(),
        email: DemoSeed.adminEmail, width: 1280);
    expect(find.text('Personal'), findsOneWidget);
    expect(find.text('Organisation'), findsOneWidget);
    expect(find.text('System'), findsNothing);
    expect(find.text('Danger zone'), findsNothing);
    expect(find.text('Firebase'), findsNothing);
  });

  testWidgets('a regular user sees only Personal', (tester) async {
    await pumpAs(tester, () => const SettingsScreen(),
        email: DemoSeed.userEmail, width: 1280);
    expect(find.text('Personal'), findsOneWidget);
    expect(find.text('Organisation'), findsNothing);
    expect(find.text('System'), findsNothing);
    expect(find.text('Branding'), findsNothing);
  });

  testWidgets('search narrows the list', (tester) async {
    await pumpAs(tester, () => const SettingsScreen(),
        email: DemoSeed.ownerEmail, width: 1280);
    await tester.enterText(find.byType(TextField).first, 'currency');
    await tester.pumpAndSettle();
    expect(find.text('Defaults'), findsWidgets);
    expect(find.text('Shortcuts'), findsNothing);
    await tester.enterText(find.byType(TextField).first, 'zzzz');
    await tester.pumpAndSettle();
    expect(find.textContaining('No settings match'), findsOneWidget);
  });
}
