import '../core/enums.dart';
import '../core/utils/date_utils.dart';
import '../core/utils/money.dart';
import 'audit_fields.dart';

/// A single add-on line item within a [ServiceContract] (e.g. "Priority
/// Support", "Extra Seats"). Priced at the contract's billing cycle. Stored as
/// an embedded map inside the customer document.
class ServiceAddOn {
  const ServiceAddOn({required this.name, this.price = Money.zero});

  final String name;
  final Money price;

  Map<String, dynamic> toMap() => {
        'name': name,
        'priceMinor': price.minor,
      };

  factory ServiceAddOn.fromMap(Map<String, dynamic> map) => ServiceAddOn(
        name: map['name'] as String? ?? '',
        price: Money((map['priceMinor'] as num?)?.toInt() ?? 0),
      );

  ServiceAddOn copyWith({String? name, Money? price}) =>
      ServiceAddOn(name: name ?? this.name, price: price ?? this.price);
}

/// The service contract captured when a customer's deal is marked
/// [DealStatus.successful]: the plan sold, its billing cadence, base price and
/// any add-on line items. Stored as an embedded object inside the customer
/// document (no separate collection / rules needed).
///
/// Add-ons are always recurring at the [billingCycle] (monthly or yearly). The
/// base plan price is normally recurring too, but can be flagged [priceOneTime]
/// (a one-off setup/licence charge) — when it is, it is excluded from the
/// recurring [total] and surfaced separately as [oneTimeTotal].
///
/// [total] is the recurring subscription value at the cadence (billable
/// add-ons + the base price unless it is one-time); [annualTotal] annualises it
/// so monthly and yearly contracts compare on the same footing.
class ServiceContract {
  const ServiceContract({
    this.purchaseDate,
    this.expiryDate,
    this.price = Money.zero,
    this.priceOneTime = false,
    this.plan = SubscriptionPlan.basic,
    this.billingCycle = BillingCycle.yearly,
    this.addOns = const [],
    this.comment = '',
  });

  final DateTime? purchaseDate;
  final DateTime? expiryDate;

  /// Base plan price. Recurring at the [billingCycle] unless [priceOneTime].
  final Money price;

  /// When true the [price] is a one-off charge (e.g. setup / perpetual licence)
  /// and is excluded from the recurring subscription [total].
  final bool priceOneTime;
  final SubscriptionPlan plan;
  final BillingCycle billingCycle;
  final List<ServiceAddOn> addOns;
  final String comment;

  /// Sum of all add-on prices at the billing cycle.
  Money get addOnsTotal =>
      addOns.fold(Money.zero, (sum, a) => sum + a.price);

  /// The base plan's contribution to the recurring subscription — zero when the
  /// plan price is a one-time charge.
  Money get recurringPrice => priceOneTime ? Money.zero : price;

  /// Full recurring subscription value at the billing cycle (recurring base +
  /// add-ons). Excludes any one-time plan charge.
  Money get total => recurringPrice + addOnsTotal;

  /// The one-off portion of the contract (the plan price when flagged
  /// [priceOneTime]); zero otherwise.
  Money get oneTimeTotal => priceOneTime ? price : Money.zero;

  /// True when a separate one-time charge should be surfaced.
  bool get hasOneTimeCharge => priceOneTime && price.isPositive;

  /// The subscription value annualised, so monthly and yearly contracts can be
  /// compared on the same footing. Excludes one-time charges.
  Money get annualTotal => total * billingCycle.perYear;

  /// Whether the contract has an expiry date that is already in the past.
  bool isExpiredAsOf(DateTime now) =>
      expiryDate != null &&
      expiryDate!.isBefore(DateTime(now.year, now.month, now.day));

  /// Calendar span from [now] to the [expiryDate] (years/months/days), or null
  /// when the contract has no expiry. [TimeRemaining.isPast] indicates whether
  /// the term has already lapsed.
  TimeRemaining? timeRemainingAsOf(DateTime now) => expiryDate == null
      ? null
      : TimeRemaining.between(now, expiryDate!);

  Map<String, dynamic> toMap() => {
        if (purchaseDate != null)
          'purchaseDate': purchaseDate!.toIso8601String(),
        if (expiryDate != null) 'expiryDate': expiryDate!.toIso8601String(),
        'priceMinor': price.minor,
        'priceOneTime': priceOneTime,
        'plan': plan.wire,
        'billingCycle': billingCycle.wire,
        'addOns': addOns.map((a) => a.toMap()).toList(),
        'comment': comment,
      };

  factory ServiceContract.fromMap(Map<String, dynamic> map) => ServiceContract(
        purchaseDate: parseDate(map['purchaseDate']),
        expiryDate: parseDate(map['expiryDate']),
        price: Money((map['priceMinor'] as num?)?.toInt() ?? 0),
        priceOneTime: map['priceOneTime'] as bool? ?? false,
        plan: SubscriptionPlan.fromWire(map['plan'] as String?),
        billingCycle: BillingCycle.fromWire(map['billingCycle'] as String?),
        addOns: [
          for (final a in (map['addOns'] as List<dynamic>? ?? const []))
            ServiceAddOn.fromMap(Map<String, dynamic>.from(a as Map)),
        ],
        comment: map['comment'] as String? ?? '',
      );

  ServiceContract copyWith({
    DateTime? purchaseDate,
    DateTime? expiryDate,
    Money? price,
    bool? priceOneTime,
    SubscriptionPlan? plan,
    BillingCycle? billingCycle,
    List<ServiceAddOn>? addOns,
    String? comment,
  }) =>
      ServiceContract(
        purchaseDate: purchaseDate ?? this.purchaseDate,
        expiryDate: expiryDate ?? this.expiryDate,
        price: price ?? this.price,
        priceOneTime: priceOneTime ?? this.priceOneTime,
        plan: plan ?? this.plan,
        billingCycle: billingCycle ?? this.billingCycle,
        addOns: addOns ?? this.addOns,
        comment: comment ?? this.comment,
      );
}

/// A single comment on a customer's activity thread. Stored as an embedded list
/// inside the customer document (no separate collection / rules needed).
class CustomerComment {
  const CustomerComment({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.text,
    this.createdAt,
  });

  final String id;
  final String authorId;
  final String authorName;
  final String text;
  final DateTime? createdAt;

  Map<String, dynamic> toMap() => {
        'id': id,
        'authorId': authorId,
        'authorName': authorName,
        'text': text,
        if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
      };

  factory CustomerComment.fromMap(Map<String, dynamic> map) => CustomerComment(
        id: map['id'] as String? ?? '',
        authorId: map['authorId'] as String? ?? '',
        authorName: map['authorName'] as String? ?? '',
        text: map['text'] as String? ?? '',
        createdAt: parseDate(map['createdAt']),
      );
}

/// A customer / lead that can be tagged to one or more businesses. Tracks CRM
/// contact details and a deal pipeline stage, plus an embedded activity comment
/// thread.
///
/// A customer is "tagged" to businesses via [businessIds]. The Owner may tag any
/// businesses; an Admin/User may only tag businesses they are assigned to (and,
/// when editing, must never drop a tag for a business they cannot see).
class Customer {
  const Customer({
    required this.id,
    required this.businessIds,
    required this.name,
    this.businessType = '',
    this.size = CompanySize.small,
    this.contactNo = '',
    this.email = '',
    this.city = '',
    this.state = '',
    this.country = 'India',
    this.socialMedia = '',
    this.dealStatus = DealStatus.pending,
    this.description = '',
    this.serviceContract,
    this.contractHistory = const [],
    this.comments = const [],
    this.audit = const AuditFields(),
  });

  final String id;

  /// The businesses this customer is tagged to. A customer may belong to
  /// several businesses at once; never empty for a persisted customer.
  final List<String> businessIds;
  final String name;
  final String businessType;
  final CompanySize size;
  final String contactNo;
  final String email;
  final String city;
  final String state;
  final String country;
  final String socialMedia;
  final DealStatus dealStatus;
  final String description;

  /// The current (most recent) service contract captured when the deal was won
  /// or last renewed. Null until the deal is marked [DealStatus.successful] and
  /// a contract is saved.
  final ServiceContract? serviceContract;

  /// Superseded contracts, newest-first: each entry is a previous term that was
  /// replaced by a renewal. The active term lives in [serviceContract]; this is
  /// the audit trail of past terms.
  final List<ServiceContract> contractHistory;
  final List<CustomerComment> comments;
  final AuditFields audit;

  /// True when a subscription contract has been recorded for this customer.
  bool get hasServiceContract => serviceContract != null;

  /// True when this customer has at least one superseded (renewed-past) term.
  bool get hasContractHistory => contractHistory.isNotEmpty;

  /// The number of terms recorded (current + superseded), i.e. how many times
  /// the contract has been established/renewed.
  int get contractTermCount =>
      (hasServiceContract ? 1 : 0) + contractHistory.length;

  /// Produces the customer that results from renewing the active contract with
  /// [renewal]: the current active term is pushed to the front of
  /// [contractHistory] and [renewal] becomes the new active [serviceContract].
  /// If there is no active contract this simply sets it (first-time capture).
  Customer withRenewedContract(ServiceContract renewal) => copyWith(
        dealStatus: DealStatus.successful,
        serviceContract: renewal,
        contractHistory: serviceContract == null
            ? contractHistory
            : [serviceContract!, ...contractHistory],
      );

  /// A single-line location summary (e.g. "Mumbai, Maharashtra, India").
  String get location => [city, state, country]
      .where((p) => p.trim().isNotEmpty)
      .join(', ');

  /// Reads the tagged businesses, tolerating the legacy scalar `businessId`
  /// field written before customers supported multi-business tagging.
  static List<String> _readBusinessIds(Map<String, dynamic> map) {
    final raw = map['businessIds'];
    if (raw is List) {
      return raw
          .map((e) => e?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
    }
    final legacy = map['businessId'] as String?;
    return (legacy != null && legacy.isNotEmpty) ? [legacy] : const [];
  }

  /// The most recent activity date: newest comment, else last update/creation.
  DateTime? get lastActivityAt {
    DateTime? latest = audit.updatedAt ?? audit.createdAt;
    for (final c in comments) {
      final d = c.createdAt;
      if (d != null && (latest == null || d.isAfter(latest))) latest = d;
    }
    return latest;
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'businessIds': businessIds,
        'name': name,
        'businessType': businessType,
        'size': size.wire,
        'contactNo': contactNo,
        'email': email,
        'city': city,
        'state': state,
        'country': country,
        'socialMedia': socialMedia,
        'dealStatus': dealStatus.wire,
        'description': description,
        if (serviceContract != null)
          'serviceContract': serviceContract!.toMap(),
        if (contractHistory.isNotEmpty)
          'contractHistory':
              contractHistory.map((c) => c.toMap()).toList(),
        'comments': comments.map((c) => c.toMap()).toList(),
        ...audit.toMap(),
      };

  factory Customer.fromMap(Map<String, dynamic> map) => Customer(
        id: map['id'] as String? ?? '',
        businessIds: _readBusinessIds(map),
        name: map['name'] as String? ?? '',
        businessType: map['businessType'] as String? ?? '',
        size: CompanySize.fromWire(map['size'] as String?),
        contactNo: map['contactNo'] as String? ?? '',
        email: map['email'] as String? ?? '',
        city: map['city'] as String? ?? '',
        state: map['state'] as String? ?? '',
        country: map['country'] as String? ?? 'India',
        socialMedia: map['socialMedia'] as String? ?? '',
        dealStatus: DealStatus.fromWire(map['dealStatus'] as String?),
        description: map['description'] as String? ?? '',
        serviceContract: map['serviceContract'] == null
            ? null
            : ServiceContract.fromMap(
                Map<String, dynamic>.from(map['serviceContract'] as Map)),
        contractHistory: [
          for (final c
              in (map['contractHistory'] as List<dynamic>? ?? const []))
            ServiceContract.fromMap(Map<String, dynamic>.from(c as Map)),
        ],
        comments: [
          for (final c in (map['comments'] as List<dynamic>? ?? const []))
            CustomerComment.fromMap(Map<String, dynamic>.from(c as Map)),
        ],
        audit: AuditFields.fromMap(map),
      );

  Customer copyWith({
    List<String>? businessIds,
    String? name,
    String? businessType,
    CompanySize? size,
    String? contactNo,
    String? email,
    String? city,
    String? state,
    String? country,
    String? socialMedia,
    DealStatus? dealStatus,
    String? description,
    ServiceContract? serviceContract,
    List<ServiceContract>? contractHistory,
    List<CustomerComment>? comments,
    AuditFields? audit,
  }) =>
      Customer(
        id: id,
        businessIds: businessIds ?? this.businessIds,
        name: name ?? this.name,
        businessType: businessType ?? this.businessType,
        size: size ?? this.size,
        contactNo: contactNo ?? this.contactNo,
        email: email ?? this.email,
        city: city ?? this.city,
        state: state ?? this.state,
        country: country ?? this.country,
        socialMedia: socialMedia ?? this.socialMedia,
        dealStatus: dealStatus ?? this.dealStatus,
        description: description ?? this.description,
        serviceContract: serviceContract ?? this.serviceContract,
        contractHistory: contractHistory ?? this.contractHistory,
        comments: comments ?? this.comments,
        audit: audit ?? this.audit,
      );
}
