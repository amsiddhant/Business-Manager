import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:salesforce_business_manager/core/enums.dart';
import 'package:salesforce_business_manager/data/demo_seed.dart';
import 'package:salesforce_business_manager/models/business.dart';
import 'package:salesforce_business_manager/screens/businesses/business_detail_screen.dart';
import 'package:salesforce_business_manager/screens/businesses/businesses_screen.dart';
import 'package:salesforce_business_manager/services/profit_calculation_service.dart';
import 'package:salesforce_business_manager/services/summaries/business_summaries.dart';
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
  test('summariseBusinesses counts each business once by state', () {
    Business b(String id,
            {EntityStatus status = EntityStatus.active,
            BusinessLifecycle lifecycle = BusinessLifecycle.active,
            DateTime? start}) =>
        Business(
            id: id,
            name: id,
            status: status,
            lifecycle: lifecycle,
            startDate: start);
    final asOf = DateTime(2026, 1, 1);
    final s = const ProfitCalculationService().summariseBusinesses([
      b('A', start: DateTime(2025, 1, 1)),
      b('B', lifecycle: BusinessLifecycle.closed),
      b('C', status: EntityStatus.inactive),
      b('D', status: EntityStatus.archived, lifecycle: BusinessLifecycle.closed),
    ], asOf);
    expect(s.total, 4);
    expect(s.trading, 1);
    expect(s.closed, 1);
    expect(s.inactive, 1);
    expect(s.archived, 1);
    expect(s.averageTenureDays, 365);
    expect(
        const ProfitCalculationService()
            .summariseBusinesses(const [], asOf)
            .averageTenureDays,
        isNull);
  });

  for (final width in [400.0, 1280.0]) {
    testWidgets('businesses list shows its figures, filters and rows at $width px',
        (tester) async {
      final data =
          await _pump(tester, () => const BusinessesScreen(), width: width);
      expect(tester.takeException(), isNull);
      expect(find.text('Businesses'), findsWidgets);
      expect(find.byType(KpiStrip), findsOneWidget);
      expect(find.text('Trading'), findsOneWidget);
      expect(find.text('Avg. tenure'), findsOneWidget);
      expect(find.text('Archived'), findsWidgets);
      expect(find.text('Add Business'), findsOneWidget);
      expect(find.text(data.businesses.first.name), findsWidgets);
    });

    testWidgets('business detail shows the header, figures and sections '
        'at $width px', (tester) async {
      late String id;
      late String name;
      await _pump(tester, () {
        return Builder(builder: (context) {
          final b = context.read<DataController>().businesses.first;
          id = b.id;
          name = b.name;
          return BusinessDetailScreen(businessId: id);
        });
      }, width: width);
      expect(tester.takeException(), isNull);
      expect(find.text(name), findsWidgets);
      expect(find.text('Net profit'), findsOneWidget);
      expect(find.text('Net margin'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('More'), findsOneWidget);
      if (width < 640) {
        expect(find.text('Overview'), findsOneWidget);
      } else {
        expect(find.text('Business Profile'), findsOneWidget);
        expect(find.text('Products'), findsWidgets);
        expect(find.text('Dealers'), findsWidgets);
        expect(find.text('Team Access'), findsOneWidget);
      }
    });
  }

  testWidgets('Add Business opens the sectioned form', (tester) async {
    await _pump(tester, () => const BusinessesScreen(), width: 1280);
    await tester.tap(find.text('Add Business'));
    await tester.pumpAndSettle();
    expect(find.text('Basics'), findsWidgets);
    expect(find.text('Ownership & dates'), findsWidgets);
    expect(find.text('Online presence'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a quick filter narrows the list to archived businesses',
      (tester) async {
    late DataController data;
    data = await _pump(tester, () => const BusinessesScreen(), width: 1280);
    final name = data.businesses.first.name;
    expect(find.text(name), findsWidgets);
    await tester.tap(find.text('Archived').first);
    await tester.pumpAndSettle();
    // No demo business is archived, so the filter empties the grid.
    expect(find.text(name), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Restore brings an archived business back to active',
      (tester) async {
    late String id;
    late DataController data;
    late AppState app;
    data = await _pump(tester, () {
      return Builder(builder: (context) {
        app = context.read<AppState>();
        id = context.read<DataController>().businesses.first.id;
        return BusinessDetailScreen(businessId: id);
      });
    }, width: 1280);
    await tester.runAsync(() async {
      await app.repository
          .archiveBusiness(id, known: data.businessById(id));
    });
    await tester.pumpAndSettle();
    expect(data.businessById(id)!.status, EntityStatus.archived);
    expect(find.textContaining('is archived'), findsOneWidget);

    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore business'));
    await tester.pumpAndSettle();
    expect(find.text('Restore business?'), findsOneWidget);
    await tester.tap(find.text('Restore').last);
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(data.businessById(id)!.status, EntityStatus.active);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a missing business shows not found with a way back',
      (tester) async {
    await _pump(tester, () => const BusinessDetailScreen(businessId: 'NOPE'),
        width: 1280);
    expect(find.text('Business not found'), findsOneWidget);
    expect(find.text('Back to Businesses'), findsOneWidget);
  });
}
