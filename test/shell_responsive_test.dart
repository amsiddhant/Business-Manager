import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:salesforce_business_manager/core/routing/app_routes.dart';
import 'package:salesforce_business_manager/core/routing/nav_registry.dart';
import 'package:salesforce_business_manager/data/demo_seed.dart';
import 'package:salesforce_business_manager/state/app_state.dart';
import 'package:salesforce_business_manager/state/data_controller.dart';
import 'package:salesforce_business_manager/state/filter_controller.dart';
import 'package:salesforce_business_manager/state/theme_controller.dart';
import 'package:salesforce_business_manager/state/user_prefs.dart';
import 'package:salesforce_business_manager/widgets/command_palette/command_palette.dart';
import 'package:salesforce_business_manager/widgets/layout/app_shell.dart';
import 'package:salesforce_business_manager/widgets/layout/app_sidebar.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The real shell around stand-in pages, signed in as the demo owner.
/// (A bare theme: the real one fetches Inter, which tests can't.)
Future<void> _pumpShell(
  WidgetTester tester, {
  required double width,
  double height = 900,
  double textScale = 1,
}) async {
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

  final router = GoRouter(
    initialLocation: Routes.dashboard,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (_, state, shell) =>
            AppShell(navigationShell: shell, location: state.uri.toString()),
        branches: [
          for (final r in kShellBranches)
            StatefulShellBranch(routes: [
              GoRoute(path: r, builder: (_, _) => Text('page $r')),
            ]),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);

  final userPrefs = UserPrefs(appState.prefs)
    ..bindUser(appState.currentUser?.uid);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<AppState>.value(value: appState),
      ChangeNotifierProvider<DataController>.value(value: data),
      ChangeNotifierProvider(create: (_) => FilterController()),
      ChangeNotifierProvider<UserPrefs>.value(value: userPrefs),
      ChangeNotifierProvider(
          create: (_) => ThemeController(appState.prefs, userPrefs)),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

AppSidebar? _sidebar(WidgetTester tester) {
  final found = find.byType(AppSidebar);
  return found.evaluate().isEmpty ? null : tester.widget<AppSidebar>(found);
}

void main() {
  testWidgets('phone: bottom navigation, no sidebar', (tester) async {
    await _pumpShell(tester, width: 400, height: 820);
    expect(tester.takeException(), isNull);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(AppSidebar), findsNothing);
    expect(find.text('page ${Routes.dashboard}'), findsOneWidget);
  });

  testWidgets('tablet: icon rail, no bottom bar', (tester) async {
    await _pumpShell(tester, width: 800, height: 1000);
    expect(tester.takeException(), isNull);
    expect(find.byType(NavigationBar), findsNothing);
    expect(_sidebar(tester)?.collapsed, isTrue);
  });

  testWidgets('desktop: full sidebar and the search field', (tester) async {
    await _pumpShell(tester, width: 1440);
    expect(tester.takeException(), isNull);
    expect(find.byType(NavigationBar), findsNothing);
    expect(_sidebar(tester)?.collapsed, isFalse);
    expect(find.text('Search or jump to…'), findsOneWidget);
  });

  testWidgets('desktop: the sidebar opens a section', (tester) async {
    await _pumpShell(tester, width: 1440);
    await tester.tap(find.text('Orders').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('page ${Routes.orders}'), findsOneWidget);
  });

  testWidgets('Ctrl+K opens the command palette', (tester) async {
    await _pumpShell(tester, width: 1440);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(CommandPalette), findsOneWidget);
  });

  for (final width in [400.0, 800.0, 900.0, 1024.0, 1100.0, 1440.0]) {
    testWidgets('large text (1.3×) lays out cleanly at ${width.toInt()} px',
        (tester) async {
      await _pumpShell(tester, width: width, textScale: 1.3);
      expect(tester.takeException(), isNull);
    });
  }
}
