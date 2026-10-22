import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:salesforce_business_manager/core/enums.dart';
import 'package:salesforce_business_manager/core/utils/money.dart';
import 'package:salesforce_business_manager/data/backend.dart';
import 'package:salesforce_business_manager/data/demo_seed.dart';
import 'package:salesforce_business_manager/data/repository.dart';
import 'package:salesforce_business_manager/models/app_settings.dart';
import 'package:salesforce_business_manager/models/app_user.dart';
import 'package:salesforce_business_manager/models/business.dart';
import 'package:salesforce_business_manager/models/expense.dart';
import 'package:salesforce_business_manager/models/goal.dart';
import 'package:salesforce_business_manager/models/order.dart';
import 'package:salesforce_business_manager/services/smart/forecast_service.dart';
import 'package:salesforce_business_manager/services/smart/smart_config.dart';
import 'package:salesforce_business_manager/services/smart/smart_engine.dart';
import 'package:salesforce_business_manager/services/smart/smart_suggestion_provider.dart';
import 'package:salesforce_business_manager/services/smart/smart_types.dart';
import 'package:salesforce_business_manager/services/smart/suggestion_service.dart';
import 'package:salesforce_business_manager/state/app_state.dart';
import 'package:salesforce_business_manager/state/data_controller.dart';
import 'package:salesforce_business_manager/state/settings_controller.dart';
import 'package:salesforce_business_manager/state/smart_insights_controller.dart';
import 'package:salesforce_business_manager/state/theme_controller.dart';
import 'package:salesforce_business_manager/state/user_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/memory_backend.dart';

final _now = DateTime(2026, 10, 22, 9);

const _owner = AppUser(
  uid: 'owner',
  loginId: 'owner',
  name: 'Owner',
  email: 'owner@example.com',
  role: UserRole.owner,
);

SmartSelfTest _selfTest({bool passed = true}) => SmartSelfTest(
      version: passed ? SmartConfig.tfjsVersion : '0.0.0',
      backend: 'cpu',
      accuracy: 1,
      forecastError: 0.05,
      storage: true,
      tensorsBefore: 0,
      tensorsAfter: 0,
      ms: 12,
    );

/// A [SmartEngine] that answers from callbacks and counts what it was asked.
class FakeEngine implements SmartEngine {
  SmartSelfTest? Function() onSelfTest = _selfTest;
  double forecastError = 0.001;
  Float64List? Function(int k, int n)? onAnomaly;
  String? meta = '';
  int classIndex = ExpenseCategory.software.index;

  int selfTests = 0,
      forecasts = 0,
      anomalies = 0,
      trains = 0,
      loads = 0,
      saves = 0,
      disposed = 0;
  int? lastAnomalyK, lastAnomalyN;
  String? savedKey, savedMeta;

  @override
  Future<SmartSelfTest?> selfTest() async {
    selfTests++;
    return onSelfTest();
  }

  @override
  Future<SmartSeriesForecast?> forecast(Float64List y, Int32List months,
      {required int horizon}) async {
    forecasts++;
    expect(months.length, y.length);
    return SmartSeriesForecast(
      mean: Float64List.fromList(List.filled(horizon, 5000)),
      lower: Float64List.fromList(List.filled(horizon, 4000)),
      upper: Float64List.fromList(List.filled(horizon, 6000)),
      error: forecastError,
    );
  }

  @override
  Future<Float64List?> anomaly(Float64List series, Int32List months,
      {required int k, required int n}) async {
    anomalies++;
    lastAnomalyK = k;
    lastAnomalyN = n;
    return onAnomaly?.call(k, n) ??
        Float64List.fromList([for (var i = 0; i < k; i++) 3.0 + i]);
  }

  @override
  Future<SmartTrainResult?> train(SmartTrainRequest request) async {
    trains++;
    final hn = request.hn;
    return SmartTrainResult(ms: 5, heads: {
      for (final h in request.heads.keys)
        h: SmartHeadPrediction(
          top: Int32List.fromList(List.filled(hn, classIndex)),
          p: Float32List.fromList(List.filled(hn, 0.9)),
          k: 1,
        ),
    });
  }

  @override
  Future<bool?> save(String key, String meta) async {
    saves++;
    savedKey = key;
    savedMeta = meta;
    return true;
  }

  @override
  Future<String?> load(String key) async {
    loads++;
    return meta;
  }

  @override
  Future<Map<String, SmartHeadPrediction>?> predict(String key, Int32List x,
          {required int n, int k = 3}) async =>
      null;

  @override
  Future<bool> drop(String key) async => true;

  @override
  void dispose() => disposed++;
}

class Rig {
  late AppState app;
  late UserPrefs prefs;
  late SettingsController settings;
  late DataController data;
  late SmartInsightsController c;
  int factoryCalls = 0;
  int wipes = 0;

  Future<void> save(AppSettings s) => settings.save(s);
}

/// Months from July 2024 to October 2026 (28), oldest first.
List<DateTime> _months() => [
      for (var i = 0; i < 28; i++) DateTime(2024, 7 + i),
    ];

/// [rulesGood]: expense names repeat words per category, so the built-in
/// rules do well; otherwise every name is unique and the rules have nothing.
Future<DataController> _data({required bool rulesGood}) async {
  final backend = BatchMemoryBackend()
    ..put(Collections.businesses, 'BIZ-1',
        const Business(id: 'BIZ-1', name: 'Acme').toMap());
  final months = _months();
  for (var i = 0; i < months.length; i++) {
    final m = months[i];
    final revenue = 100000 +
        20000 * math.sin(i * math.pi / 6) +
        ((i * 37) % 11) * 1500 +
        i * 800;
    final o = Order(
      id: 'ORD-$i',
      businessId: 'BIZ-1',
      productId: 'PROD-1',
      productName: 'Product',
      orderDate: DateTime(m.year, m.month, 5),
      sellingCost: Money.fromMajor(revenue.round()),
      status: OrderStatus.delivered,
    );
    backend.put(Collections.orders, o.id, o.toMap());
    final sw = Expense(
      id: 'EXP-S$i',
      businessId: 'BIZ-1',
      name: rulesGood ? 'Shopify plan' : 'Zq${i}s',
      category: ExpenseCategory.software,
      amount: Money.fromMajor(900 + (i * 13) % 7 * 40),
      startDate: DateTime(m.year, m.month, 10),
    );
    final host = Expense(
      id: 'EXP-H$i',
      businessId: 'BIZ-1',
      name: rulesGood ? 'AWS hosting' : 'Wk${i}h',
      category: ExpenseCategory.hosting,
      amount: Money.fromMajor(1200 + (i * 17) % 5 * 50),
      startDate: DateTime(m.year, m.month, 12),
    );
    backend
      ..put(Collections.expenses, sw.id, sw.toMap())
      ..put(Collections.expenses, host.id, host.toMap());
  }
  for (var i = 0; i < 4; i++) {
    final e = Expense(
      id: 'EXP-O$i',
      businessId: 'BIZ-1',
      name: rulesGood ? 'Desk chair' : 'Vx${i}o',
      category: ExpenseCategory.office,
      amount: Money.fromMajor(500),
      startDate: DateTime(2024, 7, 20),
    );
    backend.put(Collections.expenses, e.id, e.toMap());
  }
  final data = DataController(Repository(backend: backend, currentUser: _owner));
  await data.load();
  return data;
}

Future<Rig> _rig({
  FakeEngine? engine,
  bool buildEnabled = true,
  bool urlDisabled = false,
  bool rulesGood = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  final r = Rig();
  r.app = await AppState.create();
  await r.app.signIn(DemoSeed.ownerEmail, DemoSeed.password);
  while (r.app.currentUser == null) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  r.prefs = UserPrefs(r.app.prefs)..bindUser(r.app.currentUser?.uid);
  r.settings = SettingsController(r.app, ThemeController(r.app.prefs, r.prefs));
  r.data = await _data(rulesGood: rulesGood);
  r.c = SmartInsightsController(
    appState: r.app,
    data: r.data,
    settings: r.settings,
    prefs: r.prefs,
    engineFactory: () {
      r.factoryCalls++;
      return engine;
    },
    wipeDevice: () async => r.wipes++,
    buildEnabled: buildEnabled,
    urlDisabled: urlDisabled,
    clock: () => _now,
    spawnDelay: Duration.zero,
  );
  addTearDown(r.c.dispose);
  return r;
}

Future<void> _until(bool Function() ok, [String what = 'condition']) async {
  for (var i = 0; i < 600; i++) {
    if (ok()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('Timed out waiting for $what');
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 80));

AppSettings _off(Set<AppFeature> features, {bool wipe = true}) => AppSettings(
      features: FeatureSettings(disabled: features),
      smart: SmartSettings(wipeOnSignOut: wipe),
    );

SmartModelInfo _model(Rig r, String kind) =>
    r.c.models.firstWhere((m) => m.kind == kind);

void main() {
  group('forecasts', () {
    test('without an engine the Dart baseline is used', () async {
      final r = await _rig(engine: null);
      final f = r.c.forecastFor(null, now: _now);
      expect(f, isNotNull);
      expect(f!.revenue, isNotNull);
      expect(f.enhanced, isFalse);
      expect(r.c.status, SmartStatus.baseline);
      r.c.dashboardShown();
      await _settle();
      expect(r.factoryCalls, 1);
      expect(r.c.forecastFor(null, now: _now)!.enhanced, isFalse);
      expect(r.c.status, SmartStatus.baseline);
      expect(r.c.failures, 0);
    });

    test('the engine does not start before the dashboard asks', () async {
      final e = FakeEngine();
      final r = await _rig(engine: e);
      r.c.forecastFor(null, now: _now);
      await _settle();
      expect(r.factoryCalls, 0);
      expect(e.selfTests, 0);
    });

    test('a better backtest replaces the baseline', () async {
      final e = FakeEngine()..forecastError = 0.001;
      final r = await _rig(engine: e);
      final baseline = r.c.forecastFor(null, now: _now)!;
      expect(baseline.revenue!.error, greaterThan(0.001));
      r.c.dashboardShown();
      await _until(() => r.c.forecastFor(null, now: _now)!.enhanced,
          'the on-device forecast');
      final f = r.c.forecastFor(null, now: _now)!;
      expect(f.revenue!.model, ForecastModel.tfjs);
      expect(f.revenue!.mean.first, 5000);
      expect(e.selfTests, 1);
      expect(e.forecasts, 2);
      expect(r.c.selfTest!.passed, isTrue);
      expect(r.c.status, SmartStatus.enhanced);
      expect(r.c.revision, greaterThan(0));
    });

    test('a worse backtest leaves the baseline in place', () async {
      final e = FakeEngine()..forecastError = 0.9;
      final r = await _rig(engine: e);
      await r.save(_off({AppFeature.anomalies, AppFeature.suggestions}));
      final baseline = r.c.forecastFor(null, now: _now)!;
      r.c.dashboardShown();
      await _until(() => e.forecasts == 2, 'the engine forecast');
      await _settle();
      final f = r.c.forecastFor(null, now: _now)!;
      expect(f.enhanced, isFalse);
      expect(f.revenue!.mean.first, baseline.revenue!.mean.first);
      expect(r.c.status, SmartStatus.baseline);
    });

    test('goalProjection follows the forecast for a running revenue goal',
        () async {
      final r = await _rig(engine: null);
      final goal = Goal(
        businessId: 'BIZ-1',
        period: GoalPeriod.month(2026, 10),
        metric: GoalMetric.revenue,
        target: Money.fromMajor(200000).minor,
      );
      expect(r.c.goalProjection(goal, now: _now), isNotNull);
      final other = Goal(
        businessId: 'BIZ-1',
        period: GoalPeriod.month(2026, 10),
        metric: GoalMetric.orders,
        target: 10,
      );
      expect(r.c.goalProjection(other, now: _now), isNull);
    });
  });

  group('failures', () {
    test('a failed self-test keeps the baseline and counts one failure',
        () async {
      final e = FakeEngine()..onSelfTest = () => _selfTest(passed: false);
      final r = await _rig(engine: e);
      r.c.forecastFor(null, now: _now);
      r.c.dashboardShown();
      await _until(() => r.c.failures == 1, 'the failure count');
      await _settle();
      expect(e.selfTests, 1);
      expect(e.forecasts, 0);
      expect(e.disposed, greaterThan(0));
      expect(r.c.problem, isNotNull);
      expect(r.c.status, SmartStatus.baseline);
      expect(r.c.forecastFor(null, now: _now)!.enhanced, isFalse);
      // It does not try again this session.
      r.c.suggestionsWanted();
      await _settle();
      expect(e.selfTests, 1);
    });

    test('three failures give error status and no more engine calls',
        () async {
      final e = FakeEngine()..onSelfTest = () => null;
      final r = await _rig(engine: e);
      r.c.forecastFor(null, now: _now);
      r.c.dashboardShown();
      await _until(() => r.c.status == SmartStatus.error, 'the error status');
      expect(r.c.failures, SmartConfig.maxFailures);
      expect(r.prefs.smartFailures, SmartConfig.maxFailures);
      expect(r.c.engineAllowed, isFalse);
      final calls = e.selfTests;
      expect(calls, SmartConfig.maxFailures);
      r.c.dashboardShown();
      r.c.suggestionsWanted();
      r.c.forecastFor(null, now: _now);
      await _settle();
      expect(e.selfTests, calls);
      expect(e.forecasts, 0);
      expect(r.c.forecastFor(null, now: _now)!.enhanced, isFalse);
    });

    test('turning the switch back on clears the failures', () async {
      final e = FakeEngine()..onSelfTest = () => null;
      final r = await _rig(engine: e);
      r.c.forecastFor(null, now: _now);
      r.c.dashboardShown();
      await _until(() => r.c.status == SmartStatus.error, 'the error status');
      await r.c.setUserEnabled(false);
      await r.c.setUserEnabled(true);
      expect(r.c.failures, 0);
      expect(r.c.problem, isNull);
      expect(r.c.engineAllowed, isTrue);
    });
  });

  group('kill switches', () {
    test('the build switch keeps the engine from ever being made', () async {
      final e = FakeEngine();
      final r = await _rig(engine: e, buildEnabled: false);
      r.c.forecastFor(null, now: _now);
      r.c.dashboardShown();
      r.c.suggestionsWanted();
      await _settle();
      expect(r.c.engineAllowed, isFalse);
      expect(r.factoryCalls, 0);
      expect(e.selfTests, 0);
      expect(r.c.status, SmartStatus.baseline);
    });

    test('the URL switch keeps the engine from ever being made', () async {
      final e = FakeEngine();
      final r = await _rig(engine: e, urlDisabled: true);
      r.c.forecastFor(null, now: _now);
      r.c.dashboardShown();
      await _settle();
      expect(r.c.engineAllowed, isFalse);
      expect(r.factoryCalls, 0);
      expect(r.c.forecastFor(null, now: _now)!.enhanced, isFalse);
    });

    test('the user switch drops results and stops the engine', () async {
      final e = FakeEngine();
      final r = await _rig(engine: e);
      expect(r.c.userEnabled, isTrue);
      r.c.forecastFor(null, now: _now);
      r.c.dashboardShown();
      await _until(() => r.c.status == SmartStatus.enhanced, 'enhanced');
      await r.c.setUserEnabled(false);
      expect(r.c.userEnabled, isFalse);
      expect(r.prefs.smartEnabled, isFalse);
      expect(r.c.engineAllowed, isFalse);
      expect(r.c.status, SmartStatus.baseline);
      expect(r.c.forecastFor(null, now: _now)!.enhanced, isFalse);
      expect(r.c.spendScores, isEmpty);
      expect(e.disposed, greaterThan(0));
      final calls = e.forecasts;
      r.c.dashboardShown();
      await _settle();
      expect(e.forecasts, calls);
    });

    test('organisation features turn the matching parts off', () async {
      final e = FakeEngine();
      final r = await _rig(engine: e);
      await r.save(_off({AppFeature.forecasts}));
      expect(r.c.forecastFor(null, now: _now), isNull);
      expect(r.c.engineAllowed, isTrue);
      expect(r.c.status, SmartStatus.baseline);

      await r.save(_off({
        AppFeature.forecasts,
        AppFeature.anomalies,
        AppFeature.suggestions,
      }));
      expect(r.c.status, SmartStatus.off);
      expect(r.c.engineAllowed, isFalse);
      expect(r.c.spendScores, isEmpty);
      expect(r.c.suggestions, isA<DartSuggestionProvider>());
      r.c.dashboardShown();
      await _settle();
      expect(e.selfTests, 0);
    });
  });

  group('sign-out', () {
    test('the hook wipes the device when the setting is on', () async {
      final e = FakeEngine();
      final r = await _rig(engine: e);
      await r.save(_off({}, wipe: true));
      r.c.forecastFor(null, now: _now);
      r.c.dashboardShown();
      await _until(() => e.selfTests == 1, 'the engine to start');
      await r.app.signOut();
      expect(r.wipes, 1);
      expect(e.disposed, greaterThan(0));
    });

    test('the hook leaves the device alone when the setting is off', () async {
      final e = FakeEngine();
      final r = await _rig(engine: e);
      await r.save(_off({}, wipe: false));
      r.c.dashboardShown();
      await r.app.signOut();
      expect(r.wipes, 0);
    });

    test('clearing device data wipes and resets', () async {
      final e = FakeEngine()..onSelfTest = () => _selfTest(passed: false);
      final r = await _rig(engine: e);
      r.c.forecastFor(null, now: _now);
      r.c.dashboardShown();
      await _until(() => r.c.failures == 1, 'a failure');
      await r.c.clearDeviceData();
      expect(r.wipes, 1);
      expect(r.c.failures, 0);
      expect(r.c.problem, isNull);
    });
  });

  group('spend checks', () {
    test('scores are keyed by business and cost line', () async {
      final e = FakeEngine();
      final r = await _rig(engine: e);
      await r.save(_off({AppFeature.forecasts, AppFeature.suggestions}));
      r.c.dashboardShown();
      await _until(() => r.c.spendScores.isNotEmpty, 'the spend scores');
      expect(e.lastAnomalyN, SmartConfig.anomalyMonths);
      expect(e.lastAnomalyK, 2);
      expect(r.c.spendScores.keys,
          unorderedEquals(['BIZ-1|Software', 'BIZ-1|Hosting']));
      expect(r.c.spendScores.values.toSet(), {3.0, 4.0});
      expect(r.c.status, SmartStatus.enhanced);
    });

    test('lines the model cannot score are left out', () async {
      final e = FakeEngine()
        ..onAnomaly = (k, n) =>
            Float64List.fromList([for (var i = 0; i < k; i++) double.nan]);
      final r = await _rig(engine: e);
      await r.save(_off({AppFeature.forecasts, AppFeature.suggestions}));
      r.c.dashboardShown();
      await _until(() => e.anomalies == 1, 'the anomaly call');
      await _settle();
      expect(r.c.spendScores, isEmpty);
      expect(r.c.status, SmartStatus.baseline);
    });
  });

  group('suggestion classifiers', () {
    AppSettings suggestionsOnly() => _off({
          AppFeature.forecasts,
          AppFeature.anomalies,
        });

    test('a model is used only when it beats the rules by 0.02', () async {
      final e = FakeEngine();
      final r = await _rig(engine: e, rulesGood: false);
      await r.save(suggestionsOnly());
      r.c.suggestionsWanted();
      await _until(() => _model(r, 'expense').trainedAt != null, 'training');
      final m = _model(r, 'expense');
      expect(m.rows, 60);
      expect(m.accuracy! >= m.rulesAccuracy! + 0.02, isTrue);
      expect(m.inUse, isTrue);
      expect(r.c.suggestions, isA<SmartSuggestionProvider>());
      expect(e.trains, 1);
      expect(e.saves, 1);
      final meta = jsonDecode(e.savedMeta!) as Map<String, dynamic>;
      expect(meta['rows'], 60);
      expect(meta['better'], isTrue);
      expect(e.savedKey, endsWith(':expense'));
      expect(r.c.status, SmartStatus.enhanced);
    });

    test('a model that does not beat the rules is kept but not used',
        () async {
      final e = FakeEngine();
      final r = await _rig(engine: e, rulesGood: true);
      await r.save(suggestionsOnly());
      r.c.suggestionsWanted();
      await _until(() => _model(r, 'expense').trainedAt != null, 'training');
      final m = _model(r, 'expense');
      expect(m.accuracy! < m.rulesAccuracy! + 0.02, isTrue);
      expect(m.inUse, isFalse);
      expect(r.c.suggestions, isA<DartSuggestionProvider>());
      expect(jsonDecode(e.savedMeta!)['better'], isFalse);
      expect(r.c.status, SmartStatus.baseline);
    });

    test('too few records means no training', () async {
      final e = FakeEngine();
      final r = await _rig(engine: e);
      await r.save(AppSettings(
        features: const FeatureSettings(
            disabled: {AppFeature.forecasts, AppFeature.anomalies}),
        smart: const SmartSettings(minRows: 500),
      ));
      r.c.suggestionsWanted();
      await _settle();
      expect(e.trains, 0);
      expect(e.selfTests, 0);
    });

    String meta({int rows = 60, DateTime? at, bool better = true}) =>
        jsonEncode({
          'rows': rows,
          'at': (at ?? _now).toIso8601String(),
          'labels': [for (final c in ExpenseCategory.values) c.name],
          'acc': 0.9,
          'dart': 0.5,
          'better': better,
        });

    test('a fresh saved model is adopted without training', () async {
      final e = FakeEngine()..meta = meta();
      final r = await _rig(engine: e);
      await r.save(suggestionsOnly());
      r.c.suggestionsWanted();
      await _until(() => _model(r, 'expense').trainedAt != null, 'loading');
      expect(e.loads, greaterThan(0));
      expect(e.trains, 0);
      final m = _model(r, 'expense');
      expect(m.accuracy, 0.9);
      expect(m.rulesAccuracy, 0.5);
      expect(m.inUse, isTrue);
    });

    test('an old saved model is trained again', () async {
      final e = FakeEngine()
        ..meta = meta(at: _now.subtract(const Duration(days: 8)));
      final r = await _rig(engine: e);
      await r.save(suggestionsOnly());
      r.c.suggestionsWanted();
      await _until(() => e.trains == 1, 'retraining');
    });

    test('a saved model that is 20 records behind is trained again',
        () async {
      final e = FakeEngine()..meta = meta(rows: 40);
      final r = await _rig(engine: e);
      await r.save(suggestionsOnly());
      r.c.suggestionsWanted();
      await _until(() => e.trains == 1, 'retraining');
    });
  });
}
