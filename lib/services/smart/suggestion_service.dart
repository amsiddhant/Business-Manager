import 'dart:math' as math;

import '../../core/enums.dart';
import '../../core/utils/money.dart';
import '../../models/campaign.dart';
import '../../models/expense.dart';
import '../../models/order.dart';

/// A value a form offers as a one-tap chip. Never applied on its own.
class Suggestion<T> {
  const Suggestion(this.value, this.reason);

  final T value;

  /// Why it's offered ("Used for 4 similar expenses").
  final String reason;
}

/// Suggests form values from the records already loaded (0 reads). The P3
/// provider ranks by frequency and recency; P5 can put an on-device model
/// behind the same interface.
abstract interface class SuggestionProvider {
  /// Categories of past expenses that share words with [name] / [vendor].
  List<Suggestion<ExpenseCategory>> expenseCategory({
    required String name,
    required String vendor,
    required Iterable<Expense> history,
    String? businessId,
  });

  /// The platforms this business's campaigns use, most likely first.
  List<Suggestion<CampaignPlatform>> campaignPlatform({
    required String name,
    required Iterable<Campaign> history,
    String? businessId,
  });

  /// Campaign types already in use that match what's typed so far.
  List<Suggestion<String>> campaignType({
    required String typed,
    required Iterable<Campaign> history,
    String? businessId,
  });

  /// The product's last and typical (median) selling price per unit.
  List<Suggestion<Money>> orderPrice({
    required String productId,
    required Iterable<Order> history,
  });
}

class DartSuggestionProvider implements SuggestionProvider {
  const DartSuggestionProvider({this.now});

  /// "Today" for recency weights (tests pin it).
  final DateTime? now;

  static const maxSuggestions = 3;

  /// Orders the median price is taken over.
  static const priceWindow = 25;

  static const _stopWords = {
    'the', 'and', 'for', 'with', 'from', 'pvt', 'ltd', 'inc', 'llp', 'co',
    'per', 'month', 'monthly', 'year', 'yearly', 'annual', 'plan',
  };

  /// Lower-case words of 3+ letters, minus filler.
  static Set<String> tokens(String text) => {
        for (final w in text.toLowerCase().split(RegExp(r'[^a-z0-9]+')))
          if (w.length >= 3 && !_stopWords.contains(w)) w,
      };

  /// 1 for today, halving about every four months.
  double _recency(DateTime? at) {
    if (at == null) return 0.5;
    final days = (now ?? DateTime.now()).difference(at).inDays.clamp(0, 3650);
    return math.exp(-days / 180);
  }

  List<Suggestion<T>> _top<T>(
    Map<T, double> score,
    String Function(T value) reason,
  ) {
    final ranked = score.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [
      for (final e in ranked.take(maxSuggestions))
        Suggestion(e.key, reason(e.key)),
    ];
  }

  @override
  List<Suggestion<ExpenseCategory>> expenseCategory({
    required String name,
    required String vendor,
    required Iterable<Expense> history,
    String? businessId,
  }) {
    final words = tokens('$name $vendor');
    final v = vendor.trim().toLowerCase();
    if (words.isEmpty && v.isEmpty) return const [];
    final score = <ExpenseCategory, double>{};
    final count = <ExpenseCategory, int>{};
    final byVendor = <ExpenseCategory>{};
    for (final e in history) {
      final sameVendor = v.isNotEmpty && e.vendor.trim().toLowerCase() == v;
      final shared = tokens('${e.name} ${e.vendor} ${e.description}')
          .intersection(words)
          .length;
      if (!sameVendor && shared == 0) continue;
      final weight = _recency(e.audit.updatedAt ?? e.audit.createdAt ?? e.startDate) *
          (businessId != null && e.businessId == businessId ? 1.5 : 1);
      score[e.category] =
          (score[e.category] ?? 0) + (shared + (sameVendor ? 3 : 0)) * weight;
      count[e.category] = (count[e.category] ?? 0) + 1;
      if (sameVendor) byVendor.add(e.category);
    }
    return _top(score, (c) {
      if (byVendor.contains(c)) return 'Used for ${vendor.trim()} before';
      final n = count[c]!;
      return 'Used for $n similar ${n == 1 ? 'expense' : 'expenses'}';
    });
  }

  @override
  List<Suggestion<CampaignPlatform>> campaignPlatform({
    required String name,
    required Iterable<Campaign> history,
    String? businessId,
  }) {
    final words = tokens(name);
    final score = <CampaignPlatform, double>{};
    final count = <CampaignPlatform, int>{};
    for (final c in history) {
      if (businessId != null && c.businessId != businessId) continue;
      final shared = tokens(c.name).intersection(words).length;
      score[c.platform] = (score[c.platform] ?? 0) +
          (1 + 2 * shared) * _recency(c.audit.createdAt ?? c.startDate);
      count[c.platform] = (count[c.platform] ?? 0) + 1;
    }
    return _top(score, (p) {
      final n = count[p]!;
      return 'Used in $n ${n == 1 ? 'campaign' : 'campaigns'}'
          '${businessId == null ? '' : ' for this business'}';
    });
  }

  @override
  List<Suggestion<String>> campaignType({
    required String typed,
    required Iterable<Campaign> history,
    String? businessId,
  }) {
    final q = typed.trim().toLowerCase();
    final score = <String, double>{};
    final count = <String, int>{};
    // One entry per type whatever its case, spelt as most recently used.
    final spelling = <String, String>{};
    final latest = <String, DateTime>{};
    for (final c in history) {
      if (businessId != null && c.businessId != businessId) continue;
      final type = c.type.trim();
      final key = type.toLowerCase();
      if (key.isEmpty || key == q || (q.isNotEmpty && !key.contains(q))) {
        continue;
      }
      final at = c.audit.createdAt ?? c.startDate;
      score[key] = (score[key] ?? 0) + _recency(at);
      count[key] = (count[key] ?? 0) + 1;
      final seen = latest[key];
      if (!spelling.containsKey(key) ||
          (at != null && (seen == null || at.isAfter(seen)))) {
        spelling[key] = type;
        if (at != null) latest[key] = at;
      }
    }
    return [
      for (final s in _top(score, (k) {
        final n = count[k]!;
        return 'Used in $n ${n == 1 ? 'campaign' : 'campaigns'}';
      }))
        Suggestion(spelling[s.value]!, s.reason),
    ];
  }

  @override
  List<Suggestion<Money>> orderPrice({
    required String productId,
    required Iterable<Order> history,
  }) {
    DateTime dateOf(Order o) =>
        o.orderDate ?? o.audit.createdAt ?? DateTime(0);
    final sold = [
      for (final o in history)
        if (o.productId == productId &&
            o.isRecognised &&
            o.sellingCost.isPositive)
          o,
    ]..sort((a, b) => dateOf(b).compareTo(dateOf(a)));
    if (sold.isEmpty) return const [];
    final last = sold.first.sellingCost;
    final recent = [for (final o in sold.take(priceWindow)) o.sellingCost.minor]
      ..sort();
    final mid = recent.length ~/ 2;
    final median = Money(recent.length.isOdd
        ? recent[mid]
        : ((recent[mid - 1] + recent[mid]) / 2).round());
    return [
      Suggestion(last, 'Last sold at this price'),
      if (median != last)
        Suggestion(median,
            'Typical price over the last ${recent.length} orders'),
    ];
  }
}
