import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:salesforce_business_manager/data/demo_seed.dart';
import 'package:salesforce_business_manager/screens/users/users_screen.dart';
import 'package:salesforce_business_manager/state/app_state.dart';
import 'package:salesforce_business_manager/state/data_controller.dart';
import 'package:salesforce_business_manager/state/filter_controller.dart';
import 'package:salesforce_business_manager/state/user_prefs.dart';
import 'package:salesforce_business_manager/widgets/layout/kpi_strip.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// [child] with the app's state, signed in as the demo owner on demo data.
/// (A bare theme: the real one fetches Inter, which tests can't.)
Future<DataController> _pump(WidgetTester tester, Widget Function() child,
    {required double width, double height = 2400}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({});
  late AppState appState;
  late DataController data;
  await tester.runAsync(() async {
    appState = await AppState.create();
    await appState.signIn(DemoSeed.ownerEmail, DemoSeed.password);
    // The profile lands just after sign-in; a load before it is discarded.
    while (appState.repository.currentUser == null) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
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
    ],
    child: MaterialApp(home: Scaffold(body: Builder(builder: (_) => child()))),
  ));
  await tester.pumpAndSettle();
  return data;
}

void main() {
  for (final width in [400.0, 1280.0]) {
    testWidgets('users screen shows KPIs and the user grid at $width px',
        (tester) async {
      await _pump(tester, () => const UsersScreen(), width: width);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(KpiStrip), findsOneWidget);
      expect(find.text('Pending requests'), findsOneWidget);
      expect(find.text('Add User'), findsWidgets);
    });
  }

  testWidgets('Add User opens the three-section form', (tester) async {
    await _pump(tester, () => const UsersScreen(), width: 1280);
    await tester.tap(find.text('Add User').first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Account'), findsWidgets);
    expect(find.text('Role & businesses'), findsWidgets);
    expect(find.text('Permissions'), findsWidgets);
  });

  testWidgets('Disabled quick filter narrows the grid', (tester) async {
    await _pump(tester, () => const UsersScreen(), width: 1280);
    await tester.tap(find.text('Disabled').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('owner row is read-only with a lock', (tester) async {
    await _pump(tester, () => const UsersScreen(), width: 1280);
    expect(find.byIcon(Icons.lock_outline), findsWidgets);
  });
}
