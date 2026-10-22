import '../../core/enums.dart';
import '../../models/business.dart';
import '../profit_calculation_service.dart';

/// Headline counts for the businesses list.
class BusinessPortfolioSummary {
  const BusinessPortfolioSummary({
    required this.total,
    required this.trading,
    required this.closed,
    required this.inactive,
    required this.archived,
    required this.averageTenureDays,
  });

  /// Every business in the list, whatever its state.
  final int total;

  /// Visible and still trading.
  final int trading;

  /// Wound down (lifecycle closed) and not hidden or archived.
  final int closed;

  /// Hidden from active views without being archived.
  final int inactive;

  /// Soft-deleted.
  final int archived;

  /// Mean operating span, in days, over the businesses with a start date;
  /// null when none has one.
  final int? averageTenureDays;
}

extension BusinessSummaries on ProfitCalculationService {
  /// Counts [businesses] by state. A business is counted once: archived wins,
  /// then inactive, then closed, otherwise it is trading.
  BusinessPortfolioSummary summariseBusinesses(
      List<Business> businesses, DateTime asOf) {
    var trading = 0, closed = 0, inactive = 0, archived = 0;
    var tenureDays = 0, tenureCount = 0;
    for (final b in businesses) {
      if (b.status == EntityStatus.archived) {
        archived++;
      } else if (b.status == EntityStatus.inactive) {
        inactive++;
      } else if (b.isClosed) {
        closed++;
      } else {
        trading++;
      }
      final tenure = b.tenure(asOf);
      if (tenure != null) {
        tenureDays += tenure.totalDays;
        tenureCount++;
      }
    }
    return BusinessPortfolioSummary(
      total: businesses.length,
      trading: trading,
      closed: closed,
      inactive: inactive,
      archived: archived,
      averageTenureDays: tenureCount == 0 ? null : tenureDays ~/ tenureCount,
    );
  }
}
