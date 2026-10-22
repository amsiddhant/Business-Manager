import 'package:flutter_test/flutter_test.dart';
import 'package:salesforce_business_manager/core/utils/date_utils.dart';

String _iso(DateRange r) => '${AppDate.iso(r.start)}..${AppDate.iso(r.end)}';

ComparisonWindow _of(
  DateRange range,
  PeriodType type, {
  ComparisonBasis basis = ComparisonBasis.previousPeriod,
  DateTime? now,
}) =>
    ComparisonWindow.of(range, type, basis, now: now ?? DateTime(2030, 1, 1));

void main() {
  group('ComparisonWindow, a finished period', () {
    test('a financial year is compared with the one before', () {
      final w = _of(const FinancialYear(2025).range, PeriodType.financialYear);
      expect(w.isToDate, isFalse);
      expect(_iso(w.previous), '2024-04-01..2025-03-31');
    });

    test('a quarter is compared with the quarter before', () {
      final w = _of(DateRange(DateTime(2025, 4, 1), DateTime(2025, 6, 30)),
          PeriodType.quarter);
      expect(_iso(w.previous), '2025-01-01..2025-03-31');
    });

    test('a month is compared with the month before, leap February too', () {
      final w = _of(DateRange(DateTime(2024, 3, 1), DateTime(2024, 3, 31)),
          PeriodType.month);
      expect(_iso(w.previous), '2024-02-01..2024-02-29');
    });

    test('a custom range is compared with the same number of days before', () {
      final w = _of(DateRange(DateTime(2026, 1, 11), DateTime(2026, 1, 20)),
          PeriodType.custom);
      expect(_iso(w.previous), '2026-01-01..2026-01-10');
    });

    test('"last year" is the same dates a year earlier, keeping month ends',
        () {
      final w = _of(DateRange(DateTime(2024, 2, 1), DateTime(2024, 2, 29)),
          PeriodType.month,
          basis: ComparisonBasis.lastYear);
      expect(_iso(w.previous), '2023-02-01..2023-02-28');
    });
  });

  group('ComparisonWindow, a running period', () {
    test('both sides stop at the same day', () {
      final w = _of(const FinancialYear(2026).range, PeriodType.financialYear,
          now: DateTime(2026, 10, 22, 15, 30));
      expect(w.isToDate, isTrue);
      expect(_iso(w.current), '2026-04-01..2026-10-22');
      expect(_iso(w.previous), '2025-04-01..2025-10-22');
    });

    test('"last year" while running stops a year before today', () {
      final w = _of(DateRange(DateTime(2026, 10, 1), DateTime(2026, 10, 31)),
          PeriodType.month,
          basis: ComparisonBasis.lastYear, now: DateTime(2026, 10, 22));
      expect(_iso(w.current), '2026-10-01..2026-10-22');
      expect(_iso(w.previous), '2025-10-01..2025-10-22');
    });

    test('the previous side never runs past its own end', () {
      // 31 days into March against a 29-day February.
      final w = _of(DateRange(DateTime(2024, 3, 1), DateTime(2024, 3, 31)),
          PeriodType.month,
          now: DateTime(2024, 3, 30));
      expect(_iso(w.previous), '2024-02-01..2024-02-29');
    });

    test('a period that has not started yet is not to-date', () {
      final w = _of(const FinancialYear(2027).range, PeriodType.financialYear,
          now: DateTime(2026, 10, 22));
      expect(w.isToDate, isFalse);
    });
  });
}
