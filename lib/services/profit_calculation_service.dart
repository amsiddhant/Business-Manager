import '../core/enums.dart';
import '../core/utils/date_utils.dart';
import '../core/utils/money.dart';
import '../models/business.dart';
import '../models/campaign.dart';
import '../models/expense.dart';
import '../models/order.dart';
import '../models/product.dart';

/// Immutable bundle of computed financial metrics for a period.
class ProfitSummary {
  const ProfitSummary({
    required this.revenue,
    required this.productCost,
    required this.marketingCost,
    required this.operatingExpenses,
    required this.orderCount,
    required this.unitsSold,
  });

  final Money revenue;
  final Money productCost;
  final Money marketingCost;

  /// Operating expenses EXCLUDING marketing (marketing is tracked separately).
  final Money operatingExpenses;
  final int orderCount;
  final int unitsSold;

  Money get grossProfit => revenue - productCost;
  Money get contributionProfit => grossProfit - marketingCost;
  Money get netProfit =>
      revenue - productCost - marketingCost - operatingExpenses;

  double get grossMargin =>
      revenue.isZero ? 0 : grossProfit.major / revenue.major * 100;
  double get netMargin =>
      revenue.isZero ? 0 : netProfit.major / revenue.major * 100;

  /// Total spend across all cost buckets.
  Money get totalExpenses => productCost + marketingCost + operatingExpenses;

  static const empty = ProfitSummary(
    revenue: Money.zero,
    productCost: Money.zero,
    marketingCost: Money.zero,
    operatingExpenses: Money.zero,
    orderCount: 0,
    unitsSold: 0,
  );
}

/// Per-product roll-up used by dashboard tables and profitability reports.
class ProductProfit {
  const ProductProfit({
    required this.product,
    required this.orderCount,
    required this.unitsSold,
    required this.revenue,
    required this.productCost,
    required this.marketingCost,
  });

  final Product product;
  final int orderCount;
  final int unitsSold;
  final Money revenue;
  final Money productCost;
  final Money marketingCost;

  Money get grossProfit => revenue - productCost;
  Money get netProfit => revenue - productCost - marketingCost;
  double get margin =>
      revenue.isZero ? 0 : netProfit.major / revenue.major * 100;
}

/// Campaign performance roll-up (spend/ROI/ROAS).
class CampaignPerformance {
  const CampaignPerformance({
    required this.campaign,
    required this.spend,
    required this.attributedRevenue,
  });

  final Campaign campaign;
  final Money spend;

  /// Revenue attributed to the campaign's product within the period. Used as a
  /// pragmatic proxy for campaign-attributed revenue.
  final Money attributedRevenue;

  /// ROI% = (revenue − spend) / spend × 100. Null when spend is zero.
  double? get roi => spend.isZero
      ? null
      : (attributedRevenue - spend).major / spend.major * 100;

  /// ROAS = revenue / spend. Null when spend is zero.
  double? get roas =>
      spend.isZero ? null : attributedRevenue.major / spend.major;
}

/// A single point in a time series (label + component values).
class TimeSeriesPoint {
  const TimeSeriesPoint({
    required this.label,
    required this.revenue,
    required this.productCost,
    required this.marketingCost,
    required this.operatingExpenses,
    required this.orders,
    this.units = 0,
    this.range,
  });

  final String label;
  final Money revenue;
  final Money productCost;
  final Money marketingCost;
  final Money operatingExpenses;
  final int orders;
  final int units;

  /// The days this point covers (the bucket, clipped to the series' range).
  final DateRange? range;

  Money get grossProfit => revenue - productCost;
  Money get contributionProfit => grossProfit - marketingCost;
  Money get netProfit =>
      revenue - productCost - marketingCost - operatingExpenses;
}

/// A category slice for the expense breakdown donut.
class CategorySlice {
  const CategorySlice(this.label, this.amount);
  final String label;
  final Money amount;
}

/// A headline figure the dashboard shows and compares across periods.
enum KpiMetric {
  revenue('Revenue'),
  productCost('Product Cost', higherIsBetter: false),
  marketingCost('Marketing', higherIsBetter: false),
  operatingExpenses('Operating Expenses', higherIsBetter: false),
  grossProfit('Gross Profit'),
  contributionProfit('Contribution Profit'),
  netProfit('Net Profit'),
  netMargin('Net Margin', isPercent: true),
  grossMargin('Gross Margin', isPercent: true),
  orders('Total Orders', isCount: true),
  units('Units Sold', isCount: true);

  const KpiMetric(
    this.label, {
    this.higherIsBetter = true,
    this.isPercent = false,
    this.isCount = false,
  });

  final String label;

  /// False for costs: a fall is good news.
  final bool higherIsBetter;

  /// A margin, compared in percentage points.
  final bool isPercent;
  final bool isCount;

  bool get isMoney => !isPercent && !isCount;

  /// The value in [s]: major units for money, % for margins.
  double valueOf(ProfitSummary s) => switch (this) {
    revenue => s.revenue.major,
    productCost => s.productCost.major,
    marketingCost => s.marketingCost.major,
    operatingExpenses => s.operatingExpenses.major,
    grossProfit => s.grossProfit.major,
    contributionProfit => s.contributionProfit.major,
    netProfit => s.netProfit.major,
    netMargin => s.netMargin,
    grossMargin => s.grossMargin,
    orders => s.orderCount.toDouble(),
    units => s.unitsSold.toDouble(),
  };

  /// The value for one point of a series (e.g. a sparkline).
  double valueOfPoint(TimeSeriesPoint p) => switch (this) {
    revenue => p.revenue.major,
    productCost => p.productCost.major,
    marketingCost => p.marketingCost.major,
    operatingExpenses => p.operatingExpenses.major,
    grossProfit => p.grossProfit.major,
    contributionProfit => p.contributionProfit.major,
    netProfit => p.netProfit.major,
    netMargin =>
      p.revenue.isZero ? 0 : p.netProfit.major / p.revenue.major * 100,
    grossMargin =>
      p.revenue.isZero ? 0 : p.grossProfit.major / p.revenue.major * 100,
    orders => p.orders.toDouble(),
    units => p.units.toDouble(),
  };
}

/// One metric now and in the period it's compared with.
class MetricDelta {
  const MetricDelta({
    required this.metric,
    required this.current,
    required this.previous,
  });

  final KpiMetric metric;
  final double current;

  /// Null when the comparison period has nothing to compare with.
  final double? previous;

  /// The change: % for amounts and counts, percentage points for margins.
  /// Null when there's no basis (nothing in the comparison period).
  double? get change {
    final p = previous;
    if (p == null) return null;
    if (metric.isPercent) return current - p;
    if (p == 0) return null;
    return (current - p) / p.abs() * 100;
  }

  /// True for good news (revenue up, costs down), false for bad, null when
  /// flat (under 0.05) or unknown.
  bool? get favourable {
    final c = change;
    if (c == null || c.abs() < 0.05) return null;
    return (c > 0) == metric.higherIsBetter;
  }
}

/// The selected period against its comparison period.
class ProfitComparison {
  const ProfitComparison({required this.current, required this.previous});

  final ProfitSummary current;
  final ProfitSummary previous;

  /// Whether the comparison period has any activity at all.
  bool get hasPrevious =>
      !previous.revenue.isZero ||
      !previous.totalExpenses.isZero ||
      previous.orderCount > 0;

  MetricDelta operator [](KpiMetric metric) => MetricDelta(
    metric: metric,
    current: metric.valueOf(current),
    previous: !hasPrevious || (metric.isPercent && previous.revenue.isZero)
        ? null
        : metric.valueOf(previous),
  );
}

enum WaterfallKind { total, decrease }

/// One bar of the profit waterfall: from [start] to [end].
class WaterfallStep {
  const WaterfallStep({
    required this.label,
    required this.amount,
    required this.start,
    required this.end,
    required this.kind,
  });

  final String label;

  /// The figure itself (a cost is positive here; it's drawn downwards).
  final Money amount;
  final Money start;
  final Money end;
  final WaterfallKind kind;
}

/// One business's figures, for comparing businesses side by side.
class BusinessSummary {
  const BusinessSummary({required this.business, required this.summary});
  final Business business;
  final ProfitSummary summary;
}

/// Where the period will land if it carries on at its rate so far.
class PeriodProjection {
  const PeriodProjection({
    required this.revenue,
    required this.netProfit,
    required this.revenuePerDay,
    required this.netProfitPerDay,
    required this.elapsedDays,
    required this.totalDays,
  });

  final Money revenue;
  final Money netProfit;
  final Money revenuePerDay;
  final Money netProfitPerDay;
  final int elapsedDays;
  final int totalDays;
}

/// A series point with what happened and, for days still to come, what the
/// run rate projects.
class ForecastPoint {
  const ForecastPoint({
    required this.label,
    this.revenue,
    this.netProfit,
    this.projectedRevenue,
    this.projectedNetProfit,
  });

  final String label;

  /// Actuals; null for a bucket that hasn't started.
  final Money? revenue;
  final Money? netProfit;

  /// The projection; null for a bucket that's over (or with no projection).
  final Money? projectedRevenue;
  final Money? projectedNetProfit;
}

/// Centralised financial calculation engine. All profit formulas live here so
/// they are never duplicated across UI screens.
class ProfitCalculationService {
  const ProfitCalculationService();

  // ---- Order-based aggregation ---------------------------------------------

  /// Filters orders to those whose [Order.orderDate] falls within [range] and
  /// that contribute to recognised revenue. Cancelled orders are excluded;
  /// returned/refunded orders are kept because they still recognise their
  /// retained (non-refunded) portion.
  List<Order> recognisedOrdersIn(List<Order> orders, DateRange range) {
    return orders
        .where((o) =>
            o.isRecognised &&
            o.orderDate != null &&
            range.contains(o.orderDate!))
        .toList();
  }

  /// Recognised revenue, net of any refunds on returned orders.
  Money revenueOf(Iterable<Order> orders) =>
      orders.fold(Money.zero, (sum, o) => sum + o.recognisedRevenue);

  /// Recognised product cost, with returned units' cost reversed proportionally
  /// to the refunded fraction (returned stock is assumed restocked).
  Money productCostOf(Iterable<Order> orders) =>
      orders.fold(Money.zero, (sum, o) => sum + o.recognisedProductCost);

  int unitsSoldOf(Iterable<Order> orders) =>
      orders.fold(0, (sum, o) => sum + o.quantity);

  // ---- Marketing ------------------------------------------------------------

  /// Total marketing spend for campaigns whose spend date falls within [range].
  /// Cancelled campaigns are excluded.
  Money marketingSpendIn(List<Campaign> campaigns, DateRange range) {
    return campaigns
        .where((c) =>
            c.status != CampaignStatus.cancelled &&
            c.spendDate != null &&
            range.contains(c.spendDate!))
        .fold(Money.zero, (sum, c) => sum + c.amountInvested);
  }

  // ---- Recurring expense proration -----------------------------------------

  /// Prorates a single expense to the portion applicable within [range].
  ///
  /// One-time expenses count fully if their start date falls in the range.
  /// Recurring expenses are annualised then scaled by the fraction of the year
  /// covered by [range] — additionally clipped to the expense's own active
  /// window (start/end date) when present.
  Money proratedExpense(Expense expense, DateRange range) {
    if (expense.status != EntityStatus.active) return Money.zero;

    if (!expense.frequency.isRecurring) {
      // One-time: include only if its date is inside the range.
      final date = expense.startDate ?? expense.audit.createdAt;
      if (date == null) return Money.zero;
      return range.contains(date) ? expense.amount : Money.zero;
    }

    // Recurring: determine the effective active window intersected with range.
    final effectiveStart = expense.startDate;
    final effectiveEnd = expense.endDate;

    // Days of the range during which the expense is active.
    var activeStart = range.start;
    var activeEnd = range.end;
    if (effectiveStart != null && effectiveStart.isAfter(activeStart)) {
      activeStart = effectiveStart;
    }
    if (effectiveEnd != null && effectiveEnd.isBefore(activeEnd)) {
      activeEnd = effectiveEnd;
    }
    if (activeStart.isAfter(activeEnd)) return Money.zero;

    final activeDays =
        DateRange(activeStart, activeEnd).days.toDouble();

    // Annualised cost scaled by (active days / 365).
    final annual = expense.annualisedAmount;
    return annual * (activeDays / 365.0);
  }

  /// Total prorated operating expenses in [range]. Marketing-category expenses
  /// are excluded by default so marketing is not double-counted with campaign
  /// spend (campaigns are the source of truth for marketing cost).
  Money operatingExpensesIn(
    List<Expense> expenses,
    DateRange range, {
    bool excludeAdvertising = true,
  }) {
    return expenses
        .where((e) => !(excludeAdvertising &&
            e.category == ExpenseCategory.advertising))
        .fold(Money.zero, (sum, e) => sum + proratedExpense(e, range));
  }

  // ---- Top-level summary ----------------------------------------------------

  ProfitSummary summarise({
    required List<Order> orders,
    required List<Campaign> campaigns,
    required List<Expense> expenses,
    required DateRange range,
  }) {
    final recognised = recognisedOrdersIn(orders, range);
    return ProfitSummary(
      revenue: revenueOf(recognised),
      productCost: productCostOf(recognised),
      marketingCost: marketingSpendIn(campaigns, range),
      operatingExpenses: operatingExpensesIn(expenses, range),
      orderCount: recognised.length,
      unitsSold: unitsSoldOf(recognised),
    );
  }

  // ---- Per-product ----------------------------------------------------------

  List<ProductProfit> productProfitability({
    required List<Product> products,
    required List<Order> orders,
    required List<Campaign> campaigns,
    required DateRange range,
  }) {
    final recognised = recognisedOrdersIn(orders, range);
    final byProduct = <String, List<Order>>{};
    for (final o in recognised) {
      byProduct.putIfAbsent(o.productId, () => []).add(o);
    }

    final marketingByProduct = <String, Money>{};
    for (final c in campaigns.where((c) =>
        c.status != CampaignStatus.cancelled &&
        c.spendDate != null &&
        range.contains(c.spendDate!))) {
      marketingByProduct.update(
        c.productId,
        (v) => v + c.amountInvested,
        ifAbsent: () => c.amountInvested,
      );
    }

    final result = <ProductProfit>[];
    for (final product in products) {
      final productOrders = byProduct[product.id] ?? const [];
      result.add(ProductProfit(
        product: product,
        orderCount: productOrders.length,
        unitsSold: unitsSoldOf(productOrders),
        revenue: revenueOf(productOrders),
        productCost: productCostOf(productOrders),
        marketingCost: marketingByProduct[product.id] ?? Money.zero,
      ));
    }
    return result;
  }

  // ---- Campaign performance -------------------------------------------------

  List<CampaignPerformance> campaignPerformance({
    required List<Campaign> campaigns,
    required List<Order> orders,
    required DateRange range,
  }) {
    final recognised = recognisedOrdersIn(orders, range);
    final revenueByProduct = <String, Money>{};
    for (final o in recognised) {
      revenueByProduct.update(o.productId, (v) => v + o.recognisedRevenue,
          ifAbsent: () => o.recognisedRevenue);
    }

    // When multiple campaigns target the same product, split that product's
    // revenue across them in proportion to their spend so ROAS is not
    // over-counted.
    final spendByProduct = <String, Money>{};
    for (final c in campaigns) {
      spendByProduct.update(c.productId, (v) => v + c.amountInvested,
          ifAbsent: () => c.amountInvested);
    }

    final result = <CampaignPerformance>[];
    for (final c in campaigns) {
      final productRevenue = revenueByProduct[c.productId] ?? Money.zero;
      final totalSpend = spendByProduct[c.productId] ?? Money.zero;
      final attributed = totalSpend.isZero
          ? Money.zero
          : productRevenue * (c.amountInvested.major / totalSpend.major);
      result.add(CampaignPerformance(
        campaign: c,
        spend: c.amountInvested,
        attributedRevenue: attributed,
      ));
    }
    return result;
  }

  // ---- Time series ----------------------------------------------------------

  /// Builds a bucketed time series across [range] for the revenue-vs-expenses
  /// chart and orders trend.
  List<TimeSeriesPoint> timeSeries({
    required List<Order> orders,
    required List<Campaign> campaigns,
    required List<Expense> expenses,
    required DateRange range,
    TimeBucket? bucket,
  }) {
    final resolvedBucket = bucket ?? bucketForRange(range);
    final buckets = _buildBuckets(range, resolvedBucket);
    final recognised = recognisedOrdersIn(orders, range);

    return buckets.map((b) {
      final bucketOrders =
          recognised.where((o) => b.range.contains(o.orderDate!)).toList();
      return TimeSeriesPoint(
        label: b.label,
        revenue: revenueOf(bucketOrders),
        productCost: productCostOf(bucketOrders),
        marketingCost: marketingSpendIn(campaigns, b.range),
        operatingExpenses: operatingExpensesIn(expenses, b.range),
        orders: bucketOrders.length,
        units: unitsSoldOf(bucketOrders),
        range: b.range,
      );
    }).toList();
  }

  /// Calendar buckets across [range]. The first and last are clipped to the
  /// range, so prorated costs per bucket add up to the period's total.
  List<_Bucket> _buildBuckets(DateRange range, TimeBucket bucket) {
    return [
      for (final b in _calendarBuckets(range, bucket))
        _Bucket(
          b.label,
          DateRange(
            b.range.start.isBefore(range.start) ? range.start : b.range.start,
            b.range.end.isAfter(range.end) ? range.end : b.range.end,
          ),
        ),
    ];
  }

  List<_Bucket> _calendarBuckets(DateRange range, TimeBucket bucket) {
    final buckets = <_Bucket>[];
    switch (bucket) {
      case TimeBucket.month:
        var cursor = DateTime(range.start.year, range.start.month, 1);
        while (!cursor.isAfter(range.end)) {
          final end = DateTime(cursor.year, cursor.month + 1, 0);
          buckets.add(_Bucket(AppDate.monthYear(cursor),
              DateRange(cursor, end)));
          cursor = DateTime(cursor.year, cursor.month + 1, 1);
        }
      case TimeBucket.quarter:
        var cursor = DateTime(range.start.year, range.start.month, 1);
        while (!cursor.isAfter(range.end)) {
          final end = DateTime(cursor.year, cursor.month + 3, 0);
          final q = ((cursor.month - 1) ~/ 3) + 1;
          buckets.add(_Bucket('Q$q ${cursor.year}', DateRange(cursor, end)));
          cursor = DateTime(cursor.year, cursor.month + 3, 1);
        }
      case TimeBucket.year:
        var year = range.start.year;
        while (year <= range.end.year) {
          buckets.add(_Bucket('$year',
              DateRange(DateTime(year, 1, 1), DateTime(year, 12, 31))));
          year++;
        }
    }
    return buckets;
  }

  // ---- Expense breakdown ----------------------------------------------------

  /// Builds the donut-chart slices: product cost, marketing, and each operating
  /// expense category present in [range].
  List<CategorySlice> expenseBreakdown({
    required List<Order> orders,
    required List<Campaign> campaigns,
    required List<Expense> expenses,
    required DateRange range,
  }) {
    final recognised = recognisedOrdersIn(orders, range);
    final slices = <CategorySlice>[
      CategorySlice('Product Cost', productCostOf(recognised)),
      CategorySlice('Marketing', marketingSpendIn(campaigns, range)),
    ];

    final byCategory = <ExpenseCategory, Money>{};
    for (final e in expenses) {
      if (e.category == ExpenseCategory.advertising) continue;
      final prorated = proratedExpense(e, range);
      if (prorated.isZero) continue;
      byCategory.update(e.category, (v) => v + prorated,
          ifAbsent: () => prorated);
    }
    byCategory.forEach((cat, amount) {
      slices.add(CategorySlice(cat.label, amount));
    });

    return slices.where((s) => s.amount.isPositive).toList()
      ..sort((a, b) => b.amount.minor.compareTo(a.amount.minor));
  }

  /// Marketing spend grouped by platform within [range].
  Map<CampaignPlatform, Money> marketingByPlatform(
      List<Campaign> campaigns, DateRange range) {
    final map = <CampaignPlatform, Money>{};
    for (final c in campaigns.where((c) =>
        c.status != CampaignStatus.cancelled &&
        c.spendDate != null &&
        range.contains(c.spendDate!))) {
      map.update(c.platform, (v) => v + c.amountInvested,
          ifAbsent: () => c.amountInvested);
    }
    return map;
  }

  // ---- Comparison and composition ------------------------------------------

  /// [current] against [previous], metric by metric.
  ProfitComparison compare(ProfitSummary current, ProfitSummary previous) =>
      ProfitComparison(current: current, previous: previous);

  /// Revenue → − product cost → − marketing → − operating expenses → net
  /// profit, as the bars of a waterfall chart.
  List<WaterfallStep> profitWaterfall(ProfitSummary s) {
    final steps = [
      WaterfallStep(
        label: 'Revenue',
        amount: s.revenue,
        start: Money.zero,
        end: s.revenue,
        kind: WaterfallKind.total,
      ),
    ];
    var running = s.revenue;
    for (final (label, cost) in [
      ('Product Cost', s.productCost),
      ('Marketing', s.marketingCost),
      ('Operating', s.operatingExpenses),
    ]) {
      final next = running - cost;
      steps.add(
        WaterfallStep(
          label: label,
          amount: cost,
          start: running,
          end: next,
          kind: WaterfallKind.decrease,
        ),
      );
      running = next;
    }
    steps.add(
      WaterfallStep(
        label: 'Net Profit',
        amount: s.netProfit,
        start: Money.zero,
        end: s.netProfit,
        kind: WaterfallKind.total,
      ),
    );
    return steps;
  }

  /// [summarise] per business in [businesses] (records of other businesses
  /// are ignored), in the order given.
  List<BusinessSummary> summariseByBusiness({
    required List<Business> businesses,
    required List<Order> orders,
    required List<Campaign> campaigns,
    required List<Expense> expenses,
    required DateRange range,
  }) {
    Map<String, List<T>> group<T>(List<T> items, String Function(T) id) {
      final map = <String, List<T>>{};
      for (final e in items) {
        map.putIfAbsent(id(e), () => []).add(e);
      }
      return map;
    }

    final o = group(orders, (e) => e.businessId);
    final c = group(campaigns, (e) => e.businessId);
    final x = group(expenses, (e) => e.businessId);
    return [
      for (final b in businesses)
        BusinessSummary(
          business: b,
          summary: summarise(
            orders: o[b.id] ?? const [],
            campaigns: c[b.id] ?? const [],
            expenses: x[b.id] ?? const [],
            range: range,
          ),
        ),
    ];
  }

  /// How many orders placed in [range] are in each status — every status,
  /// cancelled included. An order without an order date counts by when it
  /// was created.
  Map<OrderStatus, int> orderStatusBreakdown(
    List<Order> orders,
    DateRange range,
  ) {
    final counts = {for (final s in OrderStatus.values) s: 0};
    for (final o in orders) {
      final date = o.orderDate ?? o.audit.createdAt;
      if (date != null && range.contains(date)) {
        counts[o.status] = counts[o.status]! + 1;
      }
    }
    return counts;
  }

  /// Monthly points for the [months] months up to [asOf] (the last one stops
  /// at [asOf]): the sparklines behind the KPI tiles.
  List<TimeSeriesPoint> trailingMonths({
    required List<Order> orders,
    required List<Campaign> campaigns,
    required List<Expense> expenses,
    required DateTime asOf,
    int months = 12,
  }) => timeSeries(
    orders: orders,
    campaigns: campaigns,
    expenses: expenses,
    range: DateRange(DateTime(asOf.year, asOf.month - months + 1, 1), asOf),
    bucket: TimeBucket.month,
  );

  // ---- Projection -----------------------------------------------------------

  /// Where [range] ends up if it keeps the daily rate of [toDate] — the
  /// period's figures up to [asOf]. Null unless the period is running and at
  /// least [minDays] days in.
  PeriodProjection? projectRunRate({
    required ProfitSummary toDate,
    required DateRange range,
    required DateTime asOf,
    int minDays = 7,
  }) {
    final today = AppDate.dayOnly(asOf);
    if (today.isBefore(range.start) || today.isAfter(range.end)) return null;
    final elapsed = DateRange(range.start, today).days;
    if (elapsed < minDays || elapsed >= range.days) return null;
    final revenuePerDay = toDate.revenue / elapsed;
    final netPerDay = toDate.netProfit / elapsed;
    final remaining = range.days - elapsed;
    return PeriodProjection(
      revenue: toDate.revenue + revenuePerDay * remaining,
      netProfit: toDate.netProfit + netPerDay * remaining,
      revenuePerDay: revenuePerDay,
      netProfitPerDay: netPerDay,
      elapsedDays: elapsed,
      totalDays: range.days,
    );
  }

  /// [series] with the [projection] laid over the days after [asOf]: the
  /// running bucket gets its actuals plus the rest at the run rate, later
  /// buckets the run rate alone.
  List<ForecastPoint> projectSeries(
    List<TimeSeriesPoint> series,
    PeriodProjection? projection,
    DateTime asOf,
  ) {
    final today = AppDate.dayOnly(asOf);
    ForecastPoint project(TimeSeriesPoint p) {
      final r = p.range;
      final actual = ForecastPoint(
          label: p.label, revenue: p.revenue, netProfit: p.netProfit);
      if (projection == null || r == null || !r.end.isAfter(today)) {
        return actual; // Over (or nothing to project).
      }
      if (r.start.isAfter(today)) {
        return ForecastPoint(
          label: p.label,
          projectedRevenue: projection.revenuePerDay * r.days,
          projectedNetProfit: projection.netProfitPerDay * r.days,
        );
      }
      // Running: actuals so far, plus the rest of the bucket at the run rate.
      final rest = r.days - DateRange(r.start, today).days;
      return ForecastPoint(
        label: p.label,
        revenue: p.revenue,
        netProfit: p.netProfit,
        projectedRevenue: p.revenue + projection.revenuePerDay * rest,
        projectedNetProfit: p.netProfit + projection.netProfitPerDay * rest,
      );
    }

    return [for (final p in series) project(p)];
  }

  // ---- Spend history --------------------------------------------------------

  /// Spend per cost line — Marketing plus each operating-expense category —
  /// for each of the [months] months up to [asOf], oldest first. The last
  /// month runs only to [asOf]. Lines with no spend in any month are left out.
  Map<String, List<Money>> monthlySpendByCategory({
    required List<Campaign> campaigns,
    required List<Expense> expenses,
    required DateTime asOf,
    int months = 7,
  }) {
    final today = AppDate.dayOnly(asOf);
    final result = <String, List<Money>>{};
    for (var i = 0; i < months; i++) {
      final first = DateTime(today.year, today.month - months + 1 + i, 1);
      final last = DateTime(first.year, first.month + 1, 0);
      final range = DateRange(first, last.isAfter(today) ? today : last);
      void add(String label, Money amount) {
        result.putIfAbsent(label, () => List.filled(months, Money.zero))[i] +=
            amount;
      }

      final marketing = marketingSpendIn(campaigns, range);
      if (!marketing.isZero) add('Marketing', marketing);
      for (final e in expenses) {
        if (e.category == ExpenseCategory.advertising) continue;
        final amount = proratedExpense(e, range);
        if (!amount.isZero) add(e.category.label, amount);
      }
    }
    return result;
  }
}

class _Bucket {
  const _Bucket(this.label, this.range);
  final String label;
  final DateRange range;
}
