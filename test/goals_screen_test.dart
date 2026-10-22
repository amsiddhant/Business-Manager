import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:salesforce_business_manager/data/demo_seed.dart';
import 'package:salesforce_business_manager/models/goal.dart';
import 'package:salesforce_business_manager/screens/goals/goals_screen.dart';
import 'package:salesforce_business_manager/screens/goals/widgets/goal_card.dart';
import 'package:salesforce_business_manager/screens/goals/widgets/goals_summary_card.dart';
import 'package:salesforce_business_manager/screens/goals/widgets/progress_ring.dart';
import 'package:salesforce_business_manager/state/app_state.dart';
import 'package:salesforce_business_manager/state/data_controller.dart';
import 'package:salesforce_business_manager/state/filter_controller.dart';
import 'package:salesforce_business_manager/state/user_prefs.dart';
import 'package:salesforce_business_manager/widgets/common/status_badge.dart';
import 'package:shared_preferences/shared_preferences.dart';

late AppState _appState;
late DataController _data;
late FilterController _filter;

/// [child] with the app's state, signed in as [email] on demo data. (A bare
/// theme: the real one fetches Inter, which tests can't.)
Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  required double width,
  String email = DemoSeed.ownerEmail,
  bool goalsUnavailable = false,
  Future<void> Function()? beforeLoad,
  double height = 2400,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({});
  await tester.runAsync(() async {
    _appState = await AppState.create();
    await _appState.signIn(email, DemoSeed.password);
    // The profile lands just after sign-in; a load before it is discarded.
    while (_appState.repository.currentUser == null) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    await beforeLoad?.call();
    _data = DataController(_appState.repository);
    await _data.load();
  });
  _data.goalsUnavailable = goalsUnavailable;
  _filter = FilterController();
  final userPrefs = UserPrefs(_appState.prefs)
    ..bindUser(_appState.currentUser?.uid);

  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<AppState>.value(value: _appState),
      ChangeNotifierProvider<DataController>.value(value: _data),
      ChangeNotifierProvider<FilterController>.value(value: _filter),
      ChangeNotifierProvider<UserPrefs>.value(value: userPrefs),
    ],
    child: MaterialApp(home: Scaffold(body: Builder(builder: (_) => child))),
  ));
  await tester.pumpAndSettle();
}

Goal _thisMonth(String businessId,
        {GoalMetric metric = GoalMetric.revenue, int target = 100000000}) =>
    Goal(
      businessId: businessId,
      period: GoalPeriod.containing(GoalPeriodType.month, DateTime.now()),
      metric: metric,
      target: target,
    );

void main() {
  testWidgets('the owner can set goals for all businesses', (tester) async {
    await _pump(tester, const GoalsScreen(), width: 1280);
    expect(tester.takeException(), isNull);
    expect(find.text('Goals'), findsWidgets);
    expect(find.text('All businesses'), findsOneWidget);
    expect(find.text('Set goals'), findsOneWidget);
    // Nothing set yet.
    expect(find.byType(GoalCard), findsNothing);
    expect(find.textContaining('No goals for'), findsOneWidget);
  });

  testWidgets('a saved goal shows as a card with its status', (tester) async {
    await _pump(tester, const GoalsScreen(), width: 1280);
    await tester.runAsync(() async {
      await _appState.repository.saveGoal(_thisMonth(Goal.allBusinesses));
      // The change stream reaches the data controller a moment later.
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(GoalCard), findsOneWidget);
    expect(find.byType(ProgressRing), findsOneWidget);
    expect(find.text('Revenue'), findsWidgets);
    expect(find.byType(StatusBadge), findsOneWidget);
    expect(
      find.byWidgetPredicate((w) =>
          w is Semantics &&
          (w.properties.label?.startsWith('Revenue, ') ?? false)),
      findsOneWidget,
    );
    expect(find.text('Year at a glance'), findsOneWidget);
    // The period controls step through months.
    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
    expect(find.byType(GoalCard), findsNothing);
    await tester.tap(find.text('Current'));
    await tester.pumpAndSettle();
    expect(find.byType(GoalCard), findsOneWidget);
  });

  testWidgets('setting a goal from the editor saves it', (tester) async {
    await _pump(tester, const GoalsScreen(), width: 1280);
    await tester.tap(find.text('Set goals'));
    await tester.pumpAndSettle();
    expect(find.text('Save goals'), findsOneWidget);
    expect(find.text('Split a yearly total…'), findsNothing);

    // The first cell is the first month's revenue target.
    await tester.enterText(find.byType(TextField).first, '250000');
    await tester.tap(find.text('Save goals'));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(_data.goalsFor(null), hasLength(1));
    expect(_data.goalsFor(null).single.target, 25000000);
    expect(_data.goalsFor(null).single.metric, GoalMetric.revenue);
    expect(find.text('Saved 1 goal'), findsOneWidget);
  });

  testWidgets('staff cannot set goals for all businesses', (tester) async {
    await _pump(tester, const GoalsScreen(),
        width: 1280, email: DemoSeed.userEmail);
    expect(tester.takeException(), isNull);
    expect(find.text('Set goals'), findsNothing);
    expect(find.text('Goals for all businesses are set by the owner.'),
        findsOneWidget);
  });

  testWidgets('the owner is told how to turn goals on', (tester) async {
    await _pump(tester, const GoalsScreen(),
        width: 1280, goalsUnavailable: true);
    expect(find.text('Set goals'), findsNothing);
    expect(
      find.textContaining('firebase deploy --only firestore:rules',
          findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('others are told goals are not available yet', (tester) async {
    await _pump(tester, const GoalsScreen(),
        width: 1280, email: DemoSeed.userEmail, goalsUnavailable: true);
    expect(find.text("Goals aren't available yet."), findsOneWidget);
    expect(find.textContaining('firestore:rules', findRichText: true),
        findsNothing);
  });

  for (final width in [400.0, 1280.0]) {
    testWidgets('goals lay out at $width px', (tester) async {
      await _pump(tester, const GoalsScreen(), width: width, beforeLoad: () async {
        final repo = _appState.repository;
        await repo.saveGoals([
          _thisMonth(Goal.allBusinesses),
          _thisMonth(Goal.allBusinesses, metric: GoalMetric.orders, target: 50),
          _thisMonth(Goal.allBusinesses,
              metric: GoalMetric.netProfit, target: 1),
        ]);
      });
      expect(tester.takeException(), isNull);
      expect(find.byType(GoalCard), findsNWidgets(3));
      expect(find.text('Achieved'), findsWidgets); // The ₹0.01 profit goal.
    });
  }

  testWidgets('the dashboard card shows running goals and nothing without',
      (tester) async {
    await _pump(tester, const GoalsSummaryCard(), width: 1280);
    expect(find.text('Goals'), findsNothing);

    await _pump(tester, const GoalsSummaryCard(), width: 400,
        beforeLoad: () => _appState.repository
            .saveGoal(_thisMonth(Goal.allBusinesses))
            .then((_) {}));
    expect(tester.takeException(), isNull);
    expect(find.text('Goals'), findsOneWidget);
    expect(find.text('View all'), findsOneWidget);
    expect(find.byType(ProgressRing), findsOneWidget);

    // Without a router, "View all" does nothing rather than crash.
    await tester.tap(find.text('View all'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the dashboard card offers to set this month\'s goals',
      (tester) async {
    await _pump(tester, const GoalsSummaryCard(), width: 1280,
        beforeLoad: () => _appState.repository
            .saveGoal(Goal(
              businessId: Goal.allBusinesses,
              period: GoalPeriod.containing(GoalPeriodType.month, DateTime.now())
                  .previous
                  .previous,
              metric: GoalMetric.revenue,
              target: 100,
            ))
            .then((_) {}));
    expect(find.text('No goals for this month'), findsOneWidget);
    expect(find.text('Set goals'), findsOneWidget);
  });
}
