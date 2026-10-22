import 'package:flutter/foundation.dart';

import '../core/utils/date_utils.dart';

/// Holds the globally-selected business scope and reporting period. Dashboard,
/// reports, tables and profit calculations all read from this.
class FilterController extends ChangeNotifier {
  FilterController({DateTime? now}) {
    final n = now ?? DateTime.now();
    _financialYear = FinancialYear.forDate(n);
    _periodType = PeriodType.financialYear;
    _recompute();
  }

  /// null == "All Businesses".
  String? _selectedBusinessId;
  String? get selectedBusinessId => _selectedBusinessId;
  bool get isAllBusinesses => _selectedBusinessId == null;

  late FinancialYear _financialYear;
  FinancialYear get financialYear => _financialYear;

  late PeriodType _periodType;
  PeriodType get periodType => _periodType;

  FinancialQuarter _quarter = FinancialQuarter.q1;
  FinancialQuarter get quarter => _quarter;

  int _calendarYear = DateTime.now().year;
  int get calendarYear => _calendarYear;

  int _month = DateTime.now().month;
  int _monthYear = DateTime.now().year;
  int get month => _month;
  int get monthYear => _monthYear;

  DateRange? _customRange;

  late DateRange _range;
  DateRange get range => _range;

  ComparisonBasis _comparison = ComparisonBasis.previousPeriod;

  /// What the dashboard's deltas compare the period with.
  ComparisonBasis get comparison => _comparison;

  void setComparison(ComparisonBasis basis) {
    if (basis == _comparison) return;
    _comparison = basis;
    notifyListeners();
  }

  /// The selected period and the span it's compared with (see
  /// [ComparisonWindow.of]).
  ComparisonWindow comparisonWindow({DateTime? now}) =>
      ComparisonWindow.of(_range, _periodType, _comparison, now: now);

  /// Identifies the current selection (business + date range): equal keys
  /// mean equal filtered results, so it can key memoised figures.
  (String?, DateTime, DateTime) get key =>
      (_selectedBusinessId, _range.start, _range.end);

  /// Human label for the current period, e.g. "FY 2026-27".
  String get periodLabel {
    switch (_periodType) {
      case PeriodType.financialYear:
        return _financialYear.label;
      case PeriodType.calendarYear:
        return 'CY $_calendarYear';
      case PeriodType.quarter:
        return '${_quarter.label} · ${_financialYear.label}';
      case PeriodType.month:
        return AppDate.monthYear(DateTime(_monthYear, _month));
      case PeriodType.custom:
        return _range.toString();
    }
  }

  void selectBusiness(String? businessId) {
    if (_selectedBusinessId == businessId) return;
    _selectedBusinessId = businessId;
    notifyListeners();
  }

  void setFinancialYear(FinancialYear fy) {
    _financialYear = fy;
    _periodType = PeriodType.financialYear;
    _recompute();
  }

  void setPeriodType(PeriodType type) {
    _periodType = type;
    _recompute();
  }

  void setQuarter(FinancialQuarter q) {
    _quarter = q;
    _periodType = PeriodType.quarter;
    _recompute();
  }

  void setCalendarYear(int year) {
    _calendarYear = year;
    _periodType = PeriodType.calendarYear;
    _recompute();
  }

  void setMonth(int month, int year) {
    _month = month;
    _monthYear = year;
    _periodType = PeriodType.month;
    _recompute();
  }

  void setCustomRange(DateRange range) {
    _customRange = range;
    _periodType = PeriodType.custom;
    _recompute();
  }

  /// The selection as JSON, for remembering it across reloads.
  Map<String, Object?> toJson() => {
        'business': _selectedBusinessId,
        'type': _periodType.name,
        'fy': _financialYear.startYear,
        'quarter': _quarter.name,
        'cy': _calendarYear,
        'month': _month,
        'monthYear': _monthYear,
        'compare': _comparison.name,
        if (_customRange case final r?) ...{
          'from': r.start.toIso8601String(),
          'to': r.end.toIso8601String(),
        },
      };

  /// Restores a [toJson] selection; anything missing or unreadable falls back
  /// to the default (all businesses, the current financial year). Null resets.
  void restore(Map<String, Object?>? json, {DateTime? now}) {
    final n = now ?? DateTime.now();
    T? read<T>(String key) => json?[key] is T ? json![key] as T : null;
    final from = DateTime.tryParse(read<String>('from') ?? '');
    final to = DateTime.tryParse(read<String>('to') ?? '');

    _selectedBusinessId = read<String>('business');
    _financialYear = switch (read<int>('fy')) {
      final y? => FinancialYear(y),
      null => FinancialYear.forDate(n),
    };
    _quarter = FinancialQuarter.values.asNameMap()[read<String>('quarter')] ??
        FinancialQuarter.q1;
    _calendarYear = read<int>('cy') ?? n.year;
    final month = read<int>('month');
    _month = month != null && month >= 1 && month <= 12 ? month : n.month;
    _monthYear = read<int>('monthYear') ?? n.year;
    _customRange =
        from != null && to != null && !to.isBefore(from) ? DateRange(from, to) : null;
    var type = PeriodType.values.asNameMap()[read<String>('type')] ??
        PeriodType.financialYear;
    if (type == PeriodType.custom && _customRange == null) {
      type = PeriodType.financialYear;
    }
    _periodType = type;
    _comparison =
        ComparisonBasis.values.asNameMap()[read<String>('compare')] ??
            ComparisonBasis.previousPeriod;
    _announced = null;
    _recompute();
  }

  // What the last notification announced, so re-selecting the same period
  // doesn't rebuild every screen.
  (PeriodType, DateRange)? _announced;

  void _recompute() {
    switch (_periodType) {
      case PeriodType.financialYear:
        _range = _financialYear.range;
      case PeriodType.calendarYear:
        _range = DateRange(
            DateTime(_calendarYear, 1, 1), DateTime(_calendarYear, 12, 31));
      case PeriodType.quarter:
        _range = _quarterRange(_financialYear, _quarter);
      case PeriodType.month:
        _range = DateRange(DateTime(_monthYear, _month, 1),
            DateTime(_monthYear, _month + 1, 0));
      case PeriodType.custom:
        _range = _customRange ?? _financialYear.range;
    }
    // The type matters as well as the range: it drives the period label
    // (e.g. FY 2026-27 vs a custom range covering the same dates).
    final next = (_periodType, _range);
    if (next == _announced) return;
    _announced = next;
    notifyListeners();
  }

  DateRange _quarterRange(FinancialYear fy, FinancialQuarter q) {
    // Q1 Apr–Jun, Q2 Jul–Sep, Q3 Oct–Dec (all in start year),
    // Q4 Jan–Mar (in end year).
    switch (q) {
      case FinancialQuarter.q1:
        return DateRange(
            DateTime(fy.startYear, 4, 1), DateTime(fy.startYear, 6, 30));
      case FinancialQuarter.q2:
        return DateRange(
            DateTime(fy.startYear, 7, 1), DateTime(fy.startYear, 9, 30));
      case FinancialQuarter.q3:
        return DateRange(
            DateTime(fy.startYear, 10, 1), DateTime(fy.startYear, 12, 31));
      case FinancialQuarter.q4:
        return DateRange(
            DateTime(fy.endYear, 1, 1), DateTime(fy.endYear, 3, 31));
    }
  }
}
