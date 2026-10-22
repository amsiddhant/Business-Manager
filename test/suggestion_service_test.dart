import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salesforce_business_manager/core/enums.dart';
import 'package:salesforce_business_manager/core/utils/money.dart';
import 'package:salesforce_business_manager/models/campaign.dart';
import 'package:salesforce_business_manager/models/expense.dart';
import 'package:salesforce_business_manager/models/order.dart';
import 'package:salesforce_business_manager/services/smart/suggestion_service.dart';
import 'package:salesforce_business_manager/widgets/forms/suggestion_chips.dart';

void main() {
  final now = DateTime(2026, 10, 1);
  final suggest = DartSuggestionProvider(now: now);

  group('expenseCategory', () {
    final history = [
      Expense(
          id: 'E1',
          businessId: 'B1',
          name: 'Hostinger VPS',
          vendor: 'Hostinger',
          category: ExpenseCategory.hosting,
          startDate: DateTime(2026, 9, 1)),
      Expense(
          id: 'E2',
          businessId: 'B1',
          name: 'Google Workspace',
          vendor: 'Google',
          category: ExpenseCategory.software,
          startDate: DateTime(2026, 8, 1)),
      Expense(
          id: 'E3',
          businessId: 'B1',
          name: 'Google Ads top-up',
          vendor: 'Google',
          category: ExpenseCategory.advertising,
          startDate: DateTime(2026, 9, 20)),
    ];

    test('ranks categories of expenses sharing words or the vendor', () {
      final s = suggest.expenseCategory(
          name: 'VPS renewal', vendor: 'Hostinger', history: history);
      expect(s.first.value, ExpenseCategory.hosting);
      expect(s.first.reason, 'Used for Hostinger before');
    });

    test('offers every matching category, most likely first', () {
      final s = suggest.expenseCategory(
          name: 'Google Ads', vendor: '', history: history);
      expect(s.map((e) => e.value),
          [ExpenseCategory.advertising, ExpenseCategory.software]);
    });

    test('nothing typed or nothing alike suggests nothing', () {
      expect(
          suggest.expenseCategory(name: '', vendor: '', history: history),
          isEmpty);
      expect(
          suggest.expenseCategory(
              name: 'Office chairs', vendor: 'IKEA', history: history),
          isEmpty);
    });
  });

  group('campaigns', () {
    Campaign c(String id, String biz, CampaignPlatform p, String type,
            DateTime start) =>
        Campaign(
            id: id,
            businessId: biz,
            productId: 'P1',
            name: 'Diwali sale $id',
            platform: p,
            type: type,
            startDate: start);
    final history = [
      c('C1', 'B1', CampaignPlatform.meta, 'Retargeting', DateTime(2026, 9)),
      c('C2', 'B1', CampaignPlatform.meta, 'retargeting', DateTime(2026, 8)),
      c('C3', 'B1', CampaignPlatform.google, 'Search', DateTime(2026, 7)),
      c('C4', 'B2', CampaignPlatform.tiktok, 'Awareness', DateTime(2026, 9)),
    ];

    test('platforms come from this business, most used first', () {
      final s = suggest.campaignPlatform(
          name: 'Diwali', history: history, businessId: 'B1');
      expect(s.map((e) => e.value),
          [CampaignPlatform.meta, CampaignPlatform.google]);
      expect(s.first.reason, 'Used in 2 campaigns for this business');
    });

    test('types merge case, use the latest spelling and match the input',
        () {
      final all =
          suggest.campaignType(typed: '', history: history, businessId: 'B1');
      expect(all.map((e) => e.value), ['Retargeting', 'Search']);
      final typed = suggest.campaignType(
          typed: 'sea', history: history, businessId: 'B1');
      expect(typed.map((e) => e.value), ['Search']);
      // The exact value already typed isn't offered back.
      expect(
          suggest.campaignType(
              typed: 'search', history: history, businessId: 'B1'),
          isEmpty);
    });
  });

  test('orderPrice offers the last and the median price of sold orders', () {
    Order o(String id, int price, DateTime date,
            {OrderStatus status = OrderStatus.delivered}) =>
        Order(
            id: id,
            businessId: 'B1',
            productId: 'P1',
            productName: 'Lamp',
            sellingCost: Money.fromMajor(price),
            orderDate: date,
            status: status);
    final history = [
      o('O1', 500, DateTime(2026, 9, 1)),
      o('O2', 400, DateTime(2026, 9, 5)),
      o('O3', 450, DateTime(2026, 9, 10)),
      // Cancelled orders don't count.
      o('O4', 999, DateTime(2026, 9, 20), status: OrderStatus.cancelled),
    ];
    final s = suggest.orderPrice(productId: 'P1', history: history);
    // The median (450) equals the last price, so it's offered once.
    expect(s.map((e) => e.value), [Money.fromMajor(450)]);
    expect(suggest.orderPrice(productId: 'P2', history: history), isEmpty);

    final s2 = suggest.orderPrice(
        productId: 'P1',
        history: [...history, o('O5', 800, DateTime(2026, 9, 25))]);
    expect(s2.map((e) => e.value),
        [Money.fromMajor(800), Money.fromMajor(475)]);
  });

  testWidgets('chips fill the field only when tapped', (tester) async {
    String? picked;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(),
      home: Scaffold(
        body: SuggestionChips<String>(
          suggestions: const [
            Suggestion('Retargeting', 'Used in 2 campaigns'),
            Suggestion('Search', 'Used in 1 campaign'),
          ],
          labelOf: (v) => v,
          current: 'Search',
          onSelected: (v) => picked = v,
        ),
      ),
    ));
    expect(find.text('Suggested'), findsOneWidget);
    expect(find.text('Retargeting'), findsOneWidget);
    // The current value isn't offered again.
    expect(find.text('Search'), findsNothing);
    expect(picked, isNull);
    await tester.tap(find.text('Retargeting'));
    expect(picked, 'Retargeting');
  });
}
