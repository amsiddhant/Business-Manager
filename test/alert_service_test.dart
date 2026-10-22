import 'package:flutter_test/flutter_test.dart';
import 'package:salesforce_business_manager/core/enums.dart';
import 'package:salesforce_business_manager/core/utils/money.dart';
import 'package:salesforce_business_manager/models/campaign.dart';
import 'package:salesforce_business_manager/services/alert_service.dart';

const _service = AlertService();
final _today = DateTime(2026, 10, 22, 9);

Campaign _campaign(String id,
        {DateTime? start, DateTime? end, int invested = 0}) =>
    Campaign(
      id: id,
      businessId: 'BIZ-1',
      productId: 'PROD-1',
      name: 'Campaign $id',
      platform: CampaignPlatform.meta,
      startDate: start ?? DateTime(2026, 1, 1),
      endDate: end,
      amountInvested: Money.fromMajor(invested),
      status: CampaignStatus.active,
    );

List<AppAlert> _build({
  List<Campaign> campaigns = const [],
  List<String> warnings = const [],
  bool demoMode = false,
}) =>
    _service.build(
      customers: const [],
      campaigns: campaigns,
      orders: const [],
      expenses: const [],
      products: const [],
      warnings: warnings,
      demoMode: demoMode,
      now: _today,
      currencyOf: (_) => CurrencyCode.inr,
    );

void main() {
  group('robustZ', () {
    const history = <double>[90, 100, 110, 100, 95, 105];

    test('a value far above the median scores high', () {
      expect(AlertService.robustZ(1000, history), greaterThan(4));
    });

    test('a value at or under the median scores nothing', () {
      expect(AlertService.robustZ(100, history), isNull);
      expect(AlertService.robustZ(50, history), isNull);
    });

    test('needs three months with spend', () {
      expect(AlertService.robustZ(1000, const [0, 0, 100, 100]), isNull);
    });

    test('with no spread, more than double the median counts as far', () {
      expect(AlertService.robustZ(250, const [100, 100, 100]),
          double.infinity);
      expect(AlertService.robustZ(150, const [100, 100, 100]), isNull);
    });
  });

  test('stableHash is FNV-1a and the same on every run', () {
    expect(AlertService.stableHash(''), '811c9dc5');
    expect(AlertService.stableHash('a'), 'e40c292c');
    expect(AlertService.stableHash('Some warning'),
        AlertService.stableHash('Some warning'));
    expect(AlertService.stableHash('one'),
        isNot(AlertService.stableHash('two')));
  });

  test('warnings come first, demo mode last', () {
    final alerts = _build(warnings: ['Orders failed'], demoMode: true);
    expect([for (final a in alerts) a.type],
        [AlertType.dataWarning, AlertType.demoMode]);
    expect(alerts.first.severity, AlertSeverity.high);
    expect(alerts.last.severity, AlertSeverity.info);
    expect(alerts.last.key, 'demo-mode');
  });

  test('a campaign ending within a week raises an alert with a stable key',
      () {
    final campaigns = [
      _campaign('CAM-1', end: DateTime(2026, 10, 25)),
      _campaign('CAM-2', end: DateTime(2026, 11, 30)),
      _campaign('CAM-3', end: DateTime(2026, 10, 1)),
    ];
    final alerts = _build(campaigns: campaigns);
    expect(alerts, hasLength(1));
    expect(alerts.single.type, AlertType.campaignEnding);
    expect(alerts.single.key, 'campaign-ending:CAM-1:2026-10-25');
    expect([for (final a in _build(campaigns: campaigns)) a.key],
        [alerts.single.key]);
  });

  test('a marketing spike this month is flagged as unusual spend', () {
    final campaigns = [
      for (final (m, v) in [(4, 90), (5, 100), (6, 110), (7, 100), (8, 95),
        (9, 105)])
        _campaign('CAM-$m', start: DateTime(2026, m, 10), invested: v),
      _campaign('CAM-10', start: DateTime(2026, 10, 5), invested: 1000),
    ];
    final spend = _build(campaigns: campaigns)
        .where((a) => a.type == AlertType.unusualSpend)
        .toList();
    expect(spend, hasLength(1));
    expect(spend.single.key, 'unusual-spend:BIZ-1:Marketing:2026-10');
    expect(spend.single.severity, AlertSeverity.high);
  });
}
