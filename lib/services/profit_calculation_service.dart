import '../core/enums.dart';
import '../core/utils/date_utils.dart';
import '../core/utils/money.dart';
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
  });

  final String label;
  final Money revenue;
  final Money productCost;
  final Money marketingCost;
  final Money operatingExpenses;
  final int orders;

  Money get netProfit =>
      revenue - productCost - marketingCost - operatingExpenses;
}

/// A category slice for the expense breakdown donut.
class CategorySlice {
  const CategorySlice(this.label, this.amount);
  final String label;
  final Money amount;
}

/// Centralised financial calculation engine. All profit formulas live here so
/// they are never duplicated across UI screens.
class ProfitCalculationService {
  const ProfitCalculationService();

  // ---- Order-based aggregation ---------------------------------------------

  /// Filters orders to those whose [Order.orderDate] falls within [range] and
  /// that contribute to recognised revenue (excludes cancelled/returned).
  List<Order> recognisedOrdersIn(List<Order> orders, DateRange range) {
    return orders
        .where((o) =>
            o.isRecognised &&
            o.orderDate != null &&
            range.contains(o.orderDate!))
        .toList();
  }

  Money revenueOf(Iterable<Order> orders) =>
      orders.fold(Money.zero, (sum, o) => sum + o.totalRevenue);

  Money productCostOf(Iterable<Order> orders) =>
      orders.fold(Money.zero, (sum, o) => sum + o.productCost);

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
      revenueByProduct.update(o.productId, (v) => v + o.totalRevenue,
          ifAbsent: () => o.totalRevenue);
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
      );
    }).toList();
  }

  List<_Bucket> _buildBuckets(DateRange range, TimeBucket bucket) {
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
}

class _Bucket {
  const _Bucket(this.label, this.range);
  final String label;
  final DateRange range;
}
