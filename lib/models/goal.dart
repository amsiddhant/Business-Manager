import 'package:flutter/foundation.dart';

import '../core/enums.dart';
import '../core/utils/date_utils.dart';
import '../core/utils/money.dart';
import 'audit_fields.dart';

/// How long a goal runs.
enum GoalPeriodType {
  month('Month'),
  quarter('Quarter'),
  financialYear('Financial year');

  const GoalPeriodType(this.label);
  final String label;
}

/// What a goal measures. Money metrics hold their target in minor units
/// (paise/cents); counts hold a plain number.
enum GoalMetric {
  revenue('Revenue'),
  grossProfit('Gross profit'),
  contributionProfit('Contribution profit'),
  netProfit('Net profit'),
  orders('Orders', isCount: true),
  units('Units sold', isCount: true);

  const GoalMetric(this.label, {this.isCount = false});
  final String label;
  final bool isCount;
  bool get isMoney => !isCount;
}

/// A month, quarter or financial year a goal covers.
///
/// Quarter and FY periods carry the FY start month they were set under, so a
/// goal keeps its dates if the organisation later moves its FY start.
@immutable
class GoalPeriod {
  const GoalPeriod._(this.type, this.year, this.index, this.fyStartMonth);

  /// A calendar month ([month] 1–12).
  factory GoalPeriod.month(int year, int month) {
    final d = DateTime(year, month);
    return GoalPeriod._(GoalPeriodType.month, d.year, d.month,
        FinancialYear.startMonth);
  }

  /// Quarter [quarter] (1–4) of the FY starting in [fyStartYear].
  factory GoalPeriod.quarter(int fyStartYear, int quarter,
      {int? fyStartMonth}) {
    // Quarters past Q4 (or before Q1) roll into the next (previous) FY.
    final q = quarter - 1;
    return GoalPeriod._(GoalPeriodType.quarter, fyStartYear + (q / 4).floor(),
        q % 4 + 1, fyStartMonth ?? FinancialYear.startMonth);
  }

  /// The FY starting in [fyStartYear].
  factory GoalPeriod.financialYear(int fyStartYear, {int? fyStartMonth}) =>
      GoalPeriod._(GoalPeriodType.financialYear, fyStartYear, 0,
          fyStartMonth ?? FinancialYear.startMonth);

  /// The period of [type] that contains [date], under the current FY start.
  factory GoalPeriod.containing(GoalPeriodType type, DateTime date) {
    final fy = FinancialYear.forDate(date);
    return switch (type) {
      GoalPeriodType.month => GoalPeriod.month(date.year, date.month),
      GoalPeriodType.quarter => GoalPeriod.quarter(
          fy.startYear, FinancialQuarter.forDate(date).index + 1),
      GoalPeriodType.financialYear => GoalPeriod.financialYear(fy.startYear),
    };
  }

  final GoalPeriodType type;

  /// Calendar year (months) or the FY's start year (quarters, FYs).
  final int year;

  /// Month 1–12, quarter 1–4, or 0 for a whole FY.
  final int index;
  final int fyStartMonth;

  static final _monthKey = RegExp(r'^(\d{4})-(\d{2})$');
  static final _quarterKey = RegExp(r'^FY(\d{4})Q([1-4])$');
  static final _fyKey = RegExp(r'^FY(\d{4})$');

  /// `2026-04` (month), `FY2026Q1` (quarter) or `FY2026` (FY).
  String get key => switch (type) {
        GoalPeriodType.month => '$year-${index.toString().padLeft(2, '0')}',
        GoalPeriodType.quarter => 'FY${year}Q$index',
        GoalPeriodType.financialYear => 'FY$year',
      };

  /// Reads a [key]; null when it isn't one.
  static GoalPeriod? parse(String key,
      {int fyStartMonth = FinancialYear.defaultStartMonth}) {
    if (_monthKey.firstMatch(key) case final m?) {
      final month = int.parse(m[2]!);
      if (month < 1 || month > 12) return null;
      return GoalPeriod._(
          GoalPeriodType.month, int.parse(m[1]!), month, fyStartMonth);
    }
    if (_quarterKey.firstMatch(key) case final m?) {
      return GoalPeriod._(GoalPeriodType.quarter, int.parse(m[1]!),
          int.parse(m[2]!), fyStartMonth);
    }
    if (_fyKey.firstMatch(key) case final m?) {
      return GoalPeriod._(
          GoalPeriodType.financialYear, int.parse(m[1]!), 0, fyStartMonth);
    }
    return null;
  }

  DateTime get _fyStart => DateTime(year, fyStartMonth, 1);

  DateRange get range {
    switch (type) {
      case GoalPeriodType.month:
        return DateRange(DateTime(year, index, 1), DateTime(year, index + 1, 0));
      case GoalPeriodType.quarter:
        final start =
            DateTime(_fyStart.year, _fyStart.month + (index - 1) * 3, 1);
        return DateRange(start, DateTime(start.year, start.month + 3, 0));
      case GoalPeriodType.financialYear:
        return DateRange(
            _fyStart, DateTime(_fyStart.year + 1, _fyStart.month, 0));
    }
  }

  String get _fyLabel {
    if (fyStartMonth == 1) return 'FY $year';
    return 'FY $year-${((year + 1) % 100).toString().padLeft(2, '0')}';
  }

  /// "Apr 2026", "Q1 · FY 2026-27" or "FY 2026-27".
  String get label => switch (type) {
        GoalPeriodType.month => AppDate.monthYear(range.start),
        GoalPeriodType.quarter => 'Q$index · $_fyLabel',
        GoalPeriodType.financialYear => _fyLabel,
      };

  GoalPeriod get next => _shift(1);
  GoalPeriod get previous => _shift(-1);

  /// The same period a year earlier (for "split by last year").
  GoalPeriod get yearEarlier => GoalPeriod._(type, year - 1, index, fyStartMonth);

  GoalPeriod _shift(int by) => switch (type) {
        GoalPeriodType.month => GoalPeriod.month(year, index + by),
        GoalPeriodType.quarter => GoalPeriod.quarter(year, index + by,
            fyStartMonth: fyStartMonth),
        GoalPeriodType.financialYear =>
          GoalPeriod.financialYear(year + by, fyStartMonth: fyStartMonth),
      };

  /// The calendar months this period covers, in order.
  List<GoalPeriod> get months {
    final r = range;
    return [
      for (var d = r.start;
          !d.isAfter(r.end);
          d = DateTime(d.year, d.month + 1, 1))
        GoalPeriod.month(d.year, d.month),
    ];
  }

  @override
  bool operator ==(Object other) =>
      other is GoalPeriod &&
      other.type == type &&
      other.year == year &&
      other.index == index &&
      (type == GoalPeriodType.month || other.fyStartMonth == fyStartMonth);

  @override
  int get hashCode => Object.hash(type, year, index,
      type == GoalPeriodType.month ? 0 : fyStartMonth);

  @override
  String toString() => key;
}

/// A target for one metric, one business (or all of them) and one period.
///
/// The id is deterministic (`{business}_{period}_{metric}`), so setting a
/// goal again simply replaces it: no counter, no duplicate.
@immutable
class Goal {
  const Goal({
    required this.businessId,
    required this.period,
    required this.metric,
    required this.target,
    this.currency = CurrencyCode.inr,
    this.note = '',
    this.audit = const AuditFields(),
  });

  /// [businessId] of an organisation-wide goal (Owner only).
  static const allBusinesses = 'ALL';

  static const maxNote = 500;

  /// Keeps targets well inside what the web can hold exactly.
  static const maxTarget = 999999999999999;

  final String businessId;
  final GoalPeriod period;
  final GoalMetric metric;

  /// Minor units for money metrics, a count otherwise.
  final int target;

  /// The currency a money target is in (the business's; INR for all).
  final CurrencyCode currency;
  final String note;
  final AuditFields audit;

  static String idFor(String businessId, GoalPeriod period, GoalMetric metric) =>
      '${businessId}_${period.key}_${metric.name}';

  String get id => idFor(businessId, period, metric);

  bool get isOrgWide => businessId == allBusinesses;

  /// The business to scope figures to; null = every business.
  String? get scopeBusinessId => isOrgWide ? null : businessId;

  Money get targetMoney => Money(target);

  /// The target as people read it: money in [currency], or a count.
  String get targetLabel => metric.isMoney
      ? MoneyFormatter.format(targetMoney, currency)
      : target.toString();

  Goal copyWith({
    String? businessId,
    GoalPeriod? period,
    GoalMetric? metric,
    int? target,
    CurrencyCode? currency,
    String? note,
    AuditFields? audit,
  }) =>
      Goal(
        businessId: businessId ?? this.businessId,
        period: period ?? this.period,
        metric: metric ?? this.metric,
        target: target ?? this.target,
        currency: currency ?? this.currency,
        note: note ?? this.note,
        audit: audit ?? this.audit,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'businessId': businessId,
        'periodType': period.type.name,
        'periodKey': period.key,
        'fyStartMonth': period.fyStartMonth,
        'metric': metric.name,
        'target': target,
        'currency': currency.wire,
        'note': note,
        ...audit.toMap(),
      };

  /// Null when the document isn't a readable goal.
  static Goal? fromMap(Map<String, dynamic> map) {
    final metric = GoalMetric.values.asNameMap()[map['metric']];
    final fyStart = map['fyStartMonth'];
    final key = map['periodKey'];
    final period = key is String
        ? GoalPeriod.parse(key,
            fyStartMonth: fyStart is int &&
                    FinancialYear.startMonths.contains(fyStart)
                ? fyStart
                : FinancialYear.defaultStartMonth)
        : null;
    final business = map['businessId'];
    final target = map['target'];
    if (metric == null ||
        period == null ||
        business is! String ||
        business.isEmpty ||
        target is! num) {
      return null;
    }
    final note = map['note'];
    return Goal(
      businessId: business,
      period: period,
      metric: metric,
      target: target.round().clamp(0, maxTarget),
      currency: CurrencyCode.fromWire(map['currency'] as String?),
      note: note is String ? note : '',
      audit: AuditFields.fromMap(map),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Goal &&
      other.id == id &&
      other.target == target &&
      other.currency == currency &&
      other.note == note;

  @override
  int get hashCode => Object.hash(id, target, currency, note);
}
