import '../../core/utils/money.dart';
import 'smart_config.dart';

/// Unusual-spend scoring (pure; 0 reads). The Dart baseline is a robust
/// z-score (median / MAD) of this month against the previous months; the
/// on-device model's seasonal-residual scores replace it when available.
class AnomalyService {
  const AnomalyService();

  /// How far [value] sits above [history]'s median, in robust standard
  /// deviations (median absolute deviation × 1.4826). Null when there isn't
  /// enough history (3+ months with spend) or [value] isn't above the median.
  /// With no spread at all, anything over double the median counts as far.
  static double? robustZ(double value, List<double> history) {
    if (history.where((v) => v > 0).length < 3) return null;
    final median = _median(history);
    if (value <= median) return null;
    final mad = _median([for (final v in history) (v - median).abs()]);
    if (mad == 0) {
      return median > 0 && value > median * 2 ? double.infinity : null;
    }
    return (value - median) / (mad * 1.4826);
  }

  static double _median(List<double> values) {
    final sorted = [...values]..sort();
    final mid = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[mid]
        : (sorted[mid - 1] + sorted[mid]) / 2;
  }

  /// Per cost line of [monthly] (oldest first, last = this month so far, as
  /// from `ProfitCalculationService.monthlySpendByCategory`): the robust z
  /// of the last month against the others. Lines with no score are left out.
  Map<String, double> scores(Map<String, List<Money>> monthly) {
    final result = <String, double>{};
    monthly.forEach((line, months) {
      if (months.length < 2) return;
      final past = [
        for (final m in months.take(months.length - 1)) m.major,
      ];
      final z = robustZ(months.last.major, past);
      if (z != null) result[line] = z;
    });
    return result;
  }

  /// Whether [months] has enough history for the on-device model
  /// ([SmartConfig.anomalyMinMonths] months before this one,
  /// [SmartConfig.anomalyMinSpendMonths] of them with spend).
  static bool enoughForModel(List<Money> months) {
    if (months.isEmpty) return false;
    final before = months.take(months.length - 1).toList();
    return before.length >= SmartConfig.anomalyMinMonths &&
        before.where((m) => m.isPositive).length >=
            SmartConfig.anomalyMinSpendMonths;
  }
}
