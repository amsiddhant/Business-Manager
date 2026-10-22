import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:salesforce_business_manager/core/enums.dart';
import 'package:salesforce_business_manager/models/campaign.dart';
import 'package:salesforce_business_manager/models/expense.dart';
import 'package:salesforce_business_manager/services/smart/smart_config.dart';
import 'package:salesforce_business_manager/services/smart/smart_suggestion_provider.dart';
import 'package:salesforce_business_manager/services/smart/suggestion_service.dart';

/// Rules with a fixed answer.
class _Rules extends DartSuggestionProvider {
  _Rules(this.expense, [this.platform = const []]);

  final List<ExpenseCategory> expense;
  final List<CampaignPlatform> platform;

  @override
  List<Suggestion<ExpenseCategory>> expenseCategory({
    required String name,
    required String vendor,
    required Iterable<Expense> history,
    String? businessId,
  }) =>
      [for (final c in expense) Suggestion(c, 'rule')];

  @override
  List<Suggestion<CampaignPlatform>> campaignPlatform({
    required String name,
    required Iterable<Campaign> history,
    String? businessId,
  }) =>
      [for (final p in platform) Suggestion(p, 'rule')];
}

class _Predictor implements SmartPredictor {
  bool inUse = true;
  int epoch = 1;
  int rows = 80;
  List<SmartClassScore> answer = const [];
  bool fail = false;
  int predictCalls = 0;
  int arrived = 0;
  final List<int> batchSizes = [];

  @override
  bool classifierInUse(String kind) => inUse;
  @override
  int classifierEpoch(String kind) => epoch;
  @override
  int classifierRows(String kind) => rows;
  @override
  Future<List<List<SmartClassScore>>?> predict(String kind, Int32List x,
      {required int n}) async {
    predictCalls++;
    batchSizes.add(n);
    expect(x.length, n * SmartConfig.tokens);
    if (fail) return null;
    return [for (var i = 0; i < n; i++) answer];
  }

  @override
  void predictionsArrived() => arrived++;
}

Future<void> _wait() => Future<void>.delayed(const Duration(milliseconds: 20));

List<ExpenseCategory> _expense(SmartSuggestionProvider p,
        [String name = 'Shopify']) =>
    [
      for (final s in p.expenseCategory(
          name: name, vendor: '', history: const [], businessId: 'BIZ-1'))
        s.value
    ];

SmartSuggestionProvider _provider(_Predictor pr, _Rules rules) =>
    SmartSuggestionProvider(pr, dart: rules, debounce: Duration.zero);

void main() {
  final software = ExpenseCategory.software.index;
  final hosting = ExpenseCategory.hosting.index;
  final office = ExpenseCategory.office.index;

  test('a cache miss answers with the rules, then the model on the next call',
      () async {
    final pr = _Predictor()..answer = [SmartClassScore(software, 0.9)];
    final p = _provider(pr, _Rules([ExpenseCategory.hosting]));
    expect(_expense(p), [ExpenseCategory.hosting]);
    expect(pr.predictCalls, 0);
    await _wait();
    expect(pr.predictCalls, 1);
    expect(pr.arrived, 1);
    expect(_expense(p), [ExpenseCategory.software, ExpenseCategory.hosting]);
    expect(pr.predictCalls, 1);
    p.dispose();
  });

  test('model classes come first, then rules, without repeats', () async {
    final pr = _Predictor()
      ..answer = [SmartClassScore(software, 0.8), SmartClassScore(hosting, 0.5)];
    final p = _provider(
        pr,
        _Rules([
          ExpenseCategory.hosting,
          ExpenseCategory.office,
        ]));
    _expense(p);
    await _wait();
    expect(_expense(p), [
      ExpenseCategory.software,
      ExpenseCategory.hosting,
      ExpenseCategory.office,
    ]);
    p.dispose();
  });

  test('at most three suggestions', () async {
    final pr = _Predictor()
      ..answer = [
        SmartClassScore(software, 0.9),
        SmartClassScore(hosting, 0.8),
        SmartClassScore(office, 0.7),
        SmartClassScore(ExpenseCategory.domain.index, 0.6),
      ];
    final p = _provider(pr, _Rules([ExpenseCategory.crm]));
    _expense(p);
    await _wait();
    expect(_expense(p), hasLength(3));
    p.dispose();
  });

  test('classes under the minimum probability are left out', () async {
    final pr = _Predictor()
      ..answer = [
        SmartClassScore(software, SmartConfig.minProbability - 0.01),
        SmartClassScore(hosting, SmartConfig.minProbability),
      ];
    final p = _provider(pr, _Rules([ExpenseCategory.office]));
    _expense(p);
    await _wait();
    expect(_expense(p), [ExpenseCategory.hosting, ExpenseCategory.office]);
    p.dispose();
  });

  test('the reason says how many records it learned from', () async {
    final pr = _Predictor()..answer = [SmartClassScore(software, 0.9)];
    final p = _provider(pr, _Rules([]));
    _expense(p);
    await _wait();
    final s = p.expenseCategory(
        name: 'Shopify', vendor: '', history: const [], businessId: 'BIZ-1');
    expect(s.single.reason, 'Learned from your 80 expenses');
    p.dispose();
  });

  test('a model that is not in use leaves the rules alone', () async {
    final pr = _Predictor()
      ..inUse = false
      ..answer = [SmartClassScore(software, 0.9)];
    final p = _provider(pr, _Rules([ExpenseCategory.hosting]));
    expect(_expense(p), [ExpenseCategory.hosting]);
    await _wait();
    expect(pr.predictCalls, 0);
    p.dispose();
  });

  test('empty text is not sent to the model', () async {
    final pr = _Predictor()..answer = [SmartClassScore(software, 0.9)];
    final p = _provider(pr, _Rules([ExpenseCategory.hosting]));
    expect(_expense(p, '  '), [ExpenseCategory.hosting]);
    await _wait();
    expect(pr.predictCalls, 0);
    p.dispose();
  });

  test('a failed prediction falls back to the rules and is not asked again',
      () async {
    final pr = _Predictor()..fail = true;
    final p = _provider(pr, _Rules([ExpenseCategory.hosting]));
    _expense(p);
    await _wait();
    expect(_expense(p), [ExpenseCategory.hosting]);
    await _wait();
    expect(pr.predictCalls, 1);
    p.dispose();
  });

  test('typing quickly sends one batch', () async {
    final pr = _Predictor()..answer = [SmartClassScore(software, 0.9)];
    final p = SmartSuggestionProvider(pr,
        dart: _Rules([]), debounce: const Duration(milliseconds: 10));
    _expense(p, 'Shopify');
    _expense(p, 'Shopify fee');
    _expense(p, 'Shopify fees plan');
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(pr.batchSizes, [3]);
    p.dispose();
  });

  test('a new model epoch asks again', () async {
    final pr = _Predictor()..answer = [SmartClassScore(software, 0.9)];
    final p = _provider(pr, _Rules([]));
    _expense(p);
    await _wait();
    pr.epoch = 2;
    pr.answer = [SmartClassScore(hosting, 0.9)];
    expect(_expense(p), isEmpty);
    await _wait();
    expect(pr.predictCalls, 2);
    expect(_expense(p), [ExpenseCategory.hosting]);
    p.dispose();
  });

  test('clear forgets cached answers', () async {
    final pr = _Predictor()..answer = [SmartClassScore(software, 0.9)];
    final p = _provider(pr, _Rules([]));
    _expense(p);
    await _wait();
    p.clear();
    expect(_expense(p), isEmpty);
    p.dispose();
  });

  test('campaign platforms work the same way', () async {
    final pr = _Predictor()
      ..answer = [SmartClassScore(CampaignPlatform.google.index, 0.9)];
    final p = _provider(pr, _Rules([], [CampaignPlatform.meta]));
    List<CampaignPlatform> ask() => [
          for (final s in p.campaignPlatform(
              name: 'Diwali search', history: const [], businessId: 'BIZ-1'))
            s.value
        ];
    expect(ask(), [CampaignPlatform.meta]);
    await _wait();
    expect(ask(), [CampaignPlatform.google, CampaignPlatform.meta]);
    p.dispose();
  });

  test('campaign types and order prices stay with the rules', () {
    final p = _provider(_Predictor(), _Rules([]));
    expect(p.campaignType(typed: 'x', history: const []), isEmpty);
    expect(p.orderPrice(productId: 'P', history: const []), isEmpty);
    p.dispose();
  });
}
