import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:salesforce_business_manager/core/enums.dart';
import 'package:salesforce_business_manager/core/utils/date_utils.dart';
import 'package:salesforce_business_manager/core/utils/money.dart';
import 'package:salesforce_business_manager/data/demo_seed.dart';
import 'package:salesforce_business_manager/models/expense.dart';
import 'package:salesforce_business_manager/screens/reports/reports_screen.dart';
import 'package:salesforce_business_manager/services/profit_calculation_service.dart';
import 'package:salesforce_business_manager/services/summaries/reports_summaries.dart';
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
  test('expenseReportTotals annualises and counts active expenses', () {
    const service = ProfitCalculationService();
    final totals = service.expenseReportTotals([
      Expense(
        id: 'E1',
        businessId: 'B1',
        name: 'Rent',
        amount: Money.fromMajor(1000),
        frequency: RecurrenceFrequency.monthly,
      ),
      Expense(
        id: 'E2',
        businessId: 'B1',
        name: 'Old',
        amount: Money.fromMajor(500),
        frequency: RecurrenceFrequency.yearly,
        status: EntityStatus.inactive,
      ),
    ], DateRange(DateTime(2025, 1, 1), DateTime(2025, 12, 31)));
    expect(totals.count, 2);
    expect(totals.activeCount, 1);
    expect(totals.annualised, Money.fromMajor(12500));
    expect(totals.monthlyRunRate, Money.fromMajor(12500) / 12);
  });

  for (final width in [400.0, 1280.0]) {
    testWidgets('reports show five tabs, KPIs and a grid at $width px',
        (tester) async {
      await _pump(tester, () => const ReportsScreen(), width: width);
      expect(tester.takeException(), isNull);
      expect(find.byType(TabBar), findsOneWidget);
      expect(find.byType(KpiStrip), findsOneWidget);
      expect(find.text('Marketing'), findsWidgets);
      expect(find.text('Business Profitability'), findsWidgets);
    });
  }

  testWidgets('initialTab opens that report', (tester) async {
    await _pump(tester, () => const ReportsScreen(initialTab: 'marketing'),
        width: 1280);
    expect(tester.takeException(), isNull);
    final tabs = tester.widget<TabBar>(find.byType(TabBar));
    expect(tabs.controller!.index, 2);
  });

  testWidgets('switching tabs swaps the report without errors', (tester) async {
    await _pump(tester, () => const ReportsScreen(), width: 1280);
    await tester.tap(find.text('Expenses').first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(KpiStrip), findsOneWidget);
  });
}
