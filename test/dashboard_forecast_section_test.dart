import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:salesforce_business_manager/core/enums.dart';
import 'package:salesforce_business_manager/core/utils/date_utils.dart';
import 'package:salesforce_business_manager/core/utils/money.dart';
import 'package:salesforce_business_manager/data/demo_seed.dart';
import 'package:salesforce_business_manager/models/app_settings.dart';
import 'package:salesforce_business_manager/screens/dashboard/dashboard_screen.dart';
import 'package:salesforce_business_manager/screens/dashboard/widgets/animated_number.dart';
import 'package:salesforce_business_manager/screens/dashboard/widgets/dashboard_registry.dart';
import 'package:salesforce_business_manager/screens/dashboard/widgets/entrance.dart';
import 'package:salesforce_business_manager/screens/dashboard/widgets/forecast_card.dart';
import 'package:salesforce_business_manager/services/profit_calculation_service.dart';
import 'package:salesforce_business_manager/services/smart/forecast_service.dart';
import 'package:salesforce_business_manager/state/alert_controller.dart';
import 'package:salesforce_business_manager/state/app_state.dart';
import 'package:salesforce_business_manager/state/data_controller.dart';
import 'package:salesforce_business_manager/state/filter_controller.dart';
import 'package:salesforce_business_manager/state/smart_insights_controller.dart';
import 'package:salesforce_business_manager/state/user_prefs.dart';
import 'package:salesforce_business_manager/view_models/dashboard_view_model.dart';
import 'package:salesforce_business_manager/widgets/charts/chart_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A stand-in for the smart controller: answers with what it is given.
class _FakeSmart extends ChangeNotifier implements SmartInsightsController {
  _FakeSmart({this.forecast, this.projection});

  final SmartForecast? forecast;
  final PeriodProjection? projection;
  int shown = 0;

  @override
  SmartForecast? forecastFor(String? businessId, {DateTime? now}) => forecast;

  @override
  PeriodProjection? projectionFor(String? businessId,
          {required ProfitSummary toDate,
          required DateRange range,
          DateTime? now}) =>
      projection;

  @override
  void dashboardShown() => shown++;

  @override
  int get revision => 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

SeriesForecast _series(List<double> mean,
        {double error = 0.12, ForecastModel model = ForecastModel.linear}) =>
    SeriesForecast(
      mean: mean,
      lower: [for (final m in mean) m * 0.85],
      upper: [for (final m in mean) m * 1.15],
      error: error,
      model: model,
      points: 12,
    );

SmartForecast _forecast({ForecastModel model = ForecastModel.linear}) {
  final n = DateTime.now();
  return SmartForecast(
    businessId: null,
    firstMonth: DateTime(n.year, n.month, 1),
    history: [
      for (var i = 0; i < 12; i++)
        TimeSeriesPoint(
          label: 'M$i',
          revenue: Money.fromMajor(100000),
          productCost: Money.zero,
          marketingCost: Money.zero,
          operatingExpenses: Money.zero,
          orders: 1,
        ),
    ],
    revenue: _series([200000, 210000, 220000], model: model),
    netProfit: _series([40000, 42000, 44000], error: 0.18, model: model),
  );
}

Future<(DataController, FilterController)> _pump(
  WidgetTester tester, {
  required SmartInsightsController? smart,
  double width = 1440,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 9000);
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({});
  late AppState appState;
  late DataController data;
  await tester.runAsync(() async {
    appState = await AppState.create();
    await appState.signIn(DemoSeed.ownerEmail, DemoSeed.password);
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
      if (smart != null)
        ChangeNotifierProvider<SmartInsightsController>.value(value: smart),
    ],
    child: const MaterialApp(home: Scaffold(body: DashboardScreen())),
  ));
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

  group('registry', () {
    final names = [for (final s in DashboardSectionId.values) s.name];

    test('forecast follows profit by default', () {
      expect(names.indexOf('forecast'), names.indexOf('profit') + 1);
      expect(const DashboardSettings().arrange(names).indexOf('forecast'),
          names.indexOf('profit') + 1);
    });

    test('a saved order without forecast still includes it', () {
      final saved = DashboardSettings(
          order: [for (final n in names.reversed) if (n != 'forecast') n]);
      final shown = saved.arrange(names);
      expect(shown, contains('forecast'));
      expect(shown, hasLength(names.length));
      expect(saved.isVisible('forecast'), isTrue);
    });
  });

  testWidgets('without enough history it says when forecasts appear',
      (tester) async {
    final (data, filter) = await _pump(tester, smart: _FakeSmart());
    expect(tester.takeException(), isNull);
    final months = DashboardViewModel.of(data, filter).historyMonths;
    expect(find.text('Next 3 months'), findsWidgets);
    expect(
      find.textContaining(months < 6
          ? 'Forecasts appear after 6 months of history'
          : 'Forecast hidden: past months were too uneven'),
      findsOneWidget,
    );
  });

  testWidgets('with a forecast it lists each month, range and accuracy',
      (tester) async {
    final smart = _FakeSmart(forecast: _forecast());
    await _pump(tester, smart: smart);
    expect(tester.takeException(), isNull);

    final now = DateTime.now();
    for (var i = 0; i < 3; i++) {
      expect(
          find.text(AppDate.monthYear(DateTime(now.year, now.month + i, 1))),
          findsWidgets);
    }
    final card = find.byType(ForecastCard);
    expect(card, findsOneWidget);
    // ₹2L (0.85 to 1.15 of it) with its range.
    expect(
        find.descendant(of: card, matching: find.textContaining(' to ')),
        findsAtLeastNWidgets(3));
    expect(
        find.descendant(
            of: card,
            matching: find.text('Past months were typically within ±12% for '
                'revenue and ±18% for net profit.')),
        findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('Method: Linear trend')),
        findsOneWidget);
    // Built-in model: no badge.
    expect(find.descendant(of: card, matching: find.text('Enhanced')),
        findsNothing);

    // The table has the ranges too.
    await tester.tap(find.descendant(
        of: card, matching: find.byTooltip('View as table')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Revenue range (80%)'), findsWidgets);
    await tester.tap(find.descendant(
        of: card, matching: find.byTooltip('View as chart')));
    await tester.pump(const Duration(milliseconds: 500));

    // And how it is worked out.
    await tester.tap(find.descendant(
        of: card, matching: find.byTooltip('How is this calculated?')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Nothing is sent anywhere'), findsOneWidget);
    expect(find.textContaining('12 completed months'), findsOneWidget);
  });

  testWidgets('the neural model earns an Enhanced badge', (tester) async {
    await _pump(tester,
        smart: _FakeSmart(forecast: _forecast(model: ForecastModel.tfjs)));
    expect(
        find.descendant(
            of: find.byType(ForecastCard), matching: find.text('Enhanced')),
        findsOneWidget);
  });

  testWidgets('the hero prefers the forecast projection, and says so',
      (tester) async {
    final projection = PeriodProjection(
      revenue: Money.fromMajor(900000),
      netProfit: Money.fromMajor(200000),
      revenuePerDay: Money.zero,
      netProfitPerDay: Money.zero,
      elapsedDays: 100,
      totalDays: 365,
      source: ProjectionSource.forecast,
      revenueLow: Money.fromMajor(800000),
      revenueHigh: Money.fromMajor(1000000),
      netProfitLow: Money.fromMajor(150000),
      netProfitHigh: Money.fromMajor(250000),
      enhanced: true,
    );
    final (data, filter) = await _pump(
        tester, smart: _FakeSmart(forecast: _forecast(), projection: projection));
    // The default period is this financial year, which is running.
    expect(DashboardViewModel.of(data, filter).projection, isNotNull);
    expect(find.textContaining('Projected · on-device:'), findsOneWidget);
    expect(find.text('Enhanced'), findsWidgets);
    expect(find.textContaining('On pace for'), findsNothing);
  });

  testWidgets('without a smart result the run rate stays', (tester) async {
    final (data, filter) = await _pump(tester, smart: _FakeSmart());
    expect(DashboardViewModel.of(data, filter).projection, isNotNull);
    expect(find.textContaining('On pace for'), findsOneWidget);
    expect(find.textContaining('Projected · on-device:'), findsNothing);
  });

  testWidgets('the first frame tells the smart controller', (tester) async {
    final smart = _FakeSmart();
    await _pump(tester, smart: smart);
    expect(smart.shown, 1);
  });

  testWidgets('no smart controller: the dashboard still builds',
      (tester) async {
    await _pump(tester, smart: null);
    expect(tester.takeException(), isNull);
    expect(find.byType(ForecastCard), findsOneWidget);
  });

  testWidgets('different currencies are not added up', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: ForecastCard(
            currency: CurrencyCode.inr, gap: ForecastGap.mixedCurrencies),
      ),
    ));
    expect(find.textContaining('different currencies'), findsOneWidget);
  });
}
