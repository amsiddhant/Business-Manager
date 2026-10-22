import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import '../../core/enums.dart';
import '../../core/utils/money.dart';
import '../../models/campaign.dart';
import '../../models/expense.dart';
import '../../models/order.dart';
import 'smart_config.dart';
import 'smart_tokenizer.dart';
import 'suggestion_service.dart';

/// A class number and how likely the on-device model thinks it is (0–1).
class SmartClassScore {
  const SmartClassScore(this.index, this.p);

  final int index;
  final double p;
}

/// What [SmartSuggestionProvider] needs from the controller that owns the
/// on-device classifiers (kinds: 'expense', 'campaign').
abstract interface class SmartPredictor {
  /// Whether [kind]'s model beat the built-in rules and is loaded.
  bool classifierInUse(String kind);

  /// Changes whenever [kind]'s model is replaced (cached answers go stale).
  int classifierEpoch(String kind);

  /// Records [kind]'s model learned from.
  int classifierRows(String kind);

  /// The likeliest classes (best first) for each of [n] rows of token ids;
  /// null when the engine can't answer.
  Future<List<List<SmartClassScore>>?> predict(String kind, Int32List x,
      {required int n});

  /// Answers were added to the provider's cache: rebuild the forms.
  void predictionsArrived();
}

/// Form suggestions with the on-device classifiers in front of the built-in
/// rules. It stays synchronous: it answers from a small cache of the
/// model's predictions and, on a miss, returns the rules' answer at once and
/// asks the model in the background (debounced); the next call hits the
/// cache. Prices and campaign types stay with the rules.
class SmartSuggestionProvider implements SuggestionProvider {
  SmartSuggestionProvider(
    this._predictor, {
    SuggestionProvider dart = const DartSuggestionProvider(),
    this.debounce = const Duration(milliseconds: 250),
  }) : _dart = dart;

  final SmartPredictor _predictor;
  final SuggestionProvider _dart;
  final Duration debounce;

  static const maxSuggestions = DartSuggestionProvider.maxSuggestions;
  static const cacheSize = 64;

  /// Cache key → the model's classes for that row (empty: it couldn't tell).
  final LinkedHashMap<String, List<SmartClassScore>> _cache = LinkedHashMap();
  final Map<String, (String, Int32List)> _pending = {};
  final Set<String> _asked = {};
  Timer? _timer;
  bool _disposed = false;

  /// The model's classes for [fields]; null while it hasn't answered yet.
  List<SmartClassScore>? _lookup(String kind, Map<String, String> fields) {
    final row = SmartTokenizer.encode(fields);
    final key = '$kind|${_predictor.classifierEpoch(kind)}|${row.join(',')}';
    final hit = _cache.remove(key);
    if (hit != null) {
      _cache[key] = hit;
      return hit;
    }
    if (!_asked.contains(key) && !_pending.containsKey(key)) {
      _pending[key] = (kind, row);
      _timer?.cancel();
      _timer = Timer(debounce, _flush);
    }
    return null;
  }

  Future<void> _flush() async {
    if (_disposed || _pending.isEmpty) return;
    final batch = Map.of(_pending);
    _pending.clear();
    _asked.addAll(batch.keys);
    var arrived = false;
    for (final kind in {for (final v in batch.values) v.$1}) {
      final keys = [
        for (final e in batch.entries)
          if (e.value.$1 == kind) e.key,
      ];
      final x = Int32List(keys.length * SmartConfig.tokens);
      for (var i = 0; i < keys.length; i++) {
        x.setRange(i * SmartConfig.tokens, (i + 1) * SmartConfig.tokens,
            batch[keys[i]]!.$2);
      }
      final result = await _predictor.predict(kind, x, n: keys.length);
      if (_disposed) return;
      for (var i = 0; i < keys.length; i++) {
        _asked.remove(keys[i]);
        final scores = result != null && i < result.length
            ? result[i]
            : const <SmartClassScore>[];
        _cache[keys[i]] = scores;
        arrived = true;
      }
      while (_cache.length > cacheSize) {
        _cache.remove(_cache.keys.first);
      }
    }
    if (arrived) _predictor.predictionsArrived();
  }

  /// The model's likely classes first, then the rules' picks, no repeats.
  List<Suggestion<T>> _merge<T>(
    List<SmartClassScore>? learned,
    List<T> values,
    String reason,
    List<Suggestion<T>> rules,
  ) {
    if (learned == null) return rules;
    final out = <Suggestion<T>>[];
    for (final s in learned) {
      if (s.p < SmartConfig.minProbability ||
          s.index < 0 ||
          s.index >= values.length) {
        continue;
      }
      out.add(Suggestion(values[s.index], reason));
    }
    for (final r in rules) {
      if (!out.any((o) => o.value == r.value)) out.add(r);
    }
    return out.take(maxSuggestions).toList();
  }

  @override
  List<Suggestion<ExpenseCategory>> expenseCategory({
    required String name,
    required String vendor,
    required Iterable<Expense> history,
    String? businessId,
  }) {
    final rules = _dart.expenseCategory(
        name: name, vendor: vendor, history: history, businessId: businessId);
    if (!_predictor.classifierInUse('expense') ||
        (name.trim().isEmpty && vendor.trim().isEmpty)) {
      return rules;
    }
    final learned = _lookup(
        'expense', {'n': name, 'v': vendor, 'b': businessId ?? ''});
    final rows = _predictor.classifierRows('expense');
    return _merge(learned, ExpenseCategory.values,
        'Learned from your $rows expenses', rules);
  }

  @override
  List<Suggestion<CampaignPlatform>> campaignPlatform({
    required String name,
    required Iterable<Campaign> history,
    String? businessId,
  }) {
    final rules = _dart.campaignPlatform(
        name: name, history: history, businessId: businessId);
    if (!_predictor.classifierInUse('campaign') || name.trim().isEmpty) {
      return rules;
    }
    final learned =
        _lookup('campaign', {'n': name, 'b': businessId ?? ''});
    final rows = _predictor.classifierRows('campaign');
    return _merge(learned, CampaignPlatform.values,
        'Learned from your $rows campaigns', rules);
  }

  @override
  List<Suggestion<String>> campaignType({
    required String typed,
    required Iterable<Campaign> history,
    String? businessId,
  }) =>
      _dart.campaignType(
          typed: typed, history: history, businessId: businessId);

  @override
  List<Suggestion<Money>> orderPrice({
    required String productId,
    required Iterable<Order> history,
  }) =>
      _dart.orderPrice(productId: productId, history: history);

  /// Drops cached answers (the model changed or was cleared).
  void clear() {
    _cache.clear();
    _pending.clear();
    _asked.clear();
    _timer?.cancel();
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
  }
}
