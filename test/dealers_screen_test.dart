import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:salesforce_business_manager/core/enums.dart';
import 'package:salesforce_business_manager/core/utils/money.dart';
import 'package:salesforce_business_manager/data/demo_seed.dart';
import 'package:salesforce_business_manager/models/dealer.dart';
import 'package:salesforce_business_manager/screens/dealers/dealer_detail_screen.dart';
import 'package:salesforce_business_manager/screens/dealers/dealers_screen.dart';
import 'package:salesforce_business_manager/services/profit_calculation_service.dart';
import 'package:salesforce_business_manager/services/summaries/dealer_summaries.dart';
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
  test('summariseDealers counts statuses and annualises active costs', () {
    Dealer dealer(String id, int cost, RecurrenceFrequency f,
            {EntityStatus status = EntityStatus.active, String url = ''}) =>
        Dealer(
          id: id,
          businessId: 'B1',
          name: id,
          cost: Money.fromMajor(cost),
          costFrequency: f,
          status: status,
          url: url,
        );
    final list = [
      dealer('D1', 1000, RecurrenceFrequency.monthly, url: 'a.com'),
      dealer('D2', 500, RecurrenceFrequency.oneTime),
      dealer('D3', 7000, RecurrenceFrequency.monthly,
          status: EntityStatus.inactive),
    ];
    const service = ProfitCalculationService();
    final s = service.summariseDealers(list);
    expect(s.count, 3);
    expect(s.activeCount, 2);
    expect(s.inactiveCount, 1);
    expect(s.withWebsite, 1);
    expect(s.annualCost, Money.fromMajor(12500));
    expect(service.summariseDealers(const []).annualCost, Money.zero);
  });

  for (final width in [400.0, 1280.0]) {
    testWidgets('dealers list shows its figures, filters and rows at $width px',
        (tester) async {
      final data =
          await _pump(tester, () => const DealersScreen(), width: width);
      expect(tester.takeException(), isNull);
      expect(find.text('Dealers'), findsWidgets);
      expect(find.byType(KpiStrip), findsOneWidget);
      expect(find.text('Annual cost'), findsWidgets);
      expect(find.text(EntityStatus.active.label), findsWidgets);
      expect(find.text('Add Dealer'), findsOneWidget);
      expect(find.text(data.dealersFor(null).first.name), findsWidgets);
    });

    testWidgets('dealer detail shows the header, figures and linked expense '
        'at $width px', (tester) async {
      await _pump(tester, () => const DealerDetailScreen(dealerId: 'DLR-00001'),
          width: width);
      expect(tester.takeException(), isNull);
      expect(find.text('Shenzhen Direct Supply'), findsWidgets);
      expect(find.text('Annualised'), findsWidgets);
      expect(find.text('Linked Expense'), findsWidgets);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Website'), findsOneWidget);
      expect(find.text('More'), findsOneWidget);
    });
  }

  testWidgets('the dealer list offers the website action per row',
      (tester) async {
    await _pump(tester, () => const DealersScreen(), width: 1280);
    expect(find.byTooltip('Open website'), findsWidgets);
    expect(find.byTooltip('Edit'), findsWidgets);
    expect(find.byTooltip('Delete'), findsWidgets);
  });

  testWidgets('the dealer form keeps the mirror line', (tester) async {
    await _pump(tester, () => const DealersScreen(), width: 1280);
    await tester.tap(find.text('Add Dealer'));
    await tester.pumpAndSettle();

    expect(find.text('Cost & schedule'), findsWidgets);
    expect(find.textContaining('mirrored automatically into Business'),
        findsOneWidget);
    expect(find.text('Dealer URL', findRichText: true), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('deleting a dealer warns about its linked expense',
      (tester) async {
    await _pump(tester, () => const DealerDetailScreen(dealerId: 'DLR-00001'),
        width: 1280);

    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete dealer'));
    await tester.pumpAndSettle();

    expect(find.text('Delete dealer?'), findsOneWidget);
    expect(find.textContaining('Its linked expense will also be removed'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a quick filter narrows the list to that status',
      (tester) async {
    await _pump(tester, () => const DealersScreen(), width: 1280);
    await tester.tap(find.text(EntityStatus.inactive.label).last);
    await tester.pumpAndSettle();
    // Both demo dealers are active.
    expect(find.text('Shenzhen Direct Supply'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a missing dealer shows not found with a way back',
      (tester) async {
    await _pump(tester, () => const DealerDetailScreen(dealerId: 'NOPE'),
        width: 1280);
    expect(find.text('Dealer not found'), findsOneWidget);
    expect(find.text('Back to Dealers'), findsOneWidget);
  });
}
