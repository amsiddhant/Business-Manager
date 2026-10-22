import 'package:flutter_test/flutter_test.dart';
import 'package:salesforce_business_manager/core/utils/money.dart';
import 'package:salesforce_business_manager/services/alert_service.dart';
import 'package:salesforce_business_manager/services/smart/anomaly_service.dart';

List<Money> _m(List<int> major) => [for (final v in major) Money.fromMajor(v)];

void main() {
  group('robustZ', () {
    const history = <double>[90, 100, 110, 100, 95, 105];

    test('a value far above the median scores high', () {
      expect(AnomalyService.robustZ(1000, history), greaterThan(4));
    });

    test('a value at or under the median scores nothing', () {
      expect(AnomalyService.robustZ(100, history), isNull);
      expect(AnomalyService.robustZ(50, history), isNull);
    });

    test('needs three months with spend', () {
      expect(AnomalyService.robustZ(1000, const [0, 0, 100, 100]), isNull);
    });

    test('with no spread, more than double the median counts as far', () {
      expect(AnomalyService.robustZ(250, const [100, 100, 100]),
          double.infinity);
      expect(AnomalyService.robustZ(150, const [100, 100, 100]), isNull);
    });

    test('matches AlertService.robustZ', () {
      for (final v in <double>[0, 50, 100, 150, 250, 1000]) {
        for (final h in const [
          <double>[90, 100, 110, 100, 95, 105],
          <double>[0, 0, 100, 100],
          <double>[100, 100, 100],
          <double>[],
        ]) {
          expect(AnomalyService.robustZ(v, h), AlertService.robustZ(v, h));
        }
      }
    });
  });

  group('scores', () {
    test('scores the last month against the earlier ones', () {
      final scores = const AnomalyService().scores({
        'Hosting': _m([100, 110, 90, 100, 105, 1000]),
        'Steady': _m([100, 110, 90, 100, 105, 95]),
        'Sparse': _m([0, 0, 100, 0, 0, 500]),
        'One': _m([500]),
      });
      expect(scores.keys, ['Hosting']);
      expect(scores['Hosting'], greaterThan(4));
    });
  });

  group('enoughForModel', () {
    test('needs 12 months before this one, 9 with spend', () {
      expect(AnomalyService.enoughForModel(_m(List.filled(13, 100))), isTrue);
      expect(AnomalyService.enoughForModel(_m(List.filled(12, 100))), isFalse);
      final sparse = _m([...List.filled(9, 100), 0, 0, 0, 500]);
      expect(AnomalyService.enoughForModel(sparse), isTrue);
      final tooSparse = _m([...List.filled(8, 100), 0, 0, 0, 0, 500]);
      expect(AnomalyService.enoughForModel(tooSparse), isFalse);
      expect(AnomalyService.enoughForModel(const []), isFalse);
    });

    test('this month does not count toward the history', () {
      final months = _m([...List.filled(8, 100), 0, 0, 0, 0, 500]);
      expect(AnomalyService.enoughForModel(months), isFalse);
    });
  });
}
