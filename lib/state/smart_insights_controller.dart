import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../core/enums.dart';
import '../core/utils/date_utils.dart';
import '../core/utils/money.dart';
import '../models/app_settings.dart';
import '../models/campaign.dart';
import '../models/expense.dart';
import '../models/goal.dart';
import '../services/profit_calculation_service.dart';
import '../services/smart/anomaly_service.dart';
import '../services/smart/forecast_service.dart';
import '../services/smart/smart_config.dart';
import '../services/smart/smart_engine.dart';
import '../services/smart/smart_engine_factory.dart';
import '../services/smart/smart_suggestion_provider.dart';
import '../services/smart/smart_tokenizer.dart';
import '../services/smart/smart_types.dart';
import '../services/smart/suggestion_service.dart';
import 'app_state.dart';
import 'data_controller.dart';
import 'memo.dart';
import 'settings_controller.dart';
import 'user_prefs.dart';

/// Where the on-device AI stands for this user on this device.
enum SmartStatus {
  /// Every smart feature is switched off.
  off('Off'),

  /// Built-in Dart models only (TensorFlow.js off, not needed yet, or not
  /// better on this data).
  baseline('Built-in models'),

  /// TensorFlow.js is improving at least one result.
  enhanced('On-device AI'),

  /// TensorFlow.js failed [SmartConfig.maxFailures] times and switched
  /// itself off; built-in models carry on.
  error('Paused after errors');

  const SmartStatus(this.label);
  final String label;
}

/// A business's (or everyone's) monthly forecasts.
class SmartForecast {
  const SmartForecast({
    required this.businessId,
    required this.firstMonth,
    required this.history,
    this.revenue,
    this.netProfit,
  });

  /// Null for All Businesses.
  final String? businessId;

  /// The month of each forecast's first value: the current month.
  final DateTime firstMonth;

  /// The complete months the forecasts were built from, oldest first.
  final List<TimeSeriesPoint> history;

  /// Null when that series' forecast was hidden (too little history, or it
  /// backtested too poorly).
  final SeriesForecast? revenue;
  final SeriesForecast? netProfit;

  bool get enhanced =>
      (revenue?.model.enhanced ?? false) || (netProfit?.model.enhanced ?? false);
}

/// One on-device classifier, for the Settings status card.
class SmartModelInfo {
  const SmartModelInfo({
    required this.kind,
    required this.label,
    required this.rows,
    this.accuracy,
    this.rulesAccuracy,
    this.trainedAt,
    this.inUse = false,
  });

  /// 'expense' or 'campaign'.
  final String kind;

  /// "Expense category", "Campaign platform".
  final String label;

  /// Records it learned from (or would, once there are enough).
  final int rows;

  /// Held-out accuracy (0–1) of the model and of the built-in rules on the
  /// same records; null before training.
  final double? accuracy;
  final double? rulesAccuracy;
  final DateTime? trainedAt;

  /// Whether its suggestions are shown (it beat the rules).
  final bool inUse;
}

/// A forecast the engine produced, tied to the history it was built from.
class _Enhanced {
  const _Enhanced(this.fingerprint, this.revenue, this.netProfit);
  final String fingerprint;
  final SeriesForecast? revenue;
  final SeriesForecast? netProfit;
}

/// One training/test row for a classifier.
class _Rec {
  const _Rec(this.id, this.at, this.fields, this.cls, this.source);
  final String id;
  final DateTime at;
  final Map<String, String> fields;
  final int cls;
  final Object source;
}

/// What is kept next to a saved model (no user text).
class _Meta {
  const _Meta(this.rows, this.at, this.labels, this.acc, this.dart, this.better);
  final int rows;
  final DateTime at;
  final List<String> labels;
  final double? acc;
  final double? dart;
  final bool better;

  static _Meta? parse(String raw) {
    if (raw.isEmpty) return null;
    try {
      final m = jsonDecode(raw);
      if (m is! Map) return null;
      final at = DateTime.tryParse('${m['at']}');
      final rows = m['rows'], labels = m['labels'];
      if (at == null || rows is! int || labels is! List) return null;
      return _Meta(
        rows,
        at,
        [for (final l in labels) '$l'],
        (m['acc'] as num?)?.toDouble(),
        (m['dart'] as num?)?.toDouble(),
        m['better'] == true,
      );
    } catch (_) {
      return null;
    }
  }
}

/// One on-device classifier's state.
class _Clf {
  _Clf(this.kind, this.label, this.head, this.labels);
  final String kind;
  final String label;
  final String head;

  /// The enum names, in index order: the model's classes.
  final List<String> labels;

  /// Whether the saved model was looked for (and trained if needed) with the
  /// running engine.
  bool attempted = false;

  /// Whether a model is loaded in the running engine.
  bool loaded = false;

  /// Bumps whenever the model is replaced (cached predictions go stale).
  int epoch = 0;

  /// Records at the last training; null before.
  int? rows;
  double? accuracy;
  double? rulesAccuracy;
  DateTime? trainedAt;
  bool better = false;

  void reset() {
    attempted = false;
    loaded = false;
    rows = null;
    accuracy = null;
    rulesAccuracy = null;
    trainedAt = null;
    better = false;
    epoch++;
  }
}

/// A unit of engine work. A null [fingerprint] means it is pending for as
/// long as it exists.
class _Job {
  const _Job(this.key, this.fingerprint, this.run);
  final String key;
  final String? fingerprint;

  /// True when the engine answered every call.
  final Future<bool> Function(SmartEngine engine) run;
}

/// On-device forecasts, anomaly scores and form suggestions (0 reads,
/// 0 writes). Dart baselines are ready at once; TensorFlow.js upgrades them
/// in the background when allowed, loaded, self-tested and better.
///
/// The engine starts only after [dashboardShown] or [suggestionsWanted],
/// [SmartConfig.spawnDelay] later, and only when there is work it can do
/// (enough history or records). One job runs at a time; a job re-runs only
/// when its inputs change. Each engine failure counts; at
/// [SmartConfig.maxFailures] in a row it switches itself off for this user
/// on this device and the built-in models carry on.
class SmartInsightsController extends ChangeNotifier
    implements SmartPredictor {
  SmartInsightsController({
    required AppState appState,
    required DataController data,
    required SettingsController settings,
    required UserPrefs prefs,
    SmartEngine? Function()? engineFactory,
    Future<void> Function()? wipeDevice,
    bool? buildEnabled,
    bool? urlDisabled,
    DateTime Function()? clock,
    Duration? spawnDelay,
  })  : _app = appState,
        _data = data,
        _settings = settings,
        _prefs = prefs,
        _engineFactory = engineFactory ?? smartEngine,
        _wipe = wipeDevice ?? wipeSmartDevice,
        _buildEnabled = buildEnabled ?? SmartConfig.buildEnabled,
        _urlDisabled = urlDisabled ?? SmartConfig.urlDisabled,
        _clock = clock ?? DateTime.now,
        _spawnDelay = spawnDelay ?? SmartConfig.spawnDelay {
    _uid = _app.currentUser?.uid;
    _flags = _featureFlags();
    _provider = SmartSuggestionProvider(this);
    _data.addListener(_onData);
    _settings.addListener(_onSettings);
    _app.addListener(_onApp);
    _app.addSignOutHook(_onSignOut);
  }

  final AppState _app;
  final DataController _data;
  final SettingsController _settings;
  final UserPrefs _prefs;
  final SmartEngine? Function() _engineFactory;
  final Future<void> Function() _wipe;
  final bool _buildEnabled;
  final bool _urlDisabled;
  final DateTime Function() _clock;
  final Duration _spawnDelay;

  static const _profit = ProfitCalculationService();
  static const _forecaster = ForecastService();
  static const _kinds = ['expense', 'campaign'];

  /// Records used to train and test a classifier (the newest).
  static const _maxRows = 1500;

  late final SmartSuggestionProvider _provider;
  final StampedMemo _memo = StampedMemo();
  bool _disposed = false;
  String? _uid;
  late (bool, bool, bool, int) _flags;

  // ---- Results -----------------------------------------------------------------

  int _revision = 0;
  SmartStatus? _lastStatus;
  SmartSelfTest? _selfTest;
  String? _problem;

  final Map<String?, _Enhanced> _enhanced = {};
  int _forecastEpoch = 0;
  final Map<String?, (Object, SmartForecast?)> _forecasts = {};
  final Map<String, double> _scores = {};
  final Map<String, _Clf> _clfs = {
    'expense': _Clf('expense', 'Expense category', 'category',
        [for (final c in ExpenseCategory.values) c.name]),
    'campaign': _Clf('campaign', 'Campaign platform', 'platform',
        [for (final p in CampaignPlatform.values) p.name]),
  };

  // ---- Engine ------------------------------------------------------------------

  SmartEngine? _engine;
  bool _noEngine = false;
  bool _wanted = false;
  bool _pumping = false;
  bool _selfTestOk = false;

  /// Set when the self-test ran and failed: no engine again this session.
  bool _blocked = false;
  int _gen = 0;
  Timer? _timer;
  final Set<String?> _asked = {};
  final Map<String, String> _done = {};

  // ---- Public state ------------------------------------------------------------

  SmartStatus get status {
    if (!_on(AppFeature.forecasts) &&
        !_on(AppFeature.anomalies) &&
        !_on(AppFeature.suggestions)) {
      return SmartStatus.off;
    }
    if (_failures >= SmartConfig.maxFailures) return SmartStatus.error;
    final usingForecast = _forecasts.values.any((e) => e.$2?.enhanced ?? false);
    final usingScores = _on(AppFeature.anomalies) && _scores.isNotEmpty;
    final usingModel = _clfs.values.any(_inUse);
    return usingForecast || usingScores || usingModel
        ? SmartStatus.enhanced
        : SmartStatus.baseline;
  }

  /// The worker's self-test this session; null until it ran.
  SmartSelfTest? get selfTest => _selfTest;

  /// What went wrong last, in plain words; null when nothing did.
  String? get problem => _problem;

  /// Bumps whenever a smart result changes (use it in memo keys).
  int get revision => _revision;

  /// Engine failures in a row on this device.
  int get failures => _failures;

  /// This user's switch for TensorFlow.js on this device (default on).
  bool get userEnabled => _prefs.smartEnabled;

  Future<void> setUserEnabled(bool value) async {
    await _prefs.setSmartEnabled(value);
    if (value) {
      await _setFailures(0);
      _problem = null;
      _blocked = false;
      _bump();
      _kick();
    } else {
      _stopEngine();
      _dropResults();
      _bump();
    }
  }

  /// Whether TensorFlow.js may run now: the build, the address, this user's
  /// switch and the failure count all allow it, and a smart feature is on.
  bool get engineAllowed =>
      _engineOk &&
      (_on(AppFeature.forecasts) ||
          _on(AppFeature.anomalies) ||
          _on(AppFeature.suggestions));

  bool get _engineOk =>
      _buildEnabled &&
      !_urlDisabled &&
      userEnabled &&
      _failures < SmartConfig.maxFailures;

  /// The dashboard has drawn its first frame: the worker may start
  /// [SmartConfig.spawnDelay] later, if a feature needs it.
  void dashboardShown() {
    _wanted = true;
    _kick();
  }

  /// A form with smart suggestions is open.
  void suggestionsWanted() {
    _wanted = true;
    _kick();
  }

  int get _failures => _prefs.smartFailures;

  AppSettings get _org => _settings.settings;

  bool _on(AppFeature f) => _org.features.isOn(f);

  (bool, bool, bool, int) _featureFlags() => (
        _on(AppFeature.forecasts),
        _on(AppFeature.anomalies),
        _on(AppFeature.suggestions),
        _org.smart.minRows,
      );

  // ---- Baselines ---------------------------------------------------------------

  /// Monthly forecasts for [businessId] (null = All Businesses); null when
  /// forecasts are switched off or neither series has enough history.
  SmartForecast? forecastFor(String? businessId, {DateTime? now}) {
    if (!_on(AppFeature.forecasts)) return null;
    final at = now ?? _clock();
    final month = DateTime(at.year, at.month);
    _asked.add(businessId);
    final key = (_data.version, month, _forecastEpoch);
    final cached = _forecasts[businessId];
    if (cached != null && cached.$1 == key) return cached.$2;
    final value = _computeForecast(businessId, month);
    _forecasts[businessId] = (key, value);
    _kick();
    return value;
  }

  List<TimeSeriesPoint> _history(String? businessId, DateTime month) =>
      _memo.get(_data.version, (#history, businessId, month), () {
        return _profit.forecastHistory(
          orders: _data.ordersFor(businessId),
          campaigns: _data.campaignsFor(businessId),
          expenses: _data.expensesFor(businessId),
          asOf: month,
        );
      });

  static List<double> _revenueOf(List<TimeSeriesPoint> h) =>
      [for (final p in h) p.revenue.major];
  static List<double> _netOf(List<TimeSeriesPoint> h) =>
      [for (final p in h) p.netProfit.major];

  /// The history's first month: it ends the month before [month].
  static DateTime _firstMonth(DateTime month, int n) =>
      DateTime(month.year, month.month - n);

  /// Changes when any value does (a worker result is only used for the
  /// history it was built from).
  static String _fingerprint(Iterable<double> a, [Iterable<double>? b]) {
    var h = 0;
    for (final v in [...a, ...?b]) {
      h = SmartTokenizer.hash('$h:${v.toStringAsFixed(2)}');
    }
    return '${a.length}:$h';
  }

  SmartForecast? _computeForecast(String? businessId, DateTime month) {
    final history = _history(businessId, month);
    if (history.length < SmartConfig.forecastMinPoints) return null;
    final first = _firstMonth(month, history.length);
    final rev = _revenueOf(history), net = _netOf(history);
    var revenue = _forecaster.forecast(rev,
        firstMonth: first, horizon: SmartConfig.forecastHorizon);
    var netProfit = _forecaster.forecast(net,
        firstMonth: first, horizon: SmartConfig.forecastHorizon);
    final tf = _enhanced[businessId];
    if (tf != null && tf.fingerprint == _fingerprint(rev, net) && _engineOk) {
      revenue = ForecastService.better(revenue, tf.revenue);
      netProfit = ForecastService.better(netProfit, tf.netProfit);
    }
    if (revenue == null && netProfit == null) return null;
    return SmartForecast(
      businessId: businessId,
      firstMonth: month,
      history: history,
      revenue: revenue,
      netProfit: netProfit,
    );
  }

  /// Where the running [range] lands per the forecasts, given its figures
  /// so far; null (use the run rate) without a usable forecast.
  PeriodProjection? projectionFor(
    String? businessId, {
    required ProfitSummary toDate,
    required DateRange range,
    DateTime? now,
  }) {
    final f = forecastFor(businessId, now: now);
    final revenue = f?.revenue, netProfit = f?.netProfit;
    if (f == null || revenue == null || netProfit == null) return null;
    return _profit.projectPeriodEnd(
      toDate: toDate,
      range: range,
      asOf: now ?? _clock(),
      firstForecastMonth: f.firstMonth,
      revenue: revenue,
      netProfit: netProfit,
    );
  }

  /// The forecast end value of a running revenue or net-profit [goal]
  /// (minor units); null for other metrics or without a forecast.
  int? goalProjection(Goal goal, {DateTime? now}) {
    if (goal.metric != GoalMetric.revenue &&
        goal.metric != GoalMetric.netProfit) {
      return null;
    }
    final at = now ?? _clock();
    final today = AppDate.dayOnly(at);
    final period = goal.period.range;
    if (!period.contains(today)) return null;
    final biz = goal.scopeBusinessId;
    final toDate = _profit.summarise(
      orders: _data.ordersFor(biz),
      campaigns: _data.campaignsFor(biz),
      expenses: _data.expensesFor(biz),
      range: DateRange(period.start, today),
    );
    final projection =
        projectionFor(biz, toDate: toDate, range: period, now: at);
    if (projection == null) return null;
    return (goal.metric == GoalMetric.revenue
            ? projection.revenue
            : projection.netProfit)
        .minor;
  }

  /// On-device anomaly scores by `'$businessId|$costLine'`; empty until
  /// TensorFlow.js has scored them.
  Map<String, double> get spendScores =>
      _on(AppFeature.anomalies) && _engineOk
          ? Map.unmodifiable(_scores)
          : const {};

  /// Form suggestions: the on-device classifiers where they beat the rules,
  /// the built-in rules otherwise.
  SuggestionProvider get suggestions =>
      _on(AppFeature.suggestions) && _clfs.values.any(_inUse)
          ? _provider
          : const DartSuggestionProvider();

  /// The classifiers, for the Settings status card.
  List<SmartModelInfo> get models => [
        for (final k in _kinds)
          SmartModelInfo(
            kind: k,
            label: _clfs[k]!.label,
            rows: _recs(k).length,
            accuracy: _clfs[k]!.accuracy,
            rulesAccuracy: _clfs[k]!.rulesAccuracy,
            trainedAt: _clfs[k]!.trainedAt,
            inUse: _inUse(_clfs[k]!),
          ),
      ];

  bool _inUse(_Clf c) =>
      c.loaded &&
      c.better &&
      _engine != null &&
      _on(AppFeature.suggestions) &&
      _engineOk;

  // ---- SmartPredictor (for the suggestion provider) --------------------------------

  @override
  bool classifierInUse(String kind) {
    final c = _clfs[kind];
    return c != null && _inUse(c);
  }

  @override
  int classifierEpoch(String kind) => _clfs[kind]?.epoch ?? 0;

  @override
  int classifierRows(String kind) => _clfs[kind]?.rows ?? 0;

  @override
  Future<List<List<SmartClassScore>>?> predict(String kind, Int32List x,
      {required int n}) async {
    final engine = _engine, clf = _clfs[kind], gen = _gen;
    if (engine == null || clf == null || !clf.loaded) return null;
    final result = await engine.predict(_modelKey(kind), x, n: n, k: 3);
    if (gen != _gen) return null;
    final head = result?[clf.head];
    if (head == null) {
      _fail('The on-device model did not answer.');
      return null;
    }
    _succeeded();
    return [
      for (var i = 0; i < head.rows; i++)
        [
          for (var r = 0; r < head.k; r++)
            SmartClassScore(head.classAt(i, r), head.probabilityAt(i, r)),
        ],
    ];
  }

  @override
  void predictionsArrived() => _bump();

  // ---- Lifecycle -------------------------------------------------------------------

  /// Stops the worker and deletes everything it learned on this device.
  Future<void> clearDeviceData() async {
    _stopEngine();
    _dropResults();
    _done.clear();
    await _setFailures(0);
    _problem = null;
    _blocked = false;
    try {
      await _wipe();
    } catch (_) {}
    _bump();
  }

  Future<void> _onSignOut() async {
    _stopEngine();
    if (_org.smart.wipeOnSignOut) {
      try {
        await _wipe();
      } catch (_) {}
    }
  }

  void _onApp() {
    final uid = _app.currentUser?.uid;
    if (uid == _uid) return;
    _uid = uid;
    _stopEngine();
    _dropResults();
    _done.clear();
    _asked.clear();
    _selfTest = null;
    _problem = null;
    _blocked = false;
    _wanted = false;
    _bump();
  }

  void _onData() => _kick();

  void _onSettings() {
    final flags = _featureFlags();
    if (flags == _flags) return;
    _flags = flags;
    if (!engineAllowed) _stopEngine();
    _bump();
    _kick();
  }

  /// Forgets everything TensorFlow.js produced (the baselines stay).
  void _dropResults() {
    _enhanced.clear();
    _forecasts.clear();
    _forecastEpoch++;
    _scores.clear();
    for (final c in _clfs.values) {
      c.reset();
    }
    _provider.clear();
  }

  /// Stops the worker; a later job starts a new one.
  void _stopEngine() {
    _gen++;
    _timer?.cancel();
    _timer = null;
    _pumping = false;
    _selfTestOk = false;
    _engine?.dispose();
    _engine = null;
    for (final c in _clfs.values) {
      c.attempted = false;
      c.loaded = false;
    }
  }

  Future<void> _setFailures(int n) async {
    if (_prefs.smartFailures == n) return;
    await _prefs.setSmartFailures(n);
  }

  void _fail(String problem) {
    final n = _failures + 1;
    unawaited(_setFailures(n));
    _problem = problem;
    if (n >= SmartConfig.maxFailures) {
      _problem = 'On-device AI paused itself after repeated errors. '
          'The built-in models are still working.';
      _stopEngine();
      _dropResults();
    }
    _bump();
  }

  void _succeeded() {
    if (_failures == 0) return;
    unawaited(_setFailures(0));
    _problem = null;
  }

  void _bump() {
    _revision++;
    _lastStatus = status;
    if (!_disposed) notifyListeners();
  }

  void _bumpIfStatusChanged() {
    if (status != _lastStatus) _bump();
  }

  // ---- Engine pipeline ---------------------------------------------------------------

  /// Schedules the pump when the engine is wanted, allowed and has work.
  void _kick() {
    if (_disposed || !_wanted || _pumping || _timer != null) return;
    if (_noEngine || _blocked || !engineAllowed) return;
    _engine ??= _engineFactory();
    if (_engine == null) {
      _noEngine = true;
      return;
    }
    if (_nextJob() == null) return;
    final delay = _selfTestOk ? Duration.zero : _spawnDelay;
    _timer = Timer(delay, () {
      _timer = null;
      unawaited(_pump());
    });
  }

  Future<void> _pump() async {
    if (_pumping || _disposed) return;
    _pumping = true;
    final gen = _gen;
    try {
      while (!_disposed && gen == _gen && engineAllowed && !_blocked) {
        final job = _nextJob();
        final engine = _engine;
        if (job == null || engine == null) break;
        if (!_selfTestOk) {
          final test = await engine.selfTest();
          if (gen != _gen) return;
          _selfTest = test ?? _selfTest;
          if (test == null) {
            _fail('The on-device AI did not start.');
            continue;
          }
          if (!test.passed) {
            _blocked = true;
            _fail('The on-device AI self-test did not pass, so the '
                'built-in models are being used.');
            _stopEngine();
            return;
          }
          _selfTestOk = true;
          _succeeded();
          _bump();
        }
        final ok = await job.run(engine);
        if (gen != _gen) return;
        if (ok) {
          final fp = job.fingerprint;
          if (fp != null) _done[job.key] = fp;
          _succeeded();
        }
        _bumpIfStatusChanged();
      }
    } catch (_) {
      if (gen == _gen) _fail('The on-device AI hit an unexpected error.');
    } finally {
      if (gen == _gen) _pumping = false;
    }
  }

  /// The first job whose inputs changed since it last ran.
  _Job? _nextJob() {
    for (final job in _jobs()) {
      if (job.fingerprint == null || _done[job.key] != job.fingerprint) {
        return job;
      }
    }
    return null;
  }

  List<_Job> _jobs() {
    final now = _clock();
    final month = DateTime(now.year, now.month);
    final jobs = <_Job>[];
    if (_on(AppFeature.forecasts)) {
      for (final id in _asked.toList()) {
        final history = _history(id, month);
        if (history.length < SmartConfig.tfForecastMinPoints) continue;
        jobs.add(_Job(
          'forecast|$id',
          _fingerprint(_revenueOf(history), _netOf(history)),
          (e) => _runForecast(e, id, month),
        ));
      }
    }
    if (_on(AppFeature.anomalies)) {
      _anomalyInputs(now).forEach((id, lines) {
        final values = [
          for (final months in lines.values)
            for (final m in months) m.major,
        ];
        jobs.add(_Job(
          'anomaly|$id',
          '${lines.keys.join(',')}:${_fingerprint(values)}',
          (e) => _runAnomaly(e, id, lines, now),
        ));
      });
    }
    if (_on(AppFeature.suggestions) && _uid != null) {
      for (final k in _kinds) {
        final clf = _clfs[k]!;
        final rows = _recs(k).length;
        if (rows < _org.smart.minRows) continue;
        if (clf.attempted && !_stale(clf, rows, now)) continue;
        jobs.add(_Job('classifier|$k', null, (e) => _runClassifier(e, clf)));
      }
    }
    return jobs;
  }

  // ---- Forecast and anomaly jobs -------------------------------------------------------

  Future<bool> _runForecast(
      SmartEngine engine, String? businessId, DateTime month) async {
    final history = _history(businessId, month);
    final n = history.length;
    final rev = _revenueOf(history), net = _netOf(history);
    final months = Int32List.fromList(
        ForecastService.calendarMonths(_firstMonth(month, n), n));
    final gen = _gen;
    final r = await engine.forecast(Float64List.fromList(rev), months,
        horizon: SmartConfig.forecastHorizon);
    if (gen != _gen) return false;
    final p = r == null
        ? null
        : await engine.forecast(Float64List.fromList(net), months,
            horizon: SmartConfig.forecastHorizon);
    if (gen != _gen) return false;
    if (r == null || p == null) {
      _fail('The on-device forecast did not finish.');
      return false;
    }
    _enhanced[businessId] = _Enhanced(
      _fingerprint(rev, net),
      _forecaster.fromEngine(r, points: n),
      _forecaster.fromEngine(p, points: n),
    );
    _forecastEpoch++;
    forecastFor(businessId, now: month);
    _bump();
    return true;
  }

  /// Per business, the cost lines the on-device model can score.
  Map<String, Map<String, List<Money>>> _anomalyInputs(DateTime now) =>
      _memo.get(_data.version, (#anomaly, AppDate.iso(now)), () {
        final ids = {
          for (final c in _data.campaigns) c.businessId,
          for (final e in _data.expenses) e.businessId,
        };
        final result = <String, Map<String, List<Money>>>{};
        for (final id in ids) {
          final history = _profit.monthlySpendByCategory(
            campaigns: _data.campaignsFor(id),
            expenses: _data.expensesFor(id),
            asOf: now,
            months: SmartConfig.anomalyMonths,
          );
          final lines = {
            for (final e in history.entries)
              if (AnomalyService.enoughForModel(e.value)) e.key: e.value,
          };
          if (lines.isNotEmpty) result[id] = lines;
        }
        return result;
      });

  Future<bool> _runAnomaly(SmartEngine engine, String businessId,
      Map<String, List<Money>> lines, DateTime now) async {
    final names = lines.keys.toList();
    final n = SmartConfig.anomalyMonths;
    final series = Float64List(names.length * n);
    for (var i = 0; i < names.length; i++) {
      final months = lines[names[i]]!;
      for (var j = 0; j < n; j++) {
        series[i * n + j] = months[j].major;
      }
    }
    final months = Int32List.fromList(ForecastService.calendarMonths(
        DateTime(now.year, now.month - n + 1), n));
    final gen = _gen;
    final scores = await engine.anomaly(series, months, k: names.length, n: n);
    if (gen != _gen) return false;
    if (scores == null || scores.length != names.length) {
      _fail('The on-device spend check did not finish.');
      return false;
    }
    _scores.removeWhere((key, _) => key.startsWith('$businessId|'));
    for (var i = 0; i < names.length; i++) {
      if (scores[i].isFinite) _scores['$businessId|${names[i]}'] = scores[i];
    }
    _bump();
    return true;
  }

  // ---- Classifiers ---------------------------------------------------------------------

  String _modelKey(String kind) =>
      'u${SmartTokenizer.hash(_uid ?? '').toRadixString(16)}:$kind';

  /// Visible records for [kind], oldest first. Dealer-mirrored expenses are
  /// skipped: the app wrote them, the user didn't pick their category.
  List<_Rec> _recs(String kind) =>
      _memo.get(_data.version, (#recs, kind), () {
        final recs = <_Rec>[];
        if (kind == 'expense') {
          for (final e in _data.expenses) {
            if (e.id.startsWith('EXP-DLR-') || e.sourceDealerId != null) {
              continue;
            }
            recs.add(_Rec(
              e.id,
              e.startDate ?? e.audit.createdAt ?? DateTime(2000),
              {'n': e.name, 'v': e.vendor, 'b': e.businessId},
              e.category.index,
              e,
            ));
          }
        } else {
          for (final c in _data.campaigns) {
            recs.add(_Rec(
              c.id,
              c.startDate ?? c.audit.createdAt ?? DateTime(2000),
              {'n': c.name, 'b': c.businessId},
              c.platform.index,
              c,
            ));
          }
        }
        recs.sort((a, b) {
          final byDate = a.at.compareTo(b.at);
          return byDate != 0 ? byDate : a.id.compareTo(b.id);
        });
        return recs;
      });

  bool _stale(_Clf c, int rows, DateTime now) {
    final at = c.trainedAt, trained = c.rows;
    if (at == null || trained == null) return true;
    return rows - trained >= SmartConfig.retrainAfterRows ||
        now.difference(at) >= SmartConfig.retrainAfter;
  }

  /// Loads the saved model and keeps it while it is fresh; otherwise trains.
  Future<bool> _runClassifier(SmartEngine engine, _Clf clf) async {
    final recs = _recs(clf.kind);
    final key = _modelKey(clf.kind);
    final gen = _gen;
    final now = _clock();
    if (!clf.attempted) {
      final raw = await engine.load(key);
      if (gen != _gen) return false;
      if (raw == null) {
        _fail('The saved on-device model could not be read.');
        return false;
      }
      final meta = _Meta.parse(raw);
      if (meta != null &&
          recs.length - meta.rows < SmartConfig.retrainAfterRows &&
          now.difference(meta.at) < SmartConfig.retrainAfter &&
          _sameLabels(meta.labels, clf.labels)) {
        clf
          ..attempted = true
          ..loaded = true
          ..rows = meta.rows
          ..accuracy = meta.acc
          ..rulesAccuracy = meta.dart
          ..trainedAt = meta.at
          ..better = meta.better
          ..epoch += 1;
        _provider.clear();
        _bump();
        return true;
      }
    }
    return _train(engine, clf, recs, key, now);
  }

  static bool _sameLabels(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Trains on the older rows, tests on the most recent 20% (10–150 rows),
  /// and keeps the model with how it did against the built-in rules.
  Future<bool> _train(SmartEngine engine, _Clf clf, List<_Rec> all, String key,
      DateTime now) async {
    final gen = _gen;
    final recs =
        all.length > _maxRows ? all.sublist(all.length - _maxRows) : all;
    final n = recs.length;
    var hold = (n * 0.2).round().clamp(10, 150);
    if (n - hold < 10) hold = n - 10;
    final train = recs.sublist(0, n - hold);
    final test = recs.sublist(n - hold);

    // Let the page draw before the rules' (slower) pass over the test rows.
    await Future<void>.delayed(Duration.zero);
    if (gen != _gen) return false;
    final rulesAcc = _rulesAccuracy(clf.kind, train, test, now);

    final result = await engine.train(SmartTrainRequest(
      key: key,
      heads: {clf.head: clf.labels.length},
      n: train.length,
      x: SmartTokenizer.encodeAll([for (final r in train) r.fields]),
      y: {
        clf.head: Int32List.fromList([for (final r in train) r.cls]),
      },
      hn: test.length,
      hx: SmartTokenizer.encodeAll([for (final r in test) r.fields]),
    ));
    if (gen != _gen) return false;
    final pred = result?.heads[clf.head];
    if (result == null || pred == null || pred.rows < test.length) {
      _fail('The on-device model did not finish learning.');
      return false;
    }
    var hits = 0;
    for (var i = 0; i < test.length; i++) {
      if (pred.classAt(i) == test[i].cls) hits++;
    }
    final acc = hits / test.length;
    final better = acc >= rulesAcc + 0.02;
    final saved = await engine.save(
        key,
        jsonEncode({
          'rows': all.length,
          'at': now.toIso8601String(),
          'labels': clf.labels,
          'acc': acc,
          'dart': rulesAcc,
          'better': better,
        }));
    if (gen != _gen) return false;
    if (saved == null) {
      _fail('The on-device model could not be kept.');
      return false;
    }
    clf
      ..attempted = true
      ..loaded = true
      ..rows = all.length
      ..accuracy = acc
      ..rulesAccuracy = rulesAcc
      ..trainedAt = now
      ..better = better
      ..epoch += 1;
    _provider.clear();
    _bump();
    return true;
  }

  /// Top-1 accuracy of the built-in rules on [test], learning from [train].
  double _rulesAccuracy(
      String kind, List<_Rec> train, List<_Rec> test, DateTime now) {
    final rules = DartSuggestionProvider(now: now);
    var hits = 0;
    if (kind == 'expense') {
      final history = [for (final r in train) r.source as Expense];
      for (final r in test) {
        final e = r.source as Expense;
        final top = rules.expenseCategory(
            name: e.name,
            vendor: e.vendor,
            history: history,
            businessId: e.businessId);
        if (top.isNotEmpty && top.first.value.index == r.cls) hits++;
      }
    } else {
      final history = [for (final r in train) r.source as Campaign];
      for (final r in test) {
        final c = r.source as Campaign;
        final top = rules.campaignPlatform(
            name: c.name, history: history, businessId: c.businessId);
        if (top.isNotEmpty && top.first.value.index == r.cls) hits++;
      }
    }
    return test.isEmpty ? 0 : hits / test.length;
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _gen++;
    _engine?.dispose();
    _engine = null;
    _data.removeListener(_onData);
    _settings.removeListener(_onSettings);
    _app.removeListener(_onApp);
    _app.removeSignOutHook(_onSignOut);
    _provider.dispose();
    super.dispose();
  }
}

/// The [SmartInsightsController], or null where none is provided (widget
/// tests of a single screen). Listens when [listen] (call from `build`).
SmartInsightsController? smartOf(BuildContext context, {bool listen = true}) {
  try {
    return Provider.of<SmartInsightsController>(context, listen: listen);
  } on ProviderNotFoundException {
    return null;
  }
}
