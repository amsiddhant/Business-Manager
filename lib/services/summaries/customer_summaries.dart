import '../../core/enums.dart';
import '../../core/utils/money.dart';
import '../../models/customer.dart';
import '../profit_calculation_service.dart';

/// Headline figures for a list of customers, as listed.
class CustomerListSummary {
  const CustomerListSummary({
    required this.count,
    required this.wonCount,
    required this.inProgressCount,
    required this.pendingCount,
    required this.cancelledCount,
    required this.activeContracts,
    required this.expiredContracts,
    required this.renewalsDue,
    required this.annualRecurring,
  });

  final int count;

  /// Deals by status.
  final int wonCount;
  final int inProgressCount;
  final int pendingCount;
  final int cancelledCount;

  /// Contracts in scope that haven't expired (open-ended ones count).
  final int activeContracts;
  final int expiredContracts;

  /// Active contracts that expire within the renewal window.
  final int renewalsDue;

  /// What the active contracts bill in a year: recurring prices and add-ons,
  /// monthly ones times twelve. One-time charges are not included.
  final Money annualRecurring;

  /// Deals still open (pending or in progress).
  int get openCount => inProgressCount + pendingCount;

  /// Won deals as a share of the deals that have been decided (won or lost),
  /// or null while none has.
  double? get winRate {
    final decided = wonCount + cancelledCount;
    return decided == 0 ? null : wonCount / decided * 100;
  }

  static const empty = CustomerListSummary(
    count: 0,
    wonCount: 0,
    inProgressCount: 0,
    pendingCount: 0,
    cancelledCount: 0,
    activeContracts: 0,
    expiredContracts: 0,
    renewalsDue: 0,
    annualRecurring: Money.zero,
  );
}

extension CustomerSummaries on ProfitCalculationService {
  /// The customer's active contracts in scope: [businessId]'s contract, or
  /// every business's under "All Businesses" (null).
  List<ServiceContract> customerContractsInScope(
    Customer customer,
    String? businessId,
  ) {
    if (businessId != null) {
      final c = customer.activeContractFor(businessId);
      return c == null ? const [] : [c];
    }
    return customer.allActiveContracts.toList();
  }

  /// The soonest expiry among the customer's active contracts in scope that
  /// have one, or null.
  DateTime? customerNextExpiry(Customer customer, String? businessId) {
    DateTime? soonest;
    for (final c in customerContractsInScope(customer, businessId)) {
      final e = c.expiryDate;
      if (e != null && (soonest == null || e.isBefore(soonest))) soonest = e;
    }
    return soonest;
  }

  /// The annual recurring value of the customer's active, unexpired contracts
  /// in scope.
  Money customerAnnualRecurring(
    Customer customer,
    String? businessId, {
    required DateTime now,
  }) {
    var total = Money.zero;
    for (final c in customerContractsInScope(customer, businessId)) {
      if (!c.isExpiredAsOf(now)) total += c.annualTotal;
    }
    return total;
  }

  CustomerListSummary summariseCustomers(
    Iterable<Customer> customers, {
    String? businessId,
    required DateTime now,
    int renewalWindowDays = 30,
  }) {
    var count = 0, won = 0, inProgress = 0, pending = 0, cancelled = 0;
    var active = 0, expired = 0, due = 0;
    var annual = Money.zero;
    final horizon = now.add(Duration(days: renewalWindowDays));
    for (final c in customers) {
      count++;
      switch (c.dealStatus) {
        case DealStatus.successful:
          won++;
        case DealStatus.inProgress:
          inProgress++;
        case DealStatus.pending:
          pending++;
        case DealStatus.cancelled:
          cancelled++;
      }
      for (final k in customerContractsInScope(c, businessId)) {
        if (k.isExpiredAsOf(now)) {
          expired++;
          continue;
        }
        active++;
        annual += k.annualTotal;
        final e = k.expiryDate;
        if (e != null && !e.isAfter(horizon)) due++;
      }
    }
    return CustomerListSummary(
      count: count,
      wonCount: won,
      inProgressCount: inProgress,
      pendingCount: pending,
      cancelledCount: cancelled,
      activeContracts: active,
      expiredContracts: expired,
      renewalsDue: due,
      annualRecurring: annual,
    );
  }
}
