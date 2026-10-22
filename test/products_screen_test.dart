import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:salesforce_business_manager/core/enums.dart';
import 'package:salesforce_business_manager/core/utils/money.dart';
import 'package:salesforce_business_manager/data/demo_seed.dart';
import 'package:salesforce_business_manager/models/product.dart';
import 'package:salesforce_business_manager/screens/products/product_detail_screen.dart';
import 'package:salesforce_business_manager/screens/products/products_screen.dart';
import 'package:salesforce_business_manager/services/profit_calculation_service.dart';
import 'package:salesforce_business_manager/services/summaries/product_summaries.dart';
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
  test('summariseProducts rolls up counts, categories and margin', () {
    Product p(String id, int buy, int sell,
            {String category = '', EntityStatus status = EntityStatus.active}) =>
        Product(
          id: id,
          businessId: 'B1',
          name: id,
          buyingPrice: Money.fromMajor(buy),
          sellingPrice: Money.fromMajor(sell),
          category: category,
          status: status,
        );
    const service = ProfitCalculationService();
    final s = service.summariseProducts([
      p('A', 50, 100, category: 'Audio'),
      p('B', 75, 100, category: 'audio'),
      p('C', 0, 0, status: EntityStatus.inactive),
    ]);
    expect(s.count, 3);
    expect(s.activeCount, 2);
    expect(s.inactiveCount, 1);
    expect(s.categoryCount, 1);
    expect(s.averageSellingPrice, Money.fromMajor(100));
    expect(s.averageBuyingPrice, Money.fromMajor(62.5));
    expect(s.averageMarkup, closeTo(37.5, 0.001));
    expect(service.summariseProducts(const []).averageMarkup, isNull);
  });

  for (final width in [400.0, 1280.0]) {
    testWidgets('products list shows its figures, filters and rows '
        'at $width px', (tester) async {
      final data =
          await _pump(tester, () => const ProductsScreen(), width: width);
      expect(tester.takeException(), isNull);
      expect(find.text('Products'), findsWidgets);
      expect(find.byType(KpiStrip), findsOneWidget);
      expect(find.text('Avg. selling price'), findsOneWidget);
      expect(find.text('Avg. list margin'), findsOneWidget);
      // A quick filter per status.
      expect(find.text(EntityStatus.active.label), findsWidgets);
      expect(find.text('Add Product'), findsOneWidget);
      expect(find.text('Import CSV'), findsOneWidget);
      expect(find.text('Export CSV'), findsOneWidget);
      final first = data.productsFor(null).first;
      expect(find.text(first.id), findsWidgets);
    });

    testWidgets('product detail shows the header, 10 metrics and both tables '
        'at $width px', (tester) async {
      late String id;
      await _pump(tester, () {
        return Builder(builder: (context) {
          id = context.read<DataController>().productsFor(null).first.id;
          return ProductDetailScreen(productId: id);
        });
      }, width: width);
      expect(tester.takeException(), isNull);
      for (final label in [
        'Buying Price',
        'Selling Price',
        'Total Orders',
        'Units Sold',
        'Revenue',
        'Product Cost',
        'Marketing Cost',
        'Gross Profit',
        'Net Profit',
        'Margin',
      ]) {
        expect(find.text(label), findsWidgets, reason: label);
      }
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('More'), findsOneWidget);
      if (width < 640) {
        expect(find.text('Overview'), findsOneWidget);
      } else {
        expect(find.text('Product Campaigns'), findsOneWidget);
        expect(find.text('Product Orders'), findsOneWidget);
      }
    });
  }

  testWidgets('a quick filter narrows the product list', (tester) async {
    final data =
        await _pump(tester, () => const ProductsScreen(), width: 1280);
    final all = data.productsFor(null);
    expect(all.every((p) => p.status == EntityStatus.active), isTrue,
        reason: 'demo products are all active');
    await tester.tap(find.text(EntityStatus.archived.label).first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text(all.first.id), findsNothing);
  });

  testWidgets('Duplicate opens a prefilled new-product form', (tester) async {
    late Product source;
    await _pump(tester, () {
      return Builder(builder: (context) {
        source = context.read<DataController>().productsFor(null).first;
        return ProductDetailScreen(productId: source.id);
      });
    }, width: 1280);

    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duplicate'));
    await tester.pumpAndSettle();

    expect(find.text('Duplicate Product'), findsOneWidget);
    expect(find.text('A new product, copied from ${source.name}'),
        findsOneWidget);
    expect(find.text('Basics'), findsWidgets);
    expect(find.text('Pricing'), findsWidgets);
    expect(find.text('${source.name} (copy)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a missing product shows not found with a way back',
      (tester) async {
    await _pump(tester, () => const ProductDetailScreen(productId: 'NOPE'),
        width: 1280);
    expect(find.text('Product not found'), findsOneWidget);
    expect(find.text('Back to Products'), findsOneWidget);
  });
}
