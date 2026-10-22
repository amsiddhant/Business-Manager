import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:salesforce_business_manager/core/enums.dart';
import 'package:salesforce_business_manager/core/utils/money.dart';
import 'package:salesforce_business_manager/data/demo_seed.dart';
import 'package:salesforce_business_manager/models/campaign.dart';
import 'package:salesforce_business_manager/screens/campaigns/campaign_detail_screen.dart';
import 'package:salesforce_business_manager/screens/campaigns/campaigns_screen.dart';
import 'package:salesforce_business_manager/services/profit_calculation_service.dart';
import 'package:salesforce_business_manager/services/summaries/campaign_summaries.dart';
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
  test('summariseCampaigns rolls up spend, rates and cost per conversion', () {
    Campaign c(String id, int spend, int imp, int clicks, int conv,
            {CampaignStatus status = CampaignStatus.active, int budget = 0}) =>
        Campaign(
          id: id,
          businessId: 'B1',
          productId: 'P1',
          name: id,
          amountInvested: Money.fromMajor(spend),
          budget: Money.fromMajor(budget),
          impressions: imp,
          clicks: clicks,
          conversions: conv,
          status: status,
        );
    const service = ProfitCalculationService();
    final s = service.summariseCampaigns([
      c('A', 600, 10000, 200, 20, budget: 1000),
      c('B', 400, 10000, 100, 5, status: CampaignStatus.paused, budget: 1000),
    ]);
    expect(s.count, 2);
    expect(s.activeCount, 1);
    expect(s.spend, Money.fromMajor(1000));
    expect(s.impressions, 20000);
    expect(s.ctr, closeTo(1.5, 0.001));
    expect(s.conversionRate, closeTo(25 / 300 * 100, 0.001));
    expect(s.budgetUsed, closeTo(50, 0.001));
    expect(s.costPerConversion, Money.fromMajor(40));
    final empty = service.summariseCampaigns(const []);
    expect(empty.costPerConversion, isNull);
    expect(empty.budgetUsed, isNull);
  });

  for (final width in [400.0, 1280.0]) {
    testWidgets('campaigns list shows its figures, filters and rows '
        'at $width px', (tester) async {
      final data =
          await _pump(tester, () => const CampaignsScreen(), width: width);
      expect(tester.takeException(), isNull);
      expect(find.text('Campaigns'), findsWidgets);
      expect(find.byType(KpiStrip), findsOneWidget);
      expect(find.text('Total spend'), findsOneWidget);
      expect(find.text('Cost / conversion'), findsOneWidget);
      // Quick filters for status and for platform.
      expect(find.text(CampaignStatus.active.label), findsWidgets);
      expect(find.text(CampaignPlatform.meta.label), findsWidgets);
      expect(find.text('Add Campaign'), findsOneWidget);
      final first = data.campaignsFor(null).first;
      expect(find.text(first.name), findsWidgets);
    });

    testWidgets('campaign detail shows the header and its 8 metrics '
        'at $width px', (tester) async {
      late String id;
      await _pump(tester, () {
        return Builder(builder: (context) {
          id = context.read<DataController>().campaignsFor(null).first.id;
          return CampaignDetailScreen(campaignId: id);
        });
      }, width: width);
      expect(tester.takeException(), isNull);
      for (final label in [
        'Budget',
        'Amount Invested',
        'Impressions',
        'Clicks',
        'Conversions',
        'CTR',
        'Conv. Rate',
        'Type',
      ]) {
        expect(find.text(label), findsWidgets, reason: label);
      }
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('More'), findsOneWidget);
      if (width < 640) {
        expect(find.text('Overview'), findsOneWidget);
      } else {
        expect(find.text('Campaign details'), findsOneWidget);
      }
    });
  }

  testWidgets('the campaign form keeps the Type field', (tester) async {
    await _pump(tester, () => const CampaignsScreen(), width: 1280);
    await tester.tap(find.text('Add Campaign'));
    await tester.pumpAndSettle();

    expect(find.text('Basics & type'), findsWidgets);
    // Field labels are rich text; the Type field and its helper are there.
    expect(find.text('Type', findRichText: true), findsOneWidget);
    expect(find.text('What the campaign is for. Optional.'), findsOneWidget);
    expect(find.text('Budget & dates'), findsWidgets);
    expect(find.text('Results'), findsWidgets);
    expect(find.text('Notes'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a platform quick filter narrows the campaign list',
      (tester) async {
    final data =
        await _pump(tester, () => const CampaignsScreen(), width: 1280);
    final all = data.campaignsFor(null);
    final tiktok = all.where((c) => c.platform == CampaignPlatform.tiktok);
    final others = all.where((c) => c.platform != CampaignPlatform.tiktok);
    expect(tiktok, isNotEmpty);
    expect(others, isNotEmpty);
    // The chips scroll sideways: bring the platform one into view first.
    await tester.ensureVisible(find.text(CampaignPlatform.tiktok.label).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(CampaignPlatform.tiktok.label).first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text(tiktok.first.name), findsWidgets);
    expect(find.text(others.first.name), findsNothing);
  });

  testWidgets('Duplicate opens a prefilled new-campaign form', (tester) async {
    late Campaign source;
    await _pump(tester, () {
      return Builder(builder: (context) {
        source = context.read<DataController>().campaignsFor(null).first;
        return CampaignDetailScreen(campaignId: source.id);
      });
    }, width: 1280);

    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duplicate'));
    await tester.pumpAndSettle();

    expect(find.text('Duplicate Campaign'), findsOneWidget);
    expect(find.text('A new campaign, copied from ${source.name}'),
        findsOneWidget);
    expect(find.text('${source.name} (copy)'), findsOneWidget);
    expect(find.text('What the campaign is for. Optional.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a missing campaign shows not found with a way back',
      (tester) async {
    await _pump(tester, () => const CampaignDetailScreen(campaignId: 'NOPE'),
        width: 1280);
    expect(find.text('Campaign not found'), findsOneWidget);
    expect(find.text('Back to Campaigns'), findsOneWidget);
  });
}
