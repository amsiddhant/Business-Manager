import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:salesforce_business_manager/core/enums.dart';
import 'package:salesforce_business_manager/core/utils/money.dart';
import 'package:salesforce_business_manager/data/demo_seed.dart';
import 'package:salesforce_business_manager/models/expense.dart';
import 'package:salesforce_business_manager/screens/expenses/expense_detail_screen.dart';
import 'package:salesforce_business_manager/screens/expenses/expenses_screen.dart';
import 'package:salesforce_business_manager/services/profit_calculation_service.dart';
import 'package:salesforce_business_manager/services/summaries/expense_summaries.dart';
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
  test('summariseExpenses splits recurring, one-time and dealer costs', () {
    Expense expense(String id, int amount, RecurrenceFrequency f,
            {String? dealer, EntityStatus status = EntityStatus.active}) =>
        Expense(
          id: id,
          businessId: 'B1',
          name: id,
          amount: Money.fromMajor(amount),
          frequency: f,
          status: status,
          sourceDealerId: dealer,
          startDate: DateTime(2026, 1, 1),
        );
    final list = [
      expense('E1', 1000, RecurrenceFrequency.monthly),
      expense('E2', 600, RecurrenceFrequency.yearly, dealer: 'D1'),
      expense('E3', 500, RecurrenceFrequency.oneTime),
      expense('E4', 9999, RecurrenceFrequency.monthly,
          status: EntityStatus.inactive),
    ];
    const service = ProfitCalculationService();
    final s = service.summariseExpenses(list, now: DateTime(2026, 3, 15));
    expect(s.count, 4);
    expect(s.activeCount, 3);
    expect(s.recurringCount, 2);
    expect(s.dealerCount, 1);
    expect(s.annualRunRate, Money.fromMajor(12600));
    expect(s.dealerAnnual, Money.fromMajor(600));
    expect(s.oneTimeTotal, Money.fromMajor(500));
    expect(s.monthlyRunRate, Money.fromMajor(1050));
  });

  for (final width in [400.0, 1280.0]) {
    testWidgets('expenses list shows its figures, filters and rows at $width px',
        (tester) async {
      final data =
          await _pump(tester, () => const ExpensesScreen(), width: width);
      expect(tester.takeException(), isNull);
      expect(find.text('Expenses'), findsWidgets);
      expect(find.byType(KpiStrip), findsOneWidget);
      expect(find.text('Annual run-rate'), findsOneWidget);
      expect(find.text('Recurring'), findsWidgets);
      expect(find.text('Add Expense'), findsOneWidget);
      expect(find.text(data.expensesFor(null).first.name), findsWidgets);
      // The mirrored rows name their dealer.
      expect(find.textContaining('Managed by '), findsWidgets);
    });

    testWidgets('expense detail shows the header, figures and sections '
        'at $width px', (tester) async {
      await _pump(tester, () => const ExpenseDetailScreen(expenseId: 'EXP-00001'),
          width: width);
      expect(tester.takeException(), isNull);
      expect(find.text('Domain (aurora-gadgets.com)'), findsWidgets);
      expect(find.text('Annualised'), findsWidgets);
      expect(find.text('This month'), findsWidgets);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('More'), findsOneWidget);
    });

    testWidgets('a dealer-mirrored expense links to its dealer at $width px',
        (tester) async {
      await _pump(
          tester, () => const ExpenseDetailScreen(expenseId: 'EXP-DLR-DLR-00001'),
          width: width);
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Read-only'), findsOneWidget);
      expect(find.text('View dealer'), findsWidgets);
      // Managed via the dealer: nothing to edit, duplicate or delete.
      expect(find.text('Edit'), findsNothing);
    });
  }

  testWidgets('a dealer-mirrored row offers no edit, duplicate or delete',
      (tester) async {
    await _pump(tester, () => const ExpensesScreen(), width: 1280);
    // Only the dealer-managed rows.
    await tester.tap(find.text('Dealer-managed').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('Managed by Shenzhen Direct Supply'),
        findsWidgets);
    expect(find.byTooltip('Open dealer'), findsWidgets);
    expect(find.byTooltip('Edit'), findsNothing);
    expect(find.byTooltip('Duplicate'), findsNothing);
    expect(find.byTooltip('Delete'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a regular row offers edit, duplicate and delete',
      (tester) async {
    await _pump(tester, () => const ExpensesScreen(), width: 1280);
    await tester.tap(find.text('One-time').last);
    await tester.pumpAndSettle();
    // No one-time expenses in the demo data: the other quick filter instead.
    await tester.tap(find.text('Recurring').last);
    await tester.pumpAndSettle();

    expect(find.byTooltip('Edit'), findsWidgets);
    expect(find.byTooltip('Duplicate'), findsWidgets);
    expect(find.byTooltip('Delete'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the expense form keeps its Description field and sections',
      (tester) async {
    await _pump(tester, () => const ExpensesScreen(), width: 1280);
    await tester.tap(find.text('Add Expense'));
    await tester.pumpAndSettle();

    expect(find.text('Description', findRichText: true), findsOneWidget);
    expect(find.text('Amount & recurrence'), findsWidgets);
    expect(find.text('Expense Name *', findRichText: true), findsWidgets);
    expect(find.text('Notes', findRichText: true), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Duplicate opens a prefilled new-expense form', (tester) async {
    await _pump(tester, () => const ExpenseDetailScreen(expenseId: 'EXP-00001'),
        width: 1280);

    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duplicate'));
    await tester.pumpAndSettle();

    expect(find.text('Duplicate Expense'), findsOneWidget);
    expect(find.text('A new expense, copied from EXP-00001'), findsOneWidget);
    expect(find.text('Description', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a missing expense shows not found with a way back',
      (tester) async {
    await _pump(tester, () => const ExpenseDetailScreen(expenseId: 'NOPE'),
        width: 1280);
    expect(find.text('Expense not found'), findsOneWidget);
    expect(find.text('Back to Expenses'), findsOneWidget);
  });
}
