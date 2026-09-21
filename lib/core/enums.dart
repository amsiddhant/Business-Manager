/// Central definitions for all enumerated domain values.
///
/// Every enum exposes a stable [wire] string used for persistence (Firestore /
/// local storage) and a human friendly [label] used in the UI. Parsing is done
/// through [fromWire] helpers so that unknown/legacy values degrade gracefully
/// instead of throwing.
library;

/// Application user roles. Order matters: higher index == more privilege.
enum UserRole {
  user('USER', 'User'),
  admin('ADMIN', 'Admin'),
  owner('OWNER', 'Owner');

  const UserRole(this.wire, this.label);
  final String wire;
  final String label;

  static UserRole fromWire(String? value) {
    return UserRole.values.firstWhere(
      (e) => e.wire == value,
      orElse: () => UserRole.user,
    );
  }

  bool get isOwner => this == UserRole.owner;
  bool get isAdmin => this == UserRole.admin;
  bool get isUser => this == UserRole.user;

  /// True when this role sits at or above [other] in the privilege hierarchy.
  bool atLeast(UserRole other) => index >= other.index;
}

/// Generic lifecycle status used by most entities.
enum EntityStatus {
  active('ACTIVE', 'Active'),
  inactive('INACTIVE', 'Inactive'),
  archived('ARCHIVED', 'Archived');

  const EntityStatus(this.wire, this.label);
  final String wire;
  final String label;

  static EntityStatus fromWire(String? value) {
    return EntityStatus.values.firstWhere(
      (e) => e.wire == value,
      orElse: () => EntityStatus.active,
    );
  }
}

/// Account status for users.
enum AccountStatus {
  active('ACTIVE', 'Active'),
  disabled('DISABLED', 'Disabled');

  const AccountStatus(this.wire, this.label);
  final String wire;
  final String label;

  static AccountStatus fromWire(String? value) {
    return AccountStatus.values.firstWhere(
      (e) => e.wire == value,
      orElse: () => AccountStatus.active,
    );
  }
}

/// Supported currencies. Additional currencies can be appended freely.
enum CurrencyCode {
  inr('INR', '₹', 'Indian Rupee'),
  usd('USD', r'$', 'US Dollar'),
  eur('EUR', '€', 'Euro'),
  gbp('GBP', '£', 'British Pound');

  const CurrencyCode(this.wire, this.symbol, this.label);
  final String wire;
  final String symbol;
  final String label;

  static CurrencyCode fromWire(String? value) {
    return CurrencyCode.values.firstWhere(
      (e) => e.wire == value,
      orElse: () => CurrencyCode.inr,
    );
  }
}

/// Advertising / marketing platforms.
enum CampaignPlatform {
  meta('META', 'Meta Ads'),
  google('GOOGLE', 'Google Ads'),
  tiktok('TIKTOK', 'TikTok Ads'),
  youtube('YOUTUBE', 'YouTube Ads'),
  linkedin('LINKEDIN', 'LinkedIn Ads'),
  other('OTHER', 'Other');

  const CampaignPlatform(this.wire, this.label);
  final String wire;
  final String label;

  static CampaignPlatform fromWire(String? value) {
    return CampaignPlatform.values.firstWhere(
      (e) => e.wire == value,
      orElse: () => CampaignPlatform.other,
    );
  }
}

enum CampaignStatus {
  draft('DRAFT', 'Draft'),
  active('ACTIVE', 'Active'),
  paused('PAUSED', 'Paused'),
  completed('COMPLETED', 'Completed'),
  cancelled('CANCELLED', 'Cancelled');

  const CampaignStatus(this.wire, this.label);
  final String wire;
  final String label;

  static CampaignStatus fromWire(String? value) {
    return CampaignStatus.values.firstWhere(
      (e) => e.wire == value,
      orElse: () => CampaignStatus.draft,
    );
  }
}

enum OrderStatus {
  pending('PENDING', 'Pending'),
  confirmed('CONFIRMED', 'Confirmed'),
  processing('PROCESSING', 'Processing'),
  shipped('SHIPPED', 'Shipped'),
  delivered('DELIVERED', 'Delivered'),
  cancelled('CANCELLED', 'Cancelled'),
  returned('RETURNED', 'Returned');

  const OrderStatus(this.wire, this.label);
  final String wire;
  final String label;

  static OrderStatus fromWire(String? value) {
    return OrderStatus.values.firstWhere(
      (e) => e.wire == value,
      orElse: () => OrderStatus.pending,
    );
  }

  /// Whether an order in this status contributes to recognised revenue.
  ///
  /// Cancelled orders are fully excluded. Returned/refunded orders still
  /// contribute their retained (non-refunded) portion, so they remain
  /// recognised — the refund amount is netted off in [Order.recognisedRevenue].
  bool get contributesToRevenue => this != OrderStatus.cancelled;
}

/// Frequency for recurring expenses / dealer costs.
enum RecurrenceFrequency {
  oneTime('ONE_TIME', 'One-Time', 0),
  monthly('MONTHLY', 'Monthly', 12),
  quarterly('QUARTERLY', 'Quarterly', 4),
  halfYearly('HALF_YEARLY', 'Half-Yearly', 2),
  yearly('YEARLY', 'Yearly', 1);

  const RecurrenceFrequency(this.wire, this.label, this.occurrencesPerYear);
  final String wire;
  final String label;

  /// How many times this cost is incurred within a single year. One-time is 0
  /// because it is not annualised (handled specially by the proration engine).
  final int occurrencesPerYear;

  static RecurrenceFrequency fromWire(String? value) {
    return RecurrenceFrequency.values.firstWhere(
      (e) => e.wire == value,
      orElse: () => RecurrenceFrequency.oneTime,
    );
  }

  bool get isRecurring => this != RecurrenceFrequency.oneTime;
}

/// Business expense categories.
enum ExpenseCategory {
  domain('DOMAIN', 'Domain'),
  crm('CRM', 'CRM'),
  hosting('HOSTING', 'Hosting'),
  dealer('DEALER', 'Dealer'),
  software('SOFTWARE', 'Software'),
  subscription('SUBSCRIPTION', 'Subscription'),
  paymentGateway('PAYMENT_GATEWAY', 'Payment Gateway'),
  shipping('SHIPPING', 'Shipping'),
  office('OFFICE', 'Office'),
  employee('EMPLOYEE', 'Employee'),
  advertising('ADVERTISING', 'Advertising'),
  other('OTHER', 'Other');

  const ExpenseCategory(this.wire, this.label);
  final String wire;
  final String label;

  static ExpenseCategory fromWire(String? value) {
    return ExpenseCategory.values.firstWhere(
      (e) => e.wire == value,
      orElse: () => ExpenseCategory.other,
    );
  }
}

/// Sales/relationship stage for a customer record (CRM deal pipeline).
enum DealStatus {
  pending('PENDING', 'Pending'),
  inProgress('IN_PROGRESS', 'In Progress'),
  successful('SUCCESSFUL', 'Successful'),
  cancelled('CANCELLED', 'Cancelled');

  const DealStatus(this.wire, this.label);
  final String wire;
  final String label;

  static DealStatus fromWire(String? value) {
    return DealStatus.values.firstWhere(
      (e) => e.wire == value,
      orElse: () => DealStatus.pending,
    );
  }
}

/// Subscription plan tier sold on a won ("Successful") deal's service contract.
enum SubscriptionPlan {
  basic('BASIC', 'Basic'),
  pro('PRO', 'Pro'),
  legend('LEGEND', 'Legend');

  const SubscriptionPlan(this.wire, this.label);
  final String wire;
  final String label;

  static SubscriptionPlan fromWire(String? value) {
    return SubscriptionPlan.values.firstWhere(
      (e) => e.wire == value,
      orElse: () => SubscriptionPlan.basic,
    );
  }
}

/// Billing cadence for a service contract's subscription + add-on pricing.
///
/// [perYear] is how many times the recorded price is billed within one year,
/// used to annualise the contract total for reporting/comparison.
enum BillingCycle {
  monthly('MONTHLY', 'Monthly', 'mo', 12),
  yearly('YEARLY', 'Yearly', 'yr', 1);

  const BillingCycle(this.wire, this.label, this.unit, this.perYear);
  final String wire;
  final String label;

  /// Short suffix for prominent price display (e.g. "₹12,000 /yr").
  final String unit;
  final int perYear;

  static BillingCycle fromWire(String? value) {
    return BillingCycle.values.firstWhere(
      (e) => e.wire == value,
      orElse: () => BillingCycle.yearly,
    );
  }
}

/// Rough headcount band describing the size of a customer's organisation.
enum CompanySize {
  micro('MICRO', 'Micro (1–10)'),
  small('SMALL', 'Small (11–50)'),
  medium('MEDIUM', 'Medium (51–250)'),
  large('LARGE', 'Large (251–1000)'),
  enterprise('ENTERPRISE', 'Enterprise (1000+)');

  const CompanySize(this.wire, this.label);
  final String wire;
  final String label;

  static CompanySize fromWire(String? value) {
    return CompanySize.values.firstWhere(
      (e) => e.wire == value,
      orElse: () => CompanySize.small,
    );
  }
}

/// Kind of audit action, for the audit trail.
enum AuditAction {
  create('CREATE', 'Created'),
  update('UPDATE', 'Updated'),
  delete('DELETE', 'Deleted'),
  archive('ARCHIVE', 'Archived'),
  login('LOGIN', 'Signed in'),
  logout('LOGOUT', 'Signed out');

  const AuditAction(this.wire, this.label);
  final String wire;
  final String label;

  static AuditAction fromWire(String? value) {
    return AuditAction.values.firstWhere(
      (e) => e.wire == value,
      orElse: () => AuditAction.update,
    );
  }
}
