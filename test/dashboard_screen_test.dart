import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:salesforce_business_manager/data/demo_seed.dart';
import 'package:salesforce_business_manager/screens/dashboard/dashboard_screen.dart';
import 'package:salesforce_business_manager/screens/dashboard/widgets/animated_number.dart';
import 'package:salesforce_business_manager/screens/dashboard/widgets/dashboard_tables.dart';
import 'package:salesforce_business_manager/screens/dashboard/widgets/entrance.dart';
import 'package:salesforce_business_manager/screens/reports/reports_screen.dart';
import 'package:salesforce_business_manager/services/profit_calculation_service.dart';
import 'package:salesforce_business_manager/state/alert_controller.dart';
import 'package:salesforce_business_manager/state/app_state.dart';
import 'package:salesforce_business_manager/state/data_controller.dart';
import 'package:salesforce_business_manager/state/filter_controller.dart';
import 'package:salesforce_business_manager/state/user_prefs.dart';
import 'package:salesforce_business_manager/view_models/dashboard_view_model.dart';
import 'package:salesforce_business_manager/widgets/charts/chart_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// [child] with the app's state, signed in as the demo owner on demo data.
/// (A bare theme: the real one fetches Inter, which tests can't.)
Future<(DataController, FilterController)> _pump(
  WidgetTester tester,
  Widget child, {
  required double width,
  double height = 9000,
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
    // The profile lands just after sign-in; a load before it is discarded.
    while (appState.repository.currentUser == null) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    data = DataController(appState.repository);
    await data.load();
  });
  final filter = FilterController();
  final userPrefs = UserPrefs(appState.prefs)
    ..bindUser(appState.currentUser?.uid);

  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<AppState>.value(value: appState),
      ChangeNotifierProvider<DataController>.value(value: data),
      ChangeNotifierProvider<FilterController>.value(value: filter),
      ChangeNotifierProvider<UserPrefs>.value(value: userPrefs),
      ChangeNotifierProvider(create: (_) => AlertController(userPrefs)),
    ],
    child: MaterialApp(home: Scaffold(body: child)),
  ));
  // The one-time entrance, count-ups and chart draw-ins.
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 500));
  }
  return (data, filter);
}

void main() {
  setUp(() {
    Entrance.reset();
    AnimatedNumber.reset();
    ChartReveal.reset();
  });

  group('dashboardRows', () {
    final rows = [for (var i = 0; i < 25; i++) 'Item $i'];
    String self(String s) => s;

    test('without a search, the first ten', () {
      expect(dashboardRows(rows, '', self), rows.take(10).toList());
    });

    test('a search finds rows outside the top ten', () {
      expect(dashboardRows(rows, 'item 2', self),
          ['Item 2', 'Item 20', 'Item 21', 'Item 22', 'Item 23', 'Item 24']);
    });

    test('matches are still capped', () {
      expect(dashboardRows(rows, 'item', self, limit: 5), hasLength(5));
    });
  });

  for (final width in [400.0, 900.0, 1440.0]) {
    testWidgets('dashboard keeps every figure, chart and table at $width px',
        (tester) async {
      await _pump(tester, const DashboardScreen(), width: width);
      expect(tester.takeException(), isNull);

      for (final metric in [
        KpiMetric.revenue,
        KpiMetric.productCost,
        KpiMetric.marketingCost,
        KpiMetric.operatingExpenses,
        KpiMetric.grossProfit,
        KpiMetric.contributionProfit,
        KpiMetric.netProfit,
        KpiMetric.netMargin,
        KpiMetric.orders,
        KpiMetric.units,
      ]) {
        expect(find.text(metric.label), findsWidgets, reason: metric.label);
      }
      for (final tip in [
        'Total recognised sales revenue.',
        'Total product purchasing cost for recognised orders.',
        'Total advertising spend in the selected period.',
        'Prorated operating costs (excluding advertising).',
        'Revenue − Product Cost.',
        'Gross Profit − Marketing Cost.',
        'Revenue − Product Cost − Marketing − Operating Expenses.',
        'Net Profit / Revenue × 100.',
        'Number of recognised orders.',
        'Total quantity across recognised orders.',
      ]) {
        expect(find.byTooltip(tip), findsOneWidget, reason: tip);
      }
      for (final title in [
        'Revenue vs Expenses',
        'Expense Breakdown',
        'Revenue by Product',
        'Profit by Product',
        'Marketing Spend',
        'Orders Trend',
        'Profit Waterfall',
        'Top Products',
        'Recent Orders',
        'Campaign Performance',
      ]) {
        expect(find.text(title), findsWidgets, reason: title);
      }
    });
  }

  testWidgets('the view model is the service output for the filter',
      (tester) async {
    final (data, filter) =
        await _pump(tester, const SizedBox(), width: 800, height: 600);
    final vm = DashboardViewModel.of(data, filter);
    final expected = const ProfitCalculationService().summarise(
      orders: data.orders,
      campaigns: data.campaigns,
      expenses: data.expenses,
      range: filter.range,
    );
    expect(vm.summary.revenue, expected.revenue);
    expect(vm.summary.netProfit, expected.netProfit);
    expect(vm.summary.orderCount, expected.orderCount);
    expect(identical(DashboardViewModel.of(data, filter), vm), isTrue,
        reason: 'memoised until the data or filter changes');
  });

  testWidgets('Reports opens on the tab in its link', (tester) async {
    await _pump(tester, const ReportsScreen(initialTab: 'marketing'),
        width: 1280, height: 1000);
    expect(tester.takeException(), isNull);
    final bar = tester.widget<TabBar>(find.byType(TabBar));
    expect(bar.controller!.index, ReportsScreen.tabKeys.indexOf('marketing'));
  });
}
