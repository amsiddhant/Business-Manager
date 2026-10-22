import '../../core/utils/date_utils.dart';
import '../../core/utils/money.dart';
import '../../models/expense.dart';
import '../profit_calculation_service.dart';

/// Headline figures for a list of expenses, as listed (no date filter).
class ExpenseListSummary {
  const ExpenseListSummary({
    required this.count,
    required this.activeCount,
    required this.recurringCount,
    required this.dealerCount,
    required this.annualRunRate,
    required this.oneTimeTotal,
    required this.dealerAnnual,
    required this.proratedInRange,
  });

  final int count;
  final int activeCount;

  /// Active recurring expenses.
  final int recurringCount;

  /// Expenses mirrored from a dealer.
  final int dealerCount;

  /// What active recurring expenses cost over a year.
  final Money annualRunRate;

  /// The full amount of active one-time expenses.
  final Money oneTimeTotal;

  /// The part of [annualRunRate] that comes from dealers.
  final Money dealerAnnual;

  /// Active expenses prorated to the range given to `summariseExpenses`.
  final Money proratedInRange;

  Money get monthlyRunRate => annualRunRate / 12;
}

/// An expense's cost over the current month and financial year.
class ExpenseProration {
  const ExpenseProration({
    required this.thisMonth,
    required this.thisFinancialYear,
    required this.financialYear,
  });

  final Money thisMonth;
  final Money thisFinancialYear;
  final FinancialYear financialYear;
}

extension ExpenseSummaries on ProfitCalculationService {
  /// Figures for [expenses]; [range] (default: the current month) is the
  /// window the prorated total covers.
  ExpenseListSummary summariseExpenses(Iterable<Expense> expenses,
      {DateRange? range, DateTime? now}) {
    final today = now ?? DateTime.now();
    final window = range ?? _monthOf(today);
    var count = 0, active = 0, recurring = 0, dealers = 0;
    var annual = Money.zero, oneTime = Money.zero;
    var dealerAnnual = Money.zero, prorated = Money.zero;
    for (final e in expenses) {
      count++;
      if (e.isFromDealer) dealers++;
      if (!e.isActive) continue;
      active++;
      prorated += proratedExpense(e, window);
      if (e.frequency.isRecurring) {
        recurring++;
        annual += e.annualisedAmount;
        if (e.isFromDealer) dealerAnnual += e.annualisedAmount;
      } else {
        oneTime += e.amount;
      }
    }
    return ExpenseListSummary(
      count: count,
      activeCount: active,
      recurringCount: recurring,
      dealerCount: dealers,
      annualRunRate: annual,
      oneTimeTotal: oneTime,
      dealerAnnual: dealerAnnual,
      proratedInRange: prorated,
    );
  }

  /// [expense] prorated to the month and financial year containing [now].
  ExpenseProration prorationOf(Expense expense, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final fy = FinancialYear.forDate(today);
    return ExpenseProration(
      thisMonth: proratedExpense(expense, _monthOf(today)),
      thisFinancialYear: proratedExpense(expense, fy.range),
      financialYear: fy,
    );
  }
}

DateRange _monthOf(DateTime d) =>
    DateRange(DateTime(d.year, d.month, 1), DateTime(d.year, d.month + 1, 0));
