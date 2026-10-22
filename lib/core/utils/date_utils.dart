import 'package:intl/intl.dart';

/// A closed date range [start, end] (both inclusive at day granularity).
class DateRange {
  DateRange(DateTime start, DateTime end)
      : start = DateTime(start.year, start.month, start.day),
        end = DateTime(end.year, end.month, end.day, 23, 59, 59, 999);

  final DateTime start;
  final DateTime end;

  bool contains(DateTime date) =>
      !date.isBefore(start) && !date.isAfter(end);

  /// Number of calendar days in the range (inclusive).
  int get days => end.difference(start).inDays + 1;

  /// Overlap in days between this range and [other]; 0 if disjoint. Used by the
  /// recurring-expense proration engine.
  int overlapDays(DateRange other) {
    final s = start.isAfter(other.start) ? start : other.start;
    final e = end.isBefore(other.end) ? end : other.end;
    if (s.isAfter(e)) return 0;
    return e.difference(DateTime(s.year, s.month, s.day)).inDays + 1;
  }

  @override
  String toString() =>
      '${DateFormat('dd-MMM-yyyy').format(start)} → ${DateFormat('dd-MMM-yyyy').format(end)}';
}

/// Financial year helpers. By default the FY runs 1 April → 31 March (the
/// Indian FY); Settings can start it in January, July or October instead
/// ([FinancialYear.configureStartMonth]).
///
/// A FY is identified by its **starting** calendar year, so FY 2026-27 has
/// [startYear] == 2026.
class FinancialYear {
  const FinancialYear(this.startYear);

  final int startYear;

  /// April: the Indian financial year.
  static const defaultStartMonth = 4;

  /// The months a financial year may start in (Settings → Defaults).
  static const startMonths = [1, 4, 7, 10];

  static int _startMonth = defaultStartMonth;

  /// The month (1–12) every financial year starts in.
  static int get startMonth => _startMonth;

  /// Sets the month financial years start in; anything but Jan, Apr, Jul or
  /// Oct falls back to April. Returns whether it changed.
  static bool configureStartMonth(int month) {
    final m = startMonths.contains(month) ? month : defaultStartMonth;
    if (m == _startMonth) return false;
    _startMonth = m;
    return true;
  }

  /// The calendar year the FY ends in (the start year when it starts in
  /// January).
  int get endYear => _startMonth == 1 ? startYear : startYear + 1;

  /// The FY that contains [date].
  factory FinancialYear.forDate(DateTime date) {
    // Months before the start month belong to the FY that started the
    // previous calendar year (Jan–Mar, for an April start).
    if (date.month < _startMonth) return FinancialYear(date.year - 1);
    return FinancialYear(date.year);
  }

  DateRange get range => DateRange(
        DateTime(startYear, _startMonth, 1),
        // Day 0 is the last day of the month before.
        DateTime(startYear + 1, _startMonth, 0),
      );

  FinancialYear get previous => FinancialYear(startYear - 1);
  FinancialYear get next => FinancialYear(startYear + 1);

  /// e.g. "FY 2026-27", or "FY 2026" when it starts in January.
  String get label {
    if (endYear == startYear) return 'FY $startYear';
    final shortEnd = (endYear % 100).toString().padLeft(2, '0');
    return 'FY $startYear-$shortEnd';
  }

  @override
  bool operator ==(Object other) =>
      other is FinancialYear && other.startYear == startYear;

  @override
  int get hashCode => startYear.hashCode;
}

/// Derives the selectable reporting periods (financial & calendar years) from
/// the actual span of activity dates, so the global filter is never hardcoded.
///
/// Both lists are newest-first and always include the period containing [now],
/// so the current FY/year is selectable even before any data exists (that is
/// the empty-data fallback). Any FY/year that has real activity — including
/// forward-dated records — is included automatically.
class PeriodOptions {
  PeriodOptions._();

  static List<FinancialYear> financialYears(
    Iterable<DateTime> dates, {
    DateTime? now,
  }) {
    final current = FinancialYear.forDate(now ?? DateTime.now());
    var minYear = current.startYear;
    var maxYear = current.startYear;
    for (final d in dates) {
      final y = FinancialYear.forDate(d).startYear;
      if (y < minYear) minYear = y;
      if (y > maxYear) maxYear = y;
    }
    return [for (var y = maxYear; y >= minYear; y--) FinancialYear(y)];
  }

  static List<int> calendarYears(
    Iterable<DateTime> dates, {
    DateTime? now,
  }) {
    final currentYear = (now ?? DateTime.now()).year;
    var minYear = currentYear;
    var maxYear = currentYear;
    for (final d in dates) {
      if (d.year < minYear) minYear = d.year;
      if (d.year > maxYear) maxYear = d.year;
    }
    return [for (var y = maxYear; y >= minYear; y--) y];
  }
}

/// The kind of period the global date filter is currently expressing.
enum PeriodType {
  financialYear('Financial Year'),
  calendarYear('Calendar Year'),
  quarter('Quarter'),
  month('Month'),
  custom('Custom Range');

  const PeriodType(this.label);
  final String label;
}

/// Named quarters within a financial year, counted from its start month
/// (Q1 = Apr–Jun for an April start).
enum FinancialQuarter {
  q1,
  q2,
  q3,
  q4;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// First calendar month (1–12).
  int get startMonth => (FinancialYear.startMonth - 1 + index * 3) % 12 + 1;

  /// Last calendar month (1–12).
  int get endMonth => (startMonth + 1) % 12 + 1;

  /// e.g. "Q1 (Apr–Jun)".
  String get label =>
      'Q${index + 1} (${_months[startMonth - 1]}–${_months[endMonth - 1]})';

  /// This quarter's dates within [fy].
  DateRange rangeIn(FinancialYear fy) {
    // Months past December roll into the next year.
    final start =
        DateTime(fy.startYear, FinancialYear.startMonth + index * 3, 1);
    return DateRange(start, DateTime(start.year, start.month + 3, 0));
  }

  /// The quarter [date] falls in (of its own financial year).
  static FinancialQuarter forDate(DateTime date) =>
      values[((date.month - FinancialYear.startMonth) % 12) ~/ 3];
}

/// Common date formatting used across the app.
class AppDate {
  AppDate._();

  static const defaultPattern = 'dd-MMM-yyyy';
  static DateFormat _display = DateFormat(defaultPattern);
  static final DateFormat _displayShort = DateFormat('dd MMM');
  static final DateFormat _monthYear = DateFormat('MMM yyyy');
  static final DateFormat _iso = DateFormat('yyyy-MM-dd');

  /// The active long-date pattern (mirrors the user's Settings preference).
  static String get displayPattern => _display.pattern ?? defaultPattern;

  /// Applies a user-configured long-date pattern. Falls back to the default if
  /// [pattern] is empty or invalid.
  static void configureDisplayFormat(String pattern) {
    final p = pattern.trim();
    if (p.isEmpty) {
      _display = DateFormat(defaultPattern);
      return;
    }
    try {
      // Probe the pattern before adopting it.
      DateFormat(p).format(DateTime(2026, 1, 1));
      _display = DateFormat(p);
    } catch (_) {
      _display = DateFormat(defaultPattern);
    }
  }

  static String format(DateTime? date) =>
      date == null ? '—' : _display.format(date);
  static String short(DateTime date) => _displayShort.format(date);
  static String monthYear(DateTime date) => _monthYear.format(date);
  static String iso(DateTime date) => _iso.format(date);

  static DateTime? tryParseIso(String? value) =>
      value == null ? null : DateTime.tryParse(value);

  /// Truncates to midnight.
  static DateTime dayOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);
}

/// A calendar-accurate span between two dates, broken into whole years, months
/// and days, plus the absolute day count. Used to show how long is left on a
/// service contract ("1 yr 2 mo remaining", "23 days remaining", "Expired…").
///
/// [isPast] is true when the target date lies before the reference date, so the
/// same value type expresses both "time remaining" and "time since expiry".
class TimeRemaining {
  const TimeRemaining({
    required this.years,
    required this.months,
    required this.days,
    required this.totalDays,
    required this.isPast,
  });

  final int years;
  final int months;
  final int days;

  /// Absolute whole-day difference between the two dates.
  final int totalDays;

  /// True when [to] is before [from] (i.e. the target date has passed).
  final bool isPast;

  /// Whole calendar span from [from] to [to], at day granularity. Order does
  /// not matter — the magnitude is returned with [isPast] recording direction.
  factory TimeRemaining.between(DateTime from, DateTime to) {
    final f = DateTime(from.year, from.month, from.day);
    final t = DateTime(to.year, to.month, to.day);
    final past = t.isBefore(f);
    final start = past ? t : f;
    final end = past ? f : t;

    var years = end.year - start.year;
    var months = end.month - start.month;
    var days = end.day - start.day;
    if (days < 0) {
      months -= 1;
      // Borrow the number of days in the month preceding `end` (day 0 of a
      // month resolves to the last day of the previous month).
      days += DateTime(end.year, end.month, 0).day;
    }
    if (months < 0) {
      years -= 1;
      months += 12;
    }
    return TimeRemaining(
      years: years,
      months: months,
      days: days,
      totalDays: end.difference(start).inDays,
      isPast: past,
    );
  }

  bool get isToday => totalDays == 0;

  /// A compact headline figure and unit, e.g. ("1 yr 2 mo"), ("23", "days").
  /// Prefers the two largest non-zero units; falls back to days.
  String get shortLabel {
    if (isToday) return 'Today';
    final parts = <String>[];
    if (years > 0) parts.add('$years yr');
    if (months > 0) parts.add('$months mo');
    if (years == 0 && days > 0) parts.add('$days day${days == 1 ? '' : 's'}');
    if (parts.isEmpty) return '$totalDays day${totalDays == 1 ? '' : 's'}';
    return parts.join(' ');
  }

  /// A full sentence for captions: "1 yr 2 mo remaining" / "Expired 5 days ago".
  String get label {
    if (isToday) return isPast ? 'Expires today' : 'Expires today';
    return isPast ? 'Expired $shortLabel ago' : '$shortLabel remaining';
  }
}

/// Buckets used to group time-series data for charts.
enum TimeBucket { month, quarter, year }

/// Chooses a sensible chart bucket based on the span of [range].
TimeBucket bucketForRange(DateRange range) {
  final days = range.days;
  if (days <= 92) return TimeBucket.month; // up to ~a quarter -> monthly
  if (days <= 400) return TimeBucket.month; // a year -> monthly
  if (days <= 1200) return TimeBucket.quarter;
  return TimeBucket.year;
}

/// What the dashboard compares the selected period against.
enum ComparisonBasis {
  previousPeriod('Previous period', 'vs previous period'),
  lastYear('Same period last year', 'vs last year');

  const ComparisonBasis(this.label, this.shortLabel);
  final String label;

  /// For delta chips: "vs previous period".
  final String shortLabel;
}

/// The two date ranges a comparison uses.
///
/// When the selected period is still running ([isToDate]), both sides stop at
/// the same point: this FY so far is compared with the previous FY up to the
/// same day, not with all of it.
class ComparisonWindow {
  const ComparisonWindow({
    required this.current,
    required this.previous,
    required this.isToDate,
  });

  /// The selected period, or the part of it up to today when it's running.
  final DateRange current;

  /// The matching span of the period it's compared with.
  final DateRange previous;

  final bool isToDate;

  /// Builds the comparison for [range] (a [type] period) against [basis].
  ///
  /// The previous period is the one just before: the previous FY, calendar
  /// year, quarter or month; for a custom range, the same number of days
  /// immediately before it. "Last year" is the same dates a year earlier.
  factory ComparisonWindow.of(
    DateRange range,
    PeriodType type,
    ComparisonBasis basis, {
    DateTime? now,
  }) {
    final today = AppDate.dayOnly(now ?? DateTime.now());
    final start = range.start;
    final end = AppDate.dayOnly(range.end);

    final DateTime prevStart;
    final DateTime prevEnd;
    if (basis == ComparisonBasis.lastYear) {
      prevStart = shiftMonths(start, -12);
      prevEnd = shiftMonths(end, -12, keepMonthEnd: true);
    } else {
      prevEnd = DateTime(start.year, start.month, start.day - 1);
      prevStart = switch (type) {
        PeriodType.financialYear ||
        PeriodType.calendarYear => shiftMonths(start, -12),
        PeriodType.quarter => shiftMonths(start, -3),
        PeriodType.month => shiftMonths(start, -1),
        PeriodType.custom => DateTime(
          prevEnd.year,
          prevEnd.month,
          prevEnd.day - range.days + 1,
        ),
      };
    }

    final running = !today.isBefore(start) && today.isBefore(end);
    if (!running) {
      return ComparisonWindow(
        current: range,
        previous: DateRange(prevStart, prevEnd),
        isToDate: false,
      );
    }
    final elapsed = today.difference(start).inDays; // days before today
    final sameDay = basis == ComparisonBasis.lastYear
        ? shiftMonths(today, -12)
        : DateTime(prevStart.year, prevStart.month, prevStart.day + elapsed);
    return ComparisonWindow(
      current: DateRange(start, today),
      previous: DateRange(
        prevStart,
        sameDay.isAfter(prevEnd) ? prevEnd : sameDay,
      ),
      isToDate: true,
    );
  }
}

/// [date] moved by [months], clamped to the target month's length
/// (31 Mar − 1 month → 28/29 Feb). With [keepMonthEnd], the last day of a
/// month maps to the last day of the target month (30 Apr − 1 month → 31 Mar).
DateTime shiftMonths(DateTime date, int months, {bool keepMonthEnd = false}) {
  final first = DateTime(date.year, date.month + months, 1);
  final length = DateTime(first.year, first.month + 1, 0).day;
  final isMonthEnd = date.day == DateTime(date.year, date.month + 1, 0).day;
  final day = keepMonthEnd && isMonthEnd
      ? length
      : (date.day > length ? length : date.day);
  return DateTime(first.year, first.month, day);
}
