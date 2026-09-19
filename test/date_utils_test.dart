import 'package:flutter_test/flutter_test.dart';
import 'package:salesforce_business_manager/core/utils/date_utils.dart';

void main() {
  group('FinancialYear (Indian FY: 1 Apr – 31 Mar)', () {
    test('forDate maps April–December to the current start year', () {
      expect(FinancialYear.forDate(DateTime(2026, 4, 1)).startYear, 2026);
      expect(FinancialYear.forDate(DateTime(2026, 9, 19)).startYear, 2026);
      expect(FinancialYear.forDate(DateTime(2026, 12, 31)).startYear, 2026);
    });

    test('forDate maps January–March to the previous start year', () {
      expect(FinancialYear.forDate(DateTime(2026, 1, 1)).startYear, 2025);
      expect(FinancialYear.forDate(DateTime(2026, 3, 31)).startYear, 2025);
    });

    test('range spans 1 Apr to 31 Mar of the next year', () {
      final fy = const FinancialYear(2026);
      expect(fy.range.start, DateTime(2026, 4, 1));
      // End is clamped to the end of the day.
      expect(fy.range.end.year, 2027);
      expect(fy.range.end.month, 3);
      expect(fy.range.end.day, 31);
    });

    test('label uses the FY YYYY-YY format', () {
      expect(const FinancialYear(2026).label, 'FY 2026-27');
      expect(const FinancialYear(1999).label, 'FY 1999-00');
      expect(const FinancialYear(2009).label, 'FY 2009-10');
    });

    test('previous/next navigation', () {
      final fy = const FinancialYear(2026);
      expect(fy.previous.startYear, 2025);
      expect(fy.next.startYear, 2027);
    });

    test('endYear is start + 1', () {
      expect(const FinancialYear(2026).endYear, 2027);
    });

    test('equality is value based', () {
      expect(const FinancialYear(2026), equals(const FinancialYear(2026)));
      expect(const FinancialYear(2026).hashCode,
          const FinancialYear(2026).hashCode);
    });
  });

  group('PeriodOptions (data-derived filter options)', () {
    final now = DateTime(2026, 9, 20); // FY 2026-27, CY 2026

    test('financialYears spans min→max of data, newest-first', () {
      final dates = [
        DateTime(2024, 5, 1), // FY 2024
        DateTime(2026, 1, 10), // Jan -> FY 2025
        DateTime(2026, 6, 1), // FY 2026
      ];
      final fys = PeriodOptions.financialYears(dates, now: now);
      expect(fys.map((f) => f.startYear), [2026, 2025, 2024]);
    });

    test('financialYears includes forward-dated activity', () {
      final dates = [DateTime(2028, 5, 1)]; // FY 2028, beyond current
      final fys = PeriodOptions.financialYears(dates, now: now);
      // Current FY (2026) up through the future FY (2028), newest-first.
      expect(fys.map((f) => f.startYear), [2028, 2027, 2026]);
    });

    test('financialYears falls back to the current FY when no data', () {
      final fys = PeriodOptions.financialYears(const [], now: now);
      expect(fys.map((f) => f.startYear), [2026]);
    });

    test('calendarYears spans min→max of data, newest-first', () {
      final dates = [DateTime(2023, 3, 1), DateTime(2026, 8, 1)];
      final years = PeriodOptions.calendarYears(dates, now: now);
      expect(years, [2026, 2025, 2024, 2023]);
    });

    test('calendarYears falls back to the current year when no data', () {
      expect(PeriodOptions.calendarYears(const [], now: now), [2026]);
    });
  });

  group('DateRange', () {
    test('contains is inclusive at day granularity', () {
      final r = DateRange(DateTime(2026, 4, 1), DateTime(2026, 4, 30));
      expect(r.contains(DateTime(2026, 4, 1)), isTrue);
      expect(r.contains(DateTime(2026, 4, 30, 23, 59)), isTrue);
      expect(r.contains(DateTime(2026, 3, 31)), isFalse);
      expect(r.contains(DateTime(2026, 5, 1)), isFalse);
    });

    test('days counts inclusive calendar days', () {
      expect(DateRange(DateTime(2026, 4, 1), DateTime(2026, 4, 1)).days, 1);
      expect(DateRange(DateTime(2026, 4, 1), DateTime(2026, 4, 30)).days, 30);
    });

    test('overlapDays returns intersection size, 0 when disjoint', () {
      final a = DateRange(DateTime(2026, 4, 1), DateTime(2026, 6, 30));
      final b = DateRange(DateTime(2026, 6, 1), DateTime(2026, 12, 31));
      expect(a.overlapDays(b), 30); // June
      final c = DateRange(DateTime(2027, 1, 1), DateTime(2027, 1, 31));
      expect(a.overlapDays(c), 0);
    });
  });

  group('bucketForRange', () {
    test('short & yearly ranges bucket by month', () {
      expect(bucketForRange(DateRange(DateTime(2026, 4, 1), DateTime(2026, 6, 30))),
          TimeBucket.month);
      expect(bucketForRange(const FinancialYear(2026).range), TimeBucket.month);
    });

    test('multi-year ranges bucket by quarter then year', () {
      expect(
          bucketForRange(DateRange(DateTime(2024, 1, 1), DateTime(2026, 6, 30))),
          TimeBucket.quarter);
      expect(
          bucketForRange(DateRange(DateTime(2020, 1, 1), DateTime(2026, 12, 31))),
          TimeBucket.year);
    });
  });

  group('AppDate configurable display format', () {
    test('applies a valid pattern and reverts on invalid/empty', () {
      final date = DateTime(2026, 9, 19);
      AppDate.configureDisplayFormat('yyyy-MM-dd');
      expect(AppDate.format(date), '2026-09-19');

      AppDate.configureDisplayFormat('');
      expect(AppDate.displayPattern, AppDate.defaultPattern);

      // Restore default for other tests.
      AppDate.configureDisplayFormat(AppDate.defaultPattern);
      expect(AppDate.format(date), '19-Sep-2026');
    });

    test('null date renders an em dash', () {
      expect(AppDate.format(null), '—');
    });
  });
}
