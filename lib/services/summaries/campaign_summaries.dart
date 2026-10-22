import '../../core/enums.dart';
import '../../core/utils/money.dart';
import '../../models/campaign.dart';
import '../profit_calculation_service.dart';

/// Headline figures for a set of campaigns (the Campaigns list KPI strip).
class CampaignSummary {
  const CampaignSummary({
    required this.count,
    required this.activeCount,
    required this.spend,
    required this.budget,
    required this.impressions,
    required this.clicks,
    required this.conversions,
  });

  final int count;
  final int activeCount;
  final Money spend;
  final Money budget;
  final int impressions;
  final int clicks;
  final int conversions;

  /// Click-through rate in percent.
  double get ctr => impressions == 0 ? 0 : clicks / impressions * 100;

  /// Conversions per click in percent.
  double get conversionRate => clicks == 0 ? 0 : conversions / clicks * 100;

  /// Spend as a share of the budget, in percent; null with no budget.
  double? get budgetUsed =>
      budget.isPositive ? spend.minor / budget.minor * 100 : null;

  /// Spend per conversion; null when nothing converted.
  Money? get costPerConversion =>
      conversions == 0 ? null : spend / conversions;
}

extension CampaignSummaries on ProfitCalculationService {
  /// Rolls [campaigns] up into spend, reach and conversion figures.
  CampaignSummary summariseCampaigns(Iterable<Campaign> campaigns) {
    var count = 0;
    var active = 0;
    var spend = Money.zero;
    var budget = Money.zero;
    var impressions = 0;
    var clicks = 0;
    var conversions = 0;
    for (final c in campaigns) {
      count++;
      if (c.status == CampaignStatus.active) active++;
      spend += c.amountInvested;
      budget += c.budget;
      impressions += c.impressions;
      clicks += c.clicks;
      conversions += c.conversions;
    }
    return CampaignSummary(
      count: count,
      activeCount: active,
      spend: spend,
      budget: budget,
      impressions: impressions,
      clicks: clicks,
      conversions: conversions,
    );
  }
}
