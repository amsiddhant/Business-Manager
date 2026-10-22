import '../../core/enums.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/money.dart';
import '../../models/expense.dart';
import '../profit_calculation_service.dart';

/// Headline figures for the Expenses report.
class ExpenseReportTotals {
  const ExpenseReportTotals({
    required this.count,
    required this.activeCount,
    required this.annualised,
    required this.inPeriod,
  });

  final int count;
  final int activeCount;

  /// Every expense as a yearly figure.
  final Money annualised;

  /// What the expenses cost within the report period (prorated).
  final Money inPeriod;

  /// The yearly figure averaged over a month.
  Money get monthlyRunRate => annualised / 12;
}

/// Headline figures for the Marketing report.
class MarketingReportTotals {
  const MarketingReportTotals({
    required this.count,
    required this.spend,
    required this.attributedRevenue,
    required this.clicks,
    required this.conversions,
  });

  final int count;
  final Money spend;
  final Money attributedRevenue;
  final int clicks;
  final int conversions;

  /// Attributed revenue per unit spent; null without spend.
  double? get roas => spend.isZero ? null : attributedRevenue.major / spend.major;

  /// (revenue − spend) ÷ spend as a %; null without spend.
  double? get roi => spend.isZero
      ? null
      : (attributedRevenue - spend).major / spend.major * 100;

  /// Conversions per click as a %; null without clicks.
  double? get conversionRate =>
      clicks == 0 ? null : conversions / clicks * 100;
}

/// Headline figures for the Product profitability report.
class ProductReportTotals {
  const ProductReportTotals({
    required this.count,
    required this.sellingCount,
    required this.orders,
    required this.units,
    required this.revenue,
    required this.productCost,
    required this.marketingCost,
  });

  final int count;

  /// Products with at least one recognised order in the period.
  final int sellingCount;
  final int orders;
  final int units;
  final Money revenue;
  final Money productCost;
  final Money marketingCost;

  Money get grossProfit => revenue - productCost;
  Money get netProfit => revenue - productCost - marketingCost;
  double get margin => revenue.isZero ? 0 : netProfit.major / revenue.major * 100;
}

/// Report-page aggregates, kept out of the widgets.
extension ReportsSummaries on ProfitCalculationService {
  ExpenseReportTotals expenseReportTotals(
      Iterable<Expense> expenses, DateRange range) {
    var count = 0, active = 0;
    var annualised = Money.zero, inPeriod = Money.zero;
    for (final e in expenses) {
      count++;
      if (e.status == EntityStatus.active) active++;
      annualised += e.annualisedAmount;
      inPeriod += proratedExpense(e, range);
    }
    return ExpenseReportTotals(
      count: count,
      activeCount: active,
      annualised: annualised,
      inPeriod: inPeriod,
    );
  }

  MarketingReportTotals marketingReportTotals(
      Iterable<CampaignPerformance> rows) {
    var count = 0, clicks = 0, conversions = 0;
    var spend = Money.zero, revenue = Money.zero;
    for (final p in rows) {
      count++;
      clicks += p.campaign.clicks;
      conversions += p.campaign.conversions;
      spend += p.spend;
      revenue += p.attributedRevenue;
    }
    return MarketingReportTotals(
      count: count,
      spend: spend,
      attributedRevenue: revenue,
      clicks: clicks,
      conversions: conversions,
    );
  }

  ProductReportTotals productReportTotals(Iterable<ProductProfit> rows) {
    var count = 0, selling = 0, orders = 0, units = 0;
    var revenue = Money.zero, cost = Money.zero, marketing = Money.zero;
    for (final p in rows) {
      count++;
      if (p.orderCount > 0) selling++;
      orders += p.orderCount;
      units += p.unitsSold;
      revenue += p.revenue;
      cost += p.productCost;
      marketing += p.marketingCost;
    }
    return ProductReportTotals(
      count: count,
      sellingCount: selling,
      orders: orders,
      units: units,
      revenue: revenue,
      productCost: cost,
      marketingCost: marketing,
    );
  }

  /// The sum of several profit summaries (same currency).
  ProfitSummary sumProfitSummaries(Iterable<ProfitSummary> summaries) {
    var revenue = Money.zero,
        cost = Money.zero,
        marketing = Money.zero,
        operating = Money.zero;
    var orders = 0, units = 0;
    for (final s in summaries) {
      revenue += s.revenue;
      cost += s.productCost;
      marketing += s.marketingCost;
      operating += s.operatingExpenses;
      orders += s.orderCount;
      units += s.unitsSold;
    }
    return ProfitSummary(
      revenue: revenue,
      productCost: cost,
      marketingCost: marketing,
      operatingExpenses: operating,
      orderCount: orders,
      unitsSold: units,
    );
  }
}
