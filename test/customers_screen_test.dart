import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:salesforce_business_manager/core/enums.dart';
import 'package:salesforce_business_manager/core/utils/money.dart';
import 'package:salesforce_business_manager/data/demo_seed.dart';
import 'package:salesforce_business_manager/models/customer.dart';
import 'package:salesforce_business_manager/screens/customers/customer_detail_screen.dart';
import 'package:salesforce_business_manager/screens/customers/customers_screen.dart';
import 'package:salesforce_business_manager/services/profit_calculation_service.dart';
import 'package:salesforce_business_manager/services/summaries/customer_summaries.dart';
import 'package:salesforce_business_manager/state/app_state.dart';
import 'package:salesforce_business_manager/state/data_controller.dart';
import 'package:salesforce_business_manager/state/filter_controller.dart';
import 'package:salesforce_business_manager/state/user_prefs.dart';
import 'package:salesforce_business_manager/widgets/layout/kpi_strip.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pumps [child] signed in as the demo owner, after seeding one won customer
/// (with a contract) and one pending customer. Returns the won customer's id.
Future<String> _pump(WidgetTester tester, Widget Function(String id) child,
    {required double width, double height = 2400}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({});
  late AppState appState;
  late DataController data;
  late String wonId;
  await tester.runAsync(() async {
    appState = await AppState.create();
    await appState.signIn(DemoSeed.ownerEmail, DemoSeed.password);
    while (appState.repository.currentUser == null) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    final repo = appState.repository;
    final biz = (await repo.fetchBusinesses()).first;
    final won = await repo.saveCustomer(
      Customer(
        id: '',
        businessIds: [biz.id],
        name: 'Acme Retail',
        city: 'Pune',
        dealStatus: DealStatus.successful,
        contractsByBusiness: {
          biz.id: BusinessContract(
            active: ServiceContract(
              businessId: biz.id,
              purchaseDate: DateTime.now().subtract(const Duration(days: 30)),
              expiryDate: DateTime.now().add(const Duration(days: 335)),
              price: Money.fromMajor(12000),
              plan: SubscriptionPlan.basic,
              billingCycle: BillingCycle.yearly,
            ),
          ),
        },
      ),
      isNew: true,
    );
    wonId = won.id;
    await repo.saveCustomer(
      Customer(id: '', businessIds: [biz.id], name: 'Pending Traders'),
      isNew: true,
    );
    data = DataController(repo);
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
    child: MaterialApp(
        home: Scaffold(body: Builder(builder: (_) => child(wonId)))),
  ));
  await tester.pumpAndSettle();
  return wonId;
}

void main() {
  test('summariseCustomers counts statuses, contracts and recurring revenue',
      () {
    const service = ProfitCalculationService();
    final now = DateTime(2026, 6, 1);
    Customer c(String id, DealStatus s, {ServiceContract? contract}) =>
        Customer(
          id: id,
          businessIds: const ['B1'],
          name: id,
          dealStatus: s,
          contractsByBusiness: {
            if (contract != null) 'B1': BusinessContract(active: contract),
          },
        );
    final s = service.summariseCustomers([
      c('C1', DealStatus.successful,
          contract: ServiceContract(
            businessId: 'B1',
            price: Money.fromMajor(1000),
            billingCycle: BillingCycle.monthly,
            expiryDate: now.add(const Duration(days: 10)),
          )),
      c('C2', DealStatus.pending),
    ], businessId: null, now: now);
    expect(s.count, 2);
    expect(s.wonCount, 1);
    expect(s.pendingCount, 1);
    expect(s.activeContracts, 1);
    expect(s.renewalsDue, 1);
    expect(s.annualRecurring, Money.fromMajor(12000));
  });

  for (final width in [400.0, 1280.0]) {
    testWidgets('customers list shows figures, filters and rows at $width px',
        (tester) async {
      await _pump(tester, (_) => const CustomersScreen(), width: width);
      expect(tester.takeException(), isNull);
      expect(find.byType(KpiStrip), findsOneWidget);
      expect(find.text('Add Customer'), findsOneWidget);
      expect(find.text('Active contracts'), findsOneWidget);
      expect(find.text('Acme Retail'), findsWidgets);
      expect(find.text('Pending Traders'), findsWidgets);
      expect(find.text(DealStatus.successful.label), findsWidgets);
    });

    testWidgets('customer detail shows header, figures and sections at '
        '$width px', (tester) async {
      await _pump(tester, (id) => CustomerDetailScreen(customerId: id),
          width: width);
      expect(tester.takeException(), isNull);
      expect(find.text('Acme Retail'), findsWidgets);
      expect(find.text('Edit'), findsWidgets);
      expect(find.text('Invoice'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('Contacts'), findsWidgets);
      expect(find.text('Team Access'), findsOneWidget);
    });
  }

  testWidgets('a quick filter narrows the list to that deal status',
      (tester) async {
    await _pump(tester, (_) => const CustomersScreen(), width: 1280);
    await tester.tap(find.text(DealStatus.pending.label).first);
    await tester.pumpAndSettle();
    expect(find.text('Pending Traders'), findsWidgets);
    expect(find.text('Acme Retail'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Duplicate opens a prefilled new-customer form', (tester) async {
    await _pump(tester, (id) => CustomerDetailScreen(customerId: id),
        width: 1280);
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duplicate'));
    await tester.pumpAndSettle();
    expect(find.text('Duplicate Customer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a missing customer shows not found with a way back',
      (tester) async {
    await _pump(tester, (_) => const CustomerDetailScreen(customerId: 'NOPE'),
        width: 1280);
    expect(find.text('Back to Customers'), findsOneWidget);
  });
}
