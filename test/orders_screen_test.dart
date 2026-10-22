import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:salesforce_business_manager/core/enums.dart';
import 'package:salesforce_business_manager/core/utils/money.dart';
import 'package:salesforce_business_manager/data/demo_seed.dart';
import 'package:salesforce_business_manager/models/order.dart';
import 'package:salesforce_business_manager/screens/orders/order_detail_screen.dart';
import 'package:salesforce_business_manager/screens/orders/orders_screen.dart';
import 'package:salesforce_business_manager/services/profit_calculation_service.dart';
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
  test('summariseOrders counts every order but sums recognised ones', () {
    Order order(String id, OrderStatus status, {int refund = 0}) => Order(
          id: id,
          businessId: 'B1',
          productId: 'P1',
          productName: 'Lamp',
          quantity: 2,
          sellingCost: Money.fromMajor(500),
          buyingCost: Money.fromMajor(300),
          status: status,
          refundAmount: Money.fromMajor(refund),
        );
    final orders = [
      order('O1', OrderStatus.delivered),
      order('O2', OrderStatus.cancelled),
      order('O3', OrderStatus.returned, refund: 200),
    ];
    const service = ProfitCalculationService();
    final s = service.summariseOrders(orders);
    final recognised = orders.where((o) => o.isRecognised);

    expect(s.count, 3);
    expect(s.cancelledCount, 1);
    expect(s.refundedCount, 1);
    expect(s.recognisedCount, 2);
    expect(s.units, 4);
    expect(s.revenue,
        recognised.fold(Money.zero, (m, o) => m + o.recognisedRevenue));
    expect(s.grossProfit,
        recognised.fold(Money.zero, (m, o) => m + o.recognisedGrossProfit));
    expect(s.refunds, Money.fromMajor(200));
    expect(s.averageOrderValue, s.revenue / 2);
    expect(service.summariseOrders(const []).grossMargin, isNull);
  });

  for (final width in [400.0, 1280.0]) {
    testWidgets('orders list shows its figures, filters and rows at $width px',
        (tester) async {
      final data =
          await _pump(tester, () => const OrdersScreen(), width: width);
      expect(tester.takeException(), isNull);
      expect(find.text('Orders'), findsWidgets);
      expect(find.byType(KpiStrip), findsOneWidget);
      expect(find.text('Gross profit'), findsOneWidget);
      expect(find.text('Avg. order value'), findsOneWidget);
      // A quick filter per status.
      expect(find.text(OrderStatus.delivered.label), findsWidgets);
      expect(find.text('Add Order'), findsOneWidget);
      // Newest first.
      final newest = data.ordersFor(null).reduce((a, b) =>
          (b.orderDate ?? DateTime(0)).isAfter(a.orderDate ?? DateTime(0))
              ? b
              : a);
      expect(find.text(newest.id), findsWidgets);
    });

    testWidgets('order detail shows the header, figures and sections '
        'at $width px', (tester) async {
      late String id;
      await _pump(tester, () {
        return Builder(builder: (context) {
          id = context.read<DataController>().ordersFor(null).first.id;
          return OrderDetailScreen(orderId: id);
        });
      }, width: width);
      expect(tester.takeException(), isNull);
      expect(find.text('Order $id'), findsOneWidget);
      expect(find.text('Total revenue'), findsWidgets);
      expect(find.text('Pricing'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('More'), findsOneWidget);
      if (width < 640) {
        // Phones switch between the sections and the activity.
        expect(find.text('Overview'), findsOneWidget);
      } else {
        expect(find.text('Order details'), findsOneWidget);
      }
    });
  }

  testWidgets('Duplicate opens a prefilled new-order form', (tester) async {
    late String id;
    await _pump(tester, () {
      return Builder(builder: (context) {
        id = context.read<DataController>().ordersFor(null).first.id;
        return OrderDetailScreen(orderId: id);
      });
    }, width: 1280);

    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duplicate'));
    await tester.pumpAndSettle();

    expect(find.text('Duplicate Order'), findsOneWidget);
    expect(find.text('A new order, copied from $id'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a missing order shows not found with a way back',
      (tester) async {
    await _pump(tester, () => const OrderDetailScreen(orderId: 'NOPE'),
        width: 1280);
    expect(find.text('Order not found'), findsOneWidget);
    expect(find.text('Back to Orders'), findsOneWidget);
  });
}
