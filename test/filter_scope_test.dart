import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:salesforce_business_manager/core/utils/date_utils.dart';
import 'package:salesforce_business_manager/state/filter_controller.dart';

void main() {
  final now = DateTime(2026, 10, 22);

  /// What UserPrefs stores and reads back.
  Map<String, Object?> viaPrefs(FilterController f) =>
      (jsonDecode(jsonEncode(f.toJson())) as Map).cast<String, Object?>();

  test('a quarter selection survives a reload', () {
    final a = FilterController(now: now)
      ..selectBusiness('BIZ-00002')
      ..setFinancialYear(FinancialYear(2025))
      ..setQuarter(FinancialQuarter.q3)
      ..setPeriodType(PeriodType.quarter);

    final b = FilterController(now: now)..restore(viaPrefs(a), now: now);
    expect(b.selectedBusinessId, 'BIZ-00002');
    expect(b.periodType, PeriodType.quarter);
    expect(b.quarter, FinancialQuarter.q3);
    expect(b.financialYear.startYear, 2025);
    expect(b.range.start, a.range.start);
    expect(b.range.end, a.range.end);
  });

  test('a custom range survives a reload', () {
    final a = FilterController(now: now)
      ..setCustomRange(DateRange(DateTime(2026, 1, 5), DateTime(2026, 2, 20)));
    final b = FilterController(now: now)..restore(viaPrefs(a), now: now);
    expect(b.periodType, PeriodType.custom);
    expect(b.range.start, DateTime(2026, 1, 5));
    expect(b.range.end.year, 2026);
    expect(b.range.end.month, 2);
    expect(b.range.end.day, 20);
  });

  test('a month selection survives a reload', () {
    final a = FilterController(now: now)..setMonth(3, 2026);
    final b = FilterController(now: now)..restore(viaPrefs(a), now: now);
    expect(b.periodType, a.periodType);
    expect(b.month, 3);
    expect(b.monthYear, 2026);
  });

  test('null or junk restores the defaults', () {
    final fresh = FilterController(now: now);
    for (final json in <Map<String, Object?>?>[
      null,
      {},
      {'type': 'nonsense', 'fy': 'x', 'month': 13, 'business': 7},
      {'type': 'custom'}, // custom without a range
      {'type': 'custom', 'from': '2026-03-01', 'to': '2026-01-01'},
    ]) {
      final f = FilterController(now: now)
        ..selectBusiness('BIZ-1')
        ..restore(json, now: now);
      expect(f.isAllBusinesses, isTrue, reason: '$json');
      expect(f.periodType, PeriodType.financialYear, reason: '$json');
      expect(f.financialYear.startYear, fresh.financialYear.startYear);
      expect(f.month, inInclusiveRange(1, 12));
    }
  });

  test('restore notifies listeners once', () {
    final f = FilterController(now: now);
    var n = 0;
    f.addListener(() => n++);
    f.restore({'business': 'BIZ-9', 'type': 'calendarYear', 'cy': 2025},
        now: now);
    expect(n, 1);
    expect(f.periodType, PeriodType.calendarYear);
    expect(f.calendarYear, 2025);
  });
}
