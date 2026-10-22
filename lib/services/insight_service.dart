import '../core/enums.dart';
import '../core/routing/app_routes.dart';
import '../core/utils/date_utils.dart';
import '../core/utils/money.dart';
import '../models/customer.dart';
import 'alert_service.dart';
import 'profit_calculation_service.dart';

enum InsightTone { positive, negative, warning, neutral }

enum InsightKind {
  revenueChange,
  marginChange,
  concentration,
  weakCampaigns,
  bestCampaign,
  spendSpike,
  contractsExpiring,
}

/// A plain-language observation about the selected period.
class Insight {
  const Insight({
    required this.kind,
    required this.tone,
    required this.title,
    required this.message,
    this.route,
  });

  final InsightKind kind;
  final InsightTone tone;
  final String title;
  final String message;

  /// Where tapping the insight goes.
  final String? route;
}

/// Turns the dashboard's figures into a short list of insights. Pure and
/// deterministic: the same figures always give the same insights, and it only
/// reads [ProfitCalculationService] outputs.
class InsightService {
  const InsightService();

  /// A change this large (%) in revenue is worth mentioning.
  static const revenueChangePercent = 10.0;

  /// A move this large in net margin (percentage points).
  static const marginChangePoints = 3.0;

  /// One product bringing more than this share (%) of revenue.
  static const concentrationPercent = 40.0;

  /// A cost line this many times its 3-month average.
  static const spikeRatio = 1.5;

  List<Insight> build({
    required ProfitComparison comparison,
    required ComparisonBasis basis,
    required bool isToDate,
    required List<ProductProfit> products,
    required List<CampaignPerformance> campaigns,
    required Map<String, List<Money>> monthlySpend,
    required List<Customer> customers,
    required String? businessId,
    required CurrencyCode currency,
    required DateTime now,
    int max = 6,
  }) {
    String money(Money m) => MoneyFormatter.format(m, currency);
    final vs = isToDate ? '${basis.shortLabel}, to date' : basis.shortLabel;
    final insights = <Insight>[];

    // Revenue change.
    final revenue = comparison[KpiMetric.revenue];
    if (revenue.change case final c? when c.abs() >= revenueChangePercent) {
      insights.add(Insight(
        kind: InsightKind.revenueChange,
        tone: c > 0 ? InsightTone.positive : InsightTone.negative,
        title: 'Revenue ${c > 0 ? 'up' : 'down'} '
            '${PercentFormatter.format(c.abs())}',
        message: '${money(comparison.current.revenue)} against '
            '${money(comparison.previous.revenue)} ($vs).',
        route: '${Routes.reports}?tab=sales',
      ));
    }

    // Net margin move.
    final margin = comparison[KpiMetric.netMargin];
    if (margin.change case final c? when c.abs() >= marginChangePoints) {
      insights.add(Insight(
        kind: InsightKind.marginChange,
        tone: c > 0 ? InsightTone.positive : InsightTone.negative,
        title: 'Net margin ${c > 0 ? 'up' : 'down'} '
            '${c.abs().toStringAsFixed(1)} pts',
        message: '${PercentFormatter.format(margin.current)} now, from '
            '${PercentFormatter.format(margin.previous!)} ($vs).',
        route: '${Routes.reports}?tab=business',
      ));
    }

    // Revenue concentration.
    final selling = [
      for (final p in products)
        if (p.revenue.isPositive) p,
    ]..sort((a, b) => b.revenue.minor.compareTo(a.revenue.minor));
    final total = selling.fold(Money.zero, (sum, p) => sum + p.revenue);
    if (selling.length >= 2 && total.isPositive) {
      final top = selling.first;
      final share = top.revenue.major / total.major * 100;
      if (share > concentrationPercent) {
        insights.add(Insight(
          kind: InsightKind.concentration,
          tone: InsightTone.warning,
          title: '${top.product.name} brings '
              '${PercentFormatter.format(share, decimals: 0)} of revenue',
          message: 'A lot rides on one product. ${money(top.revenue)} of '
              '${money(total)} this period.',
          route: Routes.productDetailPath(top.product.id),
        ));
      }
    }

    // Campaign returns.
    final spending = [
      for (final c in campaigns)
        if (c.spend.isPositive && c.roas != null) c,
    ];
    final weak = [
      for (final c in spending)
        if (c.roas! < 1) c,
    ];
    if (weak.isNotEmpty) {
      final lost = weak.fold(
          Money.zero, (sum, c) => sum + (c.spend - c.attributedRevenue));
      insights.add(Insight(
        kind: InsightKind.weakCampaigns,
        tone: InsightTone.negative,
        title: weak.length == 1
            ? '${weak.first.campaign.name} returns less than it costs'
            : '${weak.length} campaigns return less than they cost',
        message: 'ROAS under 1× — ${money(lost)} more spent than earned back.',
        route: weak.length == 1
            ? Routes.campaignDetailPath(weak.first.campaign.id)
            : Routes.campaigns,
      ));
    }
    if (spending.length >= 2) {
      final best =
          spending.reduce((a, b) => (b.roas! > a.roas!) ? b : a);
      if (best.roas! >= 1) {
        insights.add(Insight(
          kind: InsightKind.bestCampaign,
          tone: InsightTone.positive,
          title: 'Best return: ${best.campaign.name}',
          message: '${PercentFormatter.roas(best.roas)} ROAS on '
              '${money(best.spend)} of spend.',
          route: Routes.campaignDetailPath(best.campaign.id),
        ));
      }
    }

    // A cost line well above its recent average.
    Insight? spike;
    var spikeBy = 0.0;
    for (final MapEntry(key: line, value: months) in monthlySpend.entries) {
      if (months.length < 4) continue;
      final current = months.last.major;
      final prior = months.sublist(months.length - 4, months.length - 1);
      final average = prior.fold(0.0, (s, m) => s + m.major) / prior.length;
      if (average <= 0) continue;
      final ratio = current / average;
      if (ratio >= spikeRatio && ratio > spikeBy) {
        spikeBy = ratio;
        spike = Insight(
          kind: InsightKind.spendSpike,
          tone: InsightTone.warning,
          title: '$line spend is ${ratio.toStringAsFixed(1)}× usual',
          message: '${money(months.last)} this month so far, against a '
              '3-month average of ${money(Money.fromMajor(average))}.',
          route: line == 'Marketing' ? Routes.campaigns : Routes.expenses,
        );
      }
    }
    if (spike != null) insights.add(spike);

    // Renewals coming up.
    final due = contractsDue(customers,
        now: now, fromDays: 0, toDays: 30, businessId: businessId);
    if (due.isNotEmpty) {
      final value =
          due.fold(Money.zero, (sum, d) => sum + d.contract.annualTotal);
      insights.add(Insight(
        kind: InsightKind.contractsExpiring,
        tone: InsightTone.warning,
        title: due.length == 1
            ? '${due.first.customer.name}’s contract expires soon'
            : '${due.length} contracts expire within 30 days',
        message: '${money(value)} a year up for renewal. The first one is '
            '${due.first.daysLeft == 0 ? 'today' : 'in ${due.first.daysLeft} '
                'day${due.first.daysLeft == 1 ? '' : 's'}'}.',
        route: due.length == 1
            ? Routes.customerDetailPath(due.first.customer.id)
            : Routes.customers,
      ));
    }

    return insights.take(max).toList();
  }
}
