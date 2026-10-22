import '../../core/utils/money.dart';
import '../../models/dealer.dart';
import '../profit_calculation_service.dart';

/// Headline figures for a list of dealers, as listed.
class DealerListSummary {
  const DealerListSummary({
    required this.count,
    required this.activeCount,
    required this.inactiveCount,
    required this.annualCost,
    required this.withWebsite,
  });

  final int count;
  final int activeCount;
  final int inactiveCount;

  /// What active dealers cost over a year (one-time costs count once).
  final Money annualCost;
  final int withWebsite;

  Money get monthlyCost => annualCost / 12;
}

extension DealerSummaries on ProfitCalculationService {
  DealerListSummary summariseDealers(Iterable<Dealer> dealers) {
    var count = 0, active = 0, website = 0;
    var annual = Money.zero;
    for (final d in dealers) {
      count++;
      if (d.url.trim().isNotEmpty) website++;
      if (!d.isActive) continue;
      active++;
      annual += d.costFrequency.isRecurring
          ? d.cost * d.costFrequency.occurrencesPerYear
          : d.cost;
    }
    return DealerListSummary(
      count: count,
      activeCount: active,
      inactiveCount: count - active,
      annualCost: annual,
      withWebsite: website,
    );
  }
}
