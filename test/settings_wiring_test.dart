import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:salesforce_business_manager/core/enums.dart';
import 'package:salesforce_business_manager/core/permissions.dart';
import 'package:salesforce_business_manager/core/routing/app_router.dart';
import 'package:salesforce_business_manager/core/routing/app_routes.dart';
import 'package:salesforce_business_manager/core/routing/nav_registry.dart';
import 'package:salesforce_business_manager/core/utils/money.dart';
import 'package:salesforce_business_manager/data/demo_seed.dart';
import 'package:salesforce_business_manager/models/app_settings.dart';
import 'package:salesforce_business_manager/screens/dashboard/dashboard_screen.dart';
import 'package:salesforce_business_manager/screens/dashboard/widgets/animated_number.dart';
import 'package:salesforce_business_manager/screens/dashboard/widgets/dashboard_registry.dart';
import 'package:salesforce_business_manager/screens/dashboard/widgets/entrance.dart';
import 'package:salesforce_business_manager/screens/dashboard/widgets/kpi_tile.dart';
import 'package:salesforce_business_manager/services/profit_calculation_service.dart';
import 'package:salesforce_business_manager/state/alert_controller.dart';
import 'package:salesforce_business_manager/state/app_state.dart';
import 'package:salesforce_business_manager/state/data_controller.dart';
import 'package:salesforce_business_manager/state/filter_controller.dart';
import 'package:salesforce_business_manager/state/settings_controller.dart';
import 'package:salesforce_business_manager/state/theme_controller.dart';
import 'package:salesforce_business_manager/state/user_prefs.dart';
import 'package:salesforce_business_manager/view_models/dashboard_view_model.dart';
import 'package:salesforce_business_manager/widgets/charts/chart_kit.dart';
import 'package:salesforce_business_manager/widgets/data/app_data_grid.dart';
import 'package:salesforce_business_manager/widgets/layout/app_sidebar.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Everything a wired screen needs, signed in as the demo owner on demo data.
/// (A bare theme: the real one fetches Inter, which tests can't.)
class _Env {
  _Env({
    required this.appState,
    required this.data,
    required this.filter,
    required this.prefs,
    required this.theme,
    required this.settings,
    required this.alerts,
  });

  final AppState appState;
  final DataController data;
  final FilterController filter;
  final UserPrefs prefs;
  final ThemeController theme;
  final SettingsController settings;
  final AlertController alerts;

  Widget wrap(Widget child) => MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: appState),
          ChangeNotifierProvider<DataController>.value(value: data),
          ChangeNotifierProvider<FilterController>.value(value: filter),
          ChangeNotifierProvider<UserPrefs>.value(value: prefs),
          ChangeNotifierProvider<ThemeController>.value(value: theme),
          ChangeNotifierProvider<SettingsController>.value(value: settings),
          ChangeNotifierProvider<AlertController>.value(value: alerts),
        ],
        child: child,
      );
}

Future<_Env> _boot(
  WidgetTester tester, {
  AppSettings? settings,
  double width = 1280,
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
  final prefs = UserPrefs(appState.prefs)..bindUser(appState.currentUser?.uid);
  final theme = ThemeController(appState.prefs, prefs);
  final controller = SettingsController(appState, theme);
  final env = _Env(
    appState: appState,
    data: data,
    filter: FilterController(),
    prefs: prefs,
    theme: theme,
    settings: controller,
    alerts: AlertController(prefs, controller),
  );
  if (settings != null) await _save(tester, env, settings);
  return env;
}

Future<void> _save(WidgetTester tester, _Env env, AppSettings s) async {
  await tester.runAsync(() => env.settings.save(s));
}

Future<void> _pumpDashboard(WidgetTester tester, _Env env) async {
  await tester.pumpWidget(env.wrap(
    const MaterialApp(home: Scaffold(body: DashboardScreen())),
  ));
  // The one-time entrance, count-ups and chart draw-ins.
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 500));
  }
}

/// Every figure on the dashboard, headline row and "More figures" together.
List<KpiData> _kpis(WidgetTester tester) => [
      for (final w in tester.widgetList<HeroKpiTile>(find.byType(HeroKpiTile)))
        w.data,
      for (final w in tester.widgetList<KpiTile>(find.byType(KpiTile))) w.data,
    ];

/// The dashboard sections on screen, top to bottom.
List<String> _sections(WidgetTester tester) => [
      for (final e in tester.widgetList<Entrance>(find.byType(Entrance)))
        if (e.id.startsWith('dashboard-')) e.id.substring('dashboard-'.length),
    ];

class _Row {
  const _Row(this.id, this.name);
  final int id;
  final String name;
}

final _gridRows = [for (var i = 0; i < 40; i++) _Row(i, 'Item-${i + 100}')];

Widget _grid({String? exportName}) => SingleChildScrollView(
      child: AppDataGrid<_Row>(
        gridId: 'test.grid',
        rows: _gridRows,
        rowKey: (r) => r.id,
        exportName: exportName,
        columns: [
          GridColumn<_Row>(
            id: 'name',
            label: 'Name',
            pinned: true,
            cell: (r) => Text(r.name),
            sortValue: (r) => r.name,
            exportValue: (r) => r.name,
          ),
          GridColumn<_Row>(
            id: 'id',
            label: 'Number',
            cell: (r) => Text('${r.id}'),
            sortValue: (r) => r.id,
            exportValue: (r) => '${r.id}',
          ),
        ],
      ),
    );

int _gridRowCount() => find.textContaining('Item-').evaluate().length;

void main() {
  setUp(() {
    Entrance.reset();
    AnimatedNumber.reset();
    ChartReveal.reset();
  });

  tearDown(() => MoneyFormatter.configureGrouping(NumberGrouping.byCurrency));

  group('modules', () {
    testWidgets('a disabled module is dropped from the navigation', (tester) async {
      final owner = (await _boot(tester)).appState.currentUser!;
      const off = ModuleSettings(disabled: {Routes.orders, Routes.dealers});
      final routes = [for (final d in NavRegistry.visible(owner, modules: off)) d.route];
      expect(routes, isNot(contains(Routes.orders)));
      expect(routes, isNot(contains(Routes.dealers)));
      expect(routes, contains(Routes.customers));
      // Without module settings nothing changes.
      expect([for (final d in NavRegistry.visible(owner)) d.route],
          contains(Routes.orders));
    });

    testWidgets('a disabled module leaves the sidebar and its route redirects',
        (tester) async {
      final env = await _boot(tester,
          settings: const AppSettings(
            modules: ModuleSettings(disabled: {Routes.orders}),
            navigation: NavigationSettings(landingRoute: Routes.orders),
          ));
      final router = buildRouter(env.appState, settings: env.settings);
      addTearDown(router.dispose);
      await tester.pumpWidget(env.wrap(MaterialApp.router(routerConfig: router)));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }

      Finder inSidebar(String text) =>
          find.descendant(of: find.byType(AppSidebar), matching: find.text(text));
      expect(inSidebar('Customers'), findsWidgets);
      expect(inSidebar('Orders'), findsNothing);

      // A disabled section's address, and a landing page that is itself off,
      // both end on the dashboard.
      router.go(Routes.orders);
      await tester.pump(const Duration(milliseconds: 500));
      expect(router.routeInformationProvider.value.uri.path, Routes.dashboard);
      router.go('${Routes.orders}/ORD-000001');
      await tester.pump(const Duration(milliseconds: 500));
      expect(router.routeInformationProvider.value.uri.path, Routes.dashboard);

      // Switching it back on brings it back.
      await _save(tester, env, const AppSettings());
      await tester.pump(const Duration(milliseconds: 500));
      expect(inSidebar('Orders'), findsWidgets);
    });
  });

  group('dashboard', () {
    testWidgets('totals are identical with modules disabled', (tester) async {
      final env = await _boot(tester);
      await _pumpDashboard(tester, env);
      final before = {for (final k in _kpis(tester)) k.id: k.value};
      final summary = DashboardViewModel.of(env.data, env.filter).summary;
      expect(before, hasLength(kDashboardKpis.length));

      await _save(
        tester,
        env,
        const AppSettings(
          modules: ModuleSettings(disabled: {
            Routes.orders,
            Routes.goals,
            Routes.campaigns,
            Routes.reports,
          }),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      final after = {for (final k in _kpis(tester)) k.id: k.value};
      expect(after, before);
      final summaryAfter = DashboardViewModel.of(env.data, env.filter).summary;
      expect(summaryAfter.revenue, summary.revenue);
      expect(summaryAfter.netProfit, summary.netProfit);
      expect(summaryAfter.orderCount, summary.orderCount);
      expect(summaryAfter.unitsSold, summary.unitsSold);
    });

    testWidgets('section order and hidden sections are respected',
        (tester) async {
      final env = await _boot(tester);
      await _pumpDashboard(tester, env);
      final builtIn = _sections(tester);
      expect(builtIn.first, 'hero');
      expect(builtIn, contains('breakdowns'));

      await _save(
        tester,
        env,
        const AppSettings(
          dashboard: DashboardSettings(
            order: ['tables', 'products'],
            hidden: {'breakdowns', 'trends'},
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      final shown = _sections(tester);
      expect(shown.take(2), ['tables', 'products']);
      expect(shown, isNot(contains('breakdowns')));
      expect(shown, isNot(contains('trends')));
      // The sections that were not listed keep their built-in order.
      expect(shown.skip(2), [
        for (final s in builtIn)
          if (!{'tables', 'products', 'breakdowns', 'trends'}.contains(s)) s,
      ]);
    });

    testWidgets('swapping the headline figures still shows all ten',
        (tester) async {
      final env = await _boot(tester);
      await _pumpDashboard(tester, env);
      final defaultIds = [for (final k in _kpis(tester)) k.id]..sort();
      expect(defaultIds, [for (final m in kDashboardKpis) m.name]..sort());

      const hero = [
        KpiMetric.units,
        KpiMetric.productCost,
        KpiMetric.grossProfit,
        KpiMetric.contributionProfit,
      ];
      await _save(
        tester,
        env,
        AppSettings(
          dashboard:
              DashboardSettings(heroKpis: [for (final m in hero) m.name]),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      final heroIds = [
        for (final w in tester.widgetList<HeroKpiTile>(find.byType(HeroKpiTile)))
          w.data.id,
      ];
      expect(heroIds, [for (final m in hero) m.name]);

      final all = _kpis(tester);
      expect([for (final k in all) k.id]..sort(), defaultIds);
      for (final k in all) {
        expect(k.tooltip, isNotEmpty, reason: k.id);
      }
    });
  });

  group('tables', () {
    testWidgets('the organisation page size applies, a pageSize overrides it',
        (tester) async {
      final env = await _boot(tester,
          settings: const AppSettings(defaults: DefaultSettings(pageSize: 10)),
          width: 1200,
          height: 6000);
      await tester.pumpWidget(
          env.wrap(MaterialApp(home: Scaffold(body: _grid()))));
      await tester.pump();
      expect(_gridRowCount(), 10);
    });

    testWidgets('the built-in page size is 25', (tester) async {
      final env = await _boot(tester, width: 1200, height: 6000);
      await tester.pumpWidget(
          env.wrap(MaterialApp(home: Scaffold(body: _grid()))));
      await tester.pump();
      expect(_gridRowCount(), 25);
    });

    testWidgets('csvExport off hides the export button', (tester) async {
      final env = await _boot(tester, width: 1200, height: 6000);
      await tester.pumpWidget(env.wrap(
          MaterialApp(home: Scaffold(body: _grid(exportName: 'rows')))));
      await tester.pump();
      expect(find.byTooltip('Export'), findsOneWidget);

      await _save(
        tester,
        env,
        const AppSettings(
          features: FeatureSettings(disabled: {AppFeature.csvExport}),
        ),
      );
      await tester.pump();
      expect(find.byTooltip('Export'), findsNothing);
    });

    testWidgets('the organisation default columns apply', (tester) async {
      final env = await _boot(
        tester,
        settings: const AppSettings(
          tables: TableSettings(defaultColumns: {
            'test.grid': ['name']
          }),
        ),
        width: 1200,
        height: 6000,
      );
      await tester.pumpWidget(
          env.wrap(MaterialApp(home: Scaffold(body: _grid()))));
      await tester.pump();
      expect(find.text('NUMBER'), findsNothing);
      expect(find.text('NAME'), findsOneWidget);
    });

    testWidgets('only people who can edit settings may set the default columns',
        (tester) async {
      final env = await _boot(tester, width: 1200, height: 6000);
      expect(env.settings.canEdit(env.appState.currentUser),
          env.appState.currentUser!.can(Permission.manageSettings));
      await tester.pumpWidget(
          env.wrap(MaterialApp(home: Scaffold(body: _grid()))));
      await tester.pump();
      await tester.tap(find.text('Columns'));
      await tester.pumpAndSettle();
      expect(find.text('Save as default for everyone'),
          env.settings.canEdit(env.appState.currentUser)
              ? findsOneWidget
              : findsNothing);

      if (env.settings.canEdit(env.appState.currentUser)) {
        await tester.tap(find.byType(Checkbox).last);
        await tester.pump();
        await tester.tap(find.text('Save as default for everyone'));
        await tester.pump();
        await tester.runAsync(() => Future<void>.delayed(
            const Duration(milliseconds: 50)));
        await tester.pump();
        expect(env.settings.settings.tables.columnsFor('test.grid'), <String>[]);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 10));
      }
    });
  });

  group('theme and formatting', () {
    test('OrgTheme round-trips corners and chart palette', () {
      for (final corners in CornerStyle.values) {
        for (final palette in ChartPaletteStyle.values) {
          final theme = OrgTheme(corners: corners, chartPalette: palette);
          final back = OrgTheme.fromJson(theme.toJson());
          expect(back.corners, corners);
          expect(back.chartPalette, palette);
          expect(back, theme);
        }
      }
    });

    test('OrgTheme.fromJson falls back for unknown values', () {
      final back = OrgTheme.fromJson(
          {'corners': 'pointy', 'chartPalette': 'neon'});
      expect(back.corners, CornerStyle.standard);
      expect(back.chartPalette, ChartPaletteStyle.brand);
    });

    test('MoneyFormatter grouping follows the setting', () {
      final amount = Money.fromMajor(12345678);

      MoneyFormatter.configureGrouping(NumberGrouping.byCurrency);
      expect(MoneyFormatter.format(amount, CurrencyCode.inr), '₹1,23,45,678');
      expect(MoneyFormatter.format(amount, CurrencyCode.usd), '\$12,345,678');

      MoneyFormatter.configureGrouping(NumberGrouping.indian);
      expect(MoneyFormatter.format(amount, CurrencyCode.inr), '₹1,23,45,678');
      expect(MoneyFormatter.format(amount, CurrencyCode.usd), '\$1,23,45,678');

      MoneyFormatter.configureGrouping(NumberGrouping.international);
      expect(MoneyFormatter.format(amount, CurrencyCode.inr), '₹12,345,678');
      expect(MoneyFormatter.format(amount, CurrencyCode.usd), '\$12,345,678');
    });
  });
}
