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

/// Indian financial year helpers. The FY runs 1 April → 31 March.
///
/// A FY is identified by its **starting** calendar year, so FY 2026-27 has
/// [startYear] == 2026.
class FinancialYear {
  const FinancialYear(this.startYear);

  final int startYear;

  int get endYear => startYear + 1;

  /// The FY that contains [date].
  factory FinancialYear.forDate(DateTime date) {
    // Jan–Mar belong to the FY that started the previous calendar year.
    if (date.month < 4) return FinancialYear(date.year - 1);
    return FinancialYear(date.year);
  }

  DateRange get range => DateRange(
        DateTime(startYear, 4, 1),
        DateTime(endYear, 3, 31),
      );

  FinancialYear get previous => FinancialYear(startYear - 1);
  FinancialYear get next => FinancialYear(startYear + 1);

  /// e.g. "FY 2026-27".
  String get label {
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

/// Named quarters within a financial year (Q1 = Apr–Jun).
enum FinancialQuarter {
  q1('Q1 (Apr–Jun)', 4),
  q2('Q2 (Jul–Sep)', 7),
  q3('Q3 (Oct–Dec)', 10),
  q4('Q4 (Jan–Mar)', 1);

  const FinancialQuarter(this.label, this.startMonth);
  final String label;
  final int startMonth;
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
