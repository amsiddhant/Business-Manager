import '../core/enums.dart';
import '../core/utils/date_utils.dart';
import '../core/utils/money.dart';
import '../models/order.dart';
import '../services/insight_service.dart';
import '../services/profit_calculation_service.dart';
import '../state/data_controller.dart';
import '../state/filter_controller.dart';
import '../state/memo.dart';

/// Everything the dashboard shows, computed once per data change and
/// selection rather than on every build. All figures come from
/// [ProfitCalculationService]; this class only gathers them.
class DashboardViewModel {
  DashboardViewModel._({
    required this.currency,
    required this.range,
    required this.window,
    required this.basis,
    required this.summary,
    required this.comparison,
    required this.productProfit,
    required this.campaignPerformance,
    required this.series,
    required this.breakdown,
    required this.trailing,
    required this.waterfall,
    required this.platformMix,
    required this.statusBreakdown,
    required this.businessComparison,
    required this.projection,
    required this.forecast,
    required this.insights,
    required this.orders,
  });

  static const _service = ProfitCalculationService();
  static const _insights = InsightService();
  static final StampedMemo _memo = StampedMemo();

  /// The view model for the current data and selection (cached).
  static DashboardViewModel of(
    DataController data,
    FilterController filter, {
    DateTime? now,
  }) {
    final n = now ?? DateTime.now();
    return _memo.get(
      // The instance too: a fresh controller starts its version from 0 again.
      (data, data.version),
      (filter.key, filter.periodType, filter.comparison, AppDate.iso(n)),
      () => _build(data, filter, n),
    );
  }

  static DashboardViewModel _build(
      DataController data, FilterController filter, DateTime now) {
    final bizId = filter.selectedBusinessId;
    final range = filter.range;
    final orders = data.ordersFor(bizId);
    final campaigns = data.campaignsFor(bizId);
    final expenses = data.expensesFor(bizId);
    final products = data.productsFor(bizId);
    final currency = (bizId == null ? null : data.businessById(bizId))
            ?.currency ??
        CurrencyCode.inr;

    ProfitSummary summarise(DateRange r) => _service.summarise(
        orders: orders, campaigns: campaigns, expenses: expenses, range: r);

    final summary = summarise(range);
    final window = filter.comparisonWindow(now: now);
    final current = window.isToDate ? summarise(window.current) : summary;
    final comparison = _service.compare(current, summarise(window.previous));

    final productProfit = _service.productProfitability(
        products: products, orders: orders, campaigns: campaigns, range: range);
    final campaignPerformance = _service.campaignPerformance(
        campaigns: campaigns, orders: orders, range: range);
    final series = _service.timeSeries(
        orders: orders, campaigns: campaigns, expenses: expenses, range: range);

    final today = AppDate.dayOnly(now);
    final asOf = range.end.isBefore(today) ? range.end : today;
    final projection = window.isToDate
        ? _service.projectRunRate(toDate: current, range: range, asOf: today)
        : null;

    final selectable = data.selectableBusinesses;
    final businessComparison = bizId == null && selectable.length > 1
        ? _service.summariseByBusiness(
            businesses: selectable,
            orders: orders,
            campaigns: campaigns,
            expenses: expenses,
            range: range)
        : const <BusinessSummary>[];

    return DashboardViewModel._(
      currency: currency,
      range: range,
      window: window,
      basis: filter.comparison,
      summary: summary,
      comparison: comparison,
      productProfit: productProfit,
      campaignPerformance: campaignPerformance,
      series: series,
      breakdown: _service.expenseBreakdown(
          orders: orders,
          campaigns: campaigns,
          expenses: expenses,
          range: range),
      trailing: _service.trailingMonths(
          orders: orders, campaigns: campaigns, expenses: expenses, asOf: asOf),
      waterfall: _service.profitWaterfall(summary),
      platformMix: _service.marketingByPlatform(campaigns, range),
      statusBreakdown: _service.orderStatusBreakdown(orders, range),
      businessComparison: businessComparison,
      projection: projection,
      forecast: _service.projectSeries(series, projection, today),
      insights: _insights.build(
        comparison: comparison,
        basis: filter.comparison,
        isToDate: window.isToDate,
        products: productProfit,
        campaigns: campaignPerformance,
        monthlySpend: _service.monthlySpendByCategory(
            campaigns: campaigns, expenses: expenses, asOf: today),
        customers: data.customersFor(bizId),
        businessId: bizId,
        currency: currency,
        now: now,
      ),
      orders: orders,
    );
  }

  /// The selected business's currency; INR for All Businesses.
  final CurrencyCode currency;
  final DateRange range;
  final ComparisonWindow window;
  final ComparisonBasis basis;

  /// The whole selected period (the scorecards).
  final ProfitSummary summary;

  /// For the deltas: the period (to date, when running) against its
  /// comparison period.
  final ProfitComparison comparison;

  final List<ProductProfit> productProfit;
  final List<CampaignPerformance> campaignPerformance;
  final List<TimeSeriesPoint> series;
  final List<CategorySlice> breakdown;

  /// The 12 months up to the period's end (or today): the sparklines.
  final List<TimeSeriesPoint> trailing;
  final List<WaterfallStep> waterfall;
  final Map<CampaignPlatform, Money> platformMix;
  final Map<OrderStatus, int> statusBreakdown;

  /// Per business, for All Businesses with more than one; otherwise empty.
  final List<BusinessSummary> businessComparison;

  /// The run-rate landing point while the period is running.
  final PeriodProjection? projection;
  final List<ForecastPoint> forecast;
  final List<Insight> insights;

  /// The scoped orders (the Recent Orders table filters them by [range]).
  final List<Order> orders;

  /// [metric] over the trailing 12 months, oldest first.
  List<double> trend(KpiMetric metric) =>
      [for (final p in trailing) metric.valueOfPoint(p)];
}
