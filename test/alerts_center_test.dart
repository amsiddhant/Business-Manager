import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:salesforce_business_manager/data/demo_seed.dart';
import 'package:salesforce_business_manager/screens/alerts/alerts_screen.dart';
import 'package:salesforce_business_manager/state/alert_controller.dart';
import 'package:salesforce_business_manager/state/app_state.dart';
import 'package:salesforce_business_manager/state/data_controller.dart';
import 'package:salesforce_business_manager/state/filter_controller.dart';
import 'package:salesforce_business_manager/state/user_prefs.dart';
import 'package:salesforce_business_manager/widgets/alerts/alert_tile.dart';
import 'package:salesforce_business_manager/widgets/alerts/alerts_bell.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// [child] with the app's state, signed in as the demo owner on demo data.
Future<void> _pump(WidgetTester tester, Widget child,
    {required double width, double height = 1000}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({});
  late AppState appState;
  late DataController data;
  await tester.runAsync(() async {
    appState = await AppState.create();
    await appState.signIn(DemoSeed.ownerEmail, DemoSeed.password);
    data = DataController(appState.repository);
    await data.load();
  });
  final userPrefs = UserPrefs(appState.prefs)
    ..bindUser(appState.currentUser?.uid);

  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<AppState>.value(value: appState),
      ChangeNotifierProvider<DataController>.value(value: data),
      ChangeNotifierProvider(create: (_) => FilterController()),
      ChangeNotifierProvider<UserPrefs>.value(value: userPrefs),
      ChangeNotifierProvider(create: (_) => AlertController(userPrefs)),
    ],
    child: MaterialApp(home: child),
  ));
  await tester.pump(const Duration(milliseconds: 400));
}

/// Lets a route or snackbar start its transition, then finish it.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

Finder _demoTile() => find.ancestor(
    of: find.text('Demo mode active'), matching: find.byType(AlertTile));

void main() {
  testWidgets('dismiss hides an alert and Undo brings it back',
      (tester) async {
    await _pump(tester, const Scaffold(body: AlertsScreen()), width: 1280);
    expect(tester.takeException(), isNull);
    expect(_demoTile(), findsOneWidget);

    await tester.tap(find.descendant(
        of: _demoTile(), matching: find.byTooltip('Dismiss')));
    await _settle(tester);
    expect(_demoTile(), findsNothing);

    await tester.tap(find.text('Undo'));
    await _settle(tester);
    expect(_demoTile(), findsOneWidget);
  });

  testWidgets('the alerts center lays out on a phone', (tester) async {
    await _pump(tester, const Scaffold(body: AlertsScreen()),
        width: 375, height: 800);
    expect(tester.takeException(), isNull);
    expect(_demoTile(), findsOneWidget);
  });

  testWidgets('the bell opens the alerts panel', (tester) async {
    await _pump(
        tester,
        Scaffold(appBar: AppBar(actions: const [AlertsBell()])),
        width: 1280);
    await tester.tap(find.byType(AlertsBell));
    await _settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Alerts center'), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await _settle(tester);
    expect(find.text('Alerts center'), findsNothing);
  });
}
