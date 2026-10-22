import '../core/enums.dart';
import '../core/routing/app_routes.dart';
import '../core/utils/date_utils.dart';
import '../core/utils/money.dart';
import '../models/campaign.dart';
import '../models/customer.dart';
import '../models/expense.dart';
import '../models/order.dart';
import '../models/product.dart';
import 'profit_calculation_service.dart';

enum AlertSeverity {
  high('Needs action'),
  medium('Worth a look'),
  info('For your information');

  const AlertSeverity(this.label);
  final String label;
}

enum AlertType {
  contractExpiring('Contract expiring'),
  contractOverdue('Contract expired'),
  campaignEnding('Campaign ending'),
  lowMargin('Low margin'),
  unusualSpend('Unusual spend'),
  dataWarning('Data not loaded'),
  demoMode('Demo mode');

  const AlertType(this.label);
  final String label;
}

/// Something that needs (or deserves) the user's attention.
class AppAlert {
  const AppAlert({
    required this.key,
    required this.type,
    required this.severity,
    required this.title,
    required this.message,
    this.route,
    this.due,
  });

  /// Stable across reloads, and specific to the occurrence: a renewed
  /// contract's new expiry is a new alert, so dismissing the old one doesn't
  /// hide it.
  final String key;
  final AlertType type;
  final AlertSeverity severity;
  final String title;
  final String message;

  /// Where tapping the alert goes.
  final String? route;

  /// The date it's about, when there is one (sorts soonest first).
  final DateTime? due;
}

/// A customer's active contract and how far away its expiry is.
class ContractDue {
  const ContractDue({
    required this.customer,
    required this.contract,
    required this.daysLeft,
  });

  final Customer customer;
  final ServiceContract contract;

  /// Negative once it has expired.
  final int daysLeft;
}

/// Active contracts expiring between [fromDays] and [toDays] days from
/// [now] (negative = already expired), soonest first. Cancelled deals are
/// skipped. With [businessId], only that business's contracts.
List<ContractDue> contractsDue(
  List<Customer> customers, {
  required DateTime now,
  required int fromDays,
  required int toDays,
  String? businessId,
}) {
  final today = AppDate.dayOnly(now);
  final result = <ContractDue>[];
  for (final c in customers) {
    if (c.dealStatus == DealStatus.cancelled) continue;
    for (final contract in c.allActiveContracts) {
      if (businessId != null && contract.businessId != businessId) continue;
      final expiry = contract.expiryDate;
      if (expiry == null) continue;
      final days = AppDate.dayOnly(expiry).difference(today).inDays;
      if (days < fromDays || days > toDays) continue;
      result.add(ContractDue(customer: c, contract: contract, daysLeft: days));
    }
  }
  result.sort((a, b) => a.daysLeft.compareTo(b.daysLeft));
  return result;
}

/// Builds the alerts from data that's already loaded — no reads.
///
/// Rules:
/// * contracts expiring within 30 days (7 or fewer: high), or expired in the
///   last 90 days and not renewed (high);
/// * campaigns ending within 7 days;
/// * products with a net margin under 10% over the last 90 days (negative:
///   high), once they have 3+ orders;
/// * a cost line this month far above its last 6 months (robust z-score of
///   2.5 or more against the median; 4+: high);
/// * partial-load warnings (high), and demo mode (info).
class AlertService {
  const AlertService();

  static const _profit = ProfitCalculationService();

  static const lowMarginPercent = 10.0;
  static const minOrdersForMargin = 3;
  static const spendZ = 2.5;
  static const spendZHigh = 4.0;

  List<AppAlert> build({
    required List<Customer> customers,
    required List<Campaign> campaigns,
    required List<Order> orders,
    required List<Expense> expenses,
    required List<Product> products,
    required List<String> warnings,
    required bool demoMode,
    required DateTime now,
    required CurrencyCode Function(String businessId) currencyOf,
  }) {
    final today = AppDate.dayOnly(now);
    final alerts = <AppAlert>[
      ..._contracts(customers, today, currencyOf),
      ..._campaignsEnding(campaigns, today),
      ..._lowMargins(products, orders, campaigns, today, currencyOf),
      ..._unusualSpend(campaigns, expenses, today, currencyOf),
      for (final w in warnings)
        AppAlert(
          key: 'data-warning:${stableHash(w)}',
          type: AlertType.dataWarning,
          severity: AlertSeverity.high,
          title: 'Some data could not be loaded',
          message: w,
        ),
      if (demoMode)
        const AppAlert(
          key: 'demo-mode',
          type: AlertType.demoMode,
          severity: AlertSeverity.info,
          title: 'Demo mode active',
          message: 'Data is stored locally. Configure Firebase in Settings '
              'to go live.',
          route: Routes.settings,
        ),
    ];
    alerts.sort((a, b) {
      final bySeverity = a.severity.index.compareTo(b.severity.index);
      if (bySeverity != 0) return bySeverity;
      final ad = a.due, bd = b.due;
      if (ad != null && bd != null) return ad.compareTo(bd);
      return ad == null ? (bd == null ? 0 : 1) : -1;
    });
    return alerts;
  }

  Iterable<AppAlert> _contracts(List<Customer> customers, DateTime today,
      CurrencyCode Function(String) currencyOf) sync* {
    for (final due
        in contractsDue(customers, now: today, fromDays: -90, toDays: 30)) {
      final c = due.contract;
      final expiry = c.expiryDate!;
      final value =
          MoneyFormatter.format(c.annualTotal, currencyOf(c.businessId));
      final when = AppDate.format(expiry);
      final keyTail = '${due.customer.id}:${c.businessId}:${AppDate.iso(expiry)}';
      if (due.daysLeft < 0) {
        yield AppAlert(
          key: 'contract-overdue:$keyTail',
          type: AlertType.contractOverdue,
          severity: AlertSeverity.high,
          title: '${due.customer.name}: contract expired',
          message: 'Expired $when (${_days(-due.daysLeft)} ago) and hasn’t '
              'been renewed · $value a year.',
          route: Routes.customerDetailPath(due.customer.id),
          due: expiry,
        );
      } else {
        yield AppAlert(
          key: 'contract-expiring:$keyTail',
          type: AlertType.contractExpiring,
          severity:
              due.daysLeft <= 7 ? AlertSeverity.high : AlertSeverity.medium,
          title: '${due.customer.name}: contract expiring',
          message: '${_inDays(due.daysLeft)} ($when) · $value a year.',
          route: Routes.customerDetailPath(due.customer.id),
          due: expiry,
        );
      }
    }
  }

  Iterable<AppAlert> _campaignsEnding(
      List<Campaign> campaigns, DateTime today) sync* {
    for (final c in campaigns) {
      final end = c.endDate;
      if (end == null || c.status == CampaignStatus.cancelled) continue;
      final days = AppDate.dayOnly(end).difference(today).inDays;
      if (days < 0 || days > 7) continue;
      yield AppAlert(
        key: 'campaign-ending:${c.id}:${AppDate.iso(end)}',
        type: AlertType.campaignEnding,
        severity: AlertSeverity.medium,
        title: 'Campaign ending soon',
        message: '${c.name} ends ${_inDays(days).toLowerCase()} '
            '(${AppDate.format(end)}).',
        route: Routes.campaignDetailPath(c.id),
        due: end,
      );
    }
  }

  Iterable<AppAlert> _lowMargins(
    List<Product> products,
    List<Order> orders,
    List<Campaign> campaigns,
    DateTime today,
    CurrencyCode Function(String) currencyOf,
  ) sync* {
    final range =
        DateRange(DateTime(today.year, today.month, today.day - 89), today);
    final month = AppDate.iso(today).substring(0, 7);
    for (final p in _profit.productProfitability(
        products: products, orders: orders, campaigns: campaigns, range: range)) {
      if (p.orderCount < minOrdersForMargin || !p.revenue.isPositive) continue;
      if (p.margin >= lowMarginPercent) continue;
      final negative = p.netProfit.isNegative;
      yield AppAlert(
        key: 'low-margin:${p.product.id}:$month',
        type: AlertType.lowMargin,
        severity: negative ? AlertSeverity.high : AlertSeverity.medium,
        title: negative
            ? '${p.product.name} is losing money'
            : '${p.product.name}: thin margin',
        message: 'Net margin ${PercentFormatter.format(p.margin)} over the '
            'last 90 days, on '
            '${MoneyFormatter.format(p.revenue, currencyOf(p.product.businessId))}'
            ' revenue.',
        route: Routes.productDetailPath(p.product.id),
      );
    }
  }

  Iterable<AppAlert> _unusualSpend(
    List<Campaign> campaigns,
    List<Expense> expenses,
    DateTime today,
    CurrencyCode Function(String) currencyOf,
  ) sync* {
    // Per business: amounts in different currencies don't mix.
    final ids = {
      for (final c in campaigns) c.businessId,
      for (final e in expenses) e.businessId,
    };
    final month = AppDate.iso(today).substring(0, 7);
    for (final id in ids) {
      final history = _profit.monthlySpendByCategory(
        campaigns: [for (final c in campaigns) if (c.businessId == id) c],
        expenses: [for (final e in expenses) if (e.businessId == id) e],
        asOf: today,
      );
      for (final MapEntry(key: line, value: months) in history.entries) {
        final past = [for (final m in months.take(months.length - 1)) m.major];
        final current = months.last.major;
        final z = robustZ(current, past);
        if (z == null || z < spendZ) continue;
        final currency = currencyOf(id);
        final median = _median(past);
        yield AppAlert(
          key: 'unusual-spend:$id:$line:$month',
          type: AlertType.unusualSpend,
          severity: z >= spendZHigh ? AlertSeverity.high : AlertSeverity.medium,
          title: 'Unusual $line spend',
          message: '${MoneyFormatter.format(months.last, currency)} this month '
              'so far, against a typical '
              '${MoneyFormatter.format(Money.fromMajor(median), currency)}.',
          route: line == 'Marketing' ? Routes.campaigns : Routes.expenses,
        );
      }
    }
  }

  /// How far [value] sits above [history]'s median, in robust standard
  /// deviations (median absolute deviation × 1.4826). Null when there isn't
  /// enough history (3+ months with spend) or [value] isn't above the median.
  /// With no spread at all, anything over double the median counts as far.
  static double? robustZ(double value, List<double> history) {
    if (history.where((v) => v > 0).length < 3) return null;
    final median = _median(history);
    if (value <= median) return null;
    final mad = _median([for (final v in history) (v - median).abs()]);
    if (mad == 0) {
      return median > 0 && value > median * 2 ? double.infinity : null;
    }
    return (value - median) / (mad * 1.4826);
  }

  static double _median(List<double> values) {
    final sorted = [...values]..sort();
    final mid = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[mid]
        : (sorted[mid - 1] + sorted[mid]) / 2;
  }

  static String _days(int n) => '$n day${n == 1 ? '' : 's'}';

  static String _inDays(int n) => switch (n) {
        0 => 'Today',
        1 => 'Tomorrow',
        _ => 'In ${_days(n)}',
      };

  /// 32-bit FNV-1a, so a key built from text is the same on every run. The
  /// multiply by the FNV prime (2^24 + 403) is split so it stays exact on the
  /// web, where integers are doubles.
  static String stableHash(String text) {
    var h = 0x811c9dc5;
    for (final unit in text.codeUnits) {
      h = (h ^ unit) & 0xffffffff;
      h = (h * 403 + ((h & 0xff) << 24)) & 0xffffffff;
    }
    return h.toRadixString(16);
  }
}
