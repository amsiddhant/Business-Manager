import 'package:flutter_test/flutter_test.dart';
import 'package:salesforce_business_manager/data/demo_seed.dart';
import 'package:salesforce_business_manager/models/goal.dart';
import 'package:salesforce_business_manager/screens/goals/goal_style.dart';
import 'package:salesforce_business_manager/services/profit_calculation_service.dart';
import 'package:salesforce_business_manager/state/app_state.dart';
import 'package:salesforce_business_manager/state/data_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('GoalStyle.progressOf passes a projection override through', () async {
    SharedPreferences.setMockInitialValues({});
    final appState = await AppState.create();
    await appState.signIn(DemoSeed.ownerEmail, DemoSeed.password);
    while (appState.repository.currentUser == null) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    final data = DataController(appState.repository);
    await data.load();

    final now = DateTime(2026, 6, 15);
    final goal = Goal(
      businessId: data.businesses.first.id,
      period: GoalPeriod.month(2026, 6),
      metric: GoalMetric.revenue,
      target: 100000000,
    );
    List<GoalProgress> run({int? Function(Goal)? projection}) =>
        GoalStyle.progressOf(data, [goal],
            asOf: now, atRiskPercent: 90, projection: projection);

    // Mid-June, nothing near the target: the run rate is the baseline.
    final base = run().single;
    expect(base.projected, isNotNull);

    // A forecast end value replaces the run rate and drives the status.
    final high = run(projection: (_) => 250000000).single;
    expect(high.projected, 250000000);
    expect(high.status, GoalStatus.onTrack);

    final low = run(projection: (_) => 10000000).single;
    expect(low.projected, 10000000);
    expect(low.status, GoalStatus.behind);

    // No forecast for a goal (null): back to the run rate.
    final none = run(projection: (_) => null).single;
    expect(none.projected, base.projected);
    expect(none.status, base.status);
  });
}
