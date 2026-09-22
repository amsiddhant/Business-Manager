import '../core/enums.dart';
import '../core/utils/date_utils.dart';
import '../core/utils/money.dart';
import 'audit_fields.dart';
import 'contact.dart';

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
    this.businessId = '',
    this.purchaseDate,
    this.expiryDate,
    this.price = Money.zero,
    this.priceOneTime = false,
    this.plan = SubscriptionPlan.basic,
    this.billingCycle = BillingCycle.yearly,
    this.addOns = const [],
    this.comment = '',
  });

  /// The specific business this contract is sold under. A customer may be tagged
  /// to several businesses; the invoice shows this business's details as the
  /// seller. Empty for legacy contracts written before per-contract business
  /// selection — callers fall back to the customer's first tagged business.
  final String businessId;

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
        if (businessId.isNotEmpty) 'businessId': businessId,
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
        businessId: map['businessId'] as String? ?? '',
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
    String? businessId,
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
        businessId: businessId ?? this.businessId,
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

/// A customer's contract relationship with a single business: the current
/// [active] term plus the [history] of superseded terms (newest-first) from
/// prior renewals. A customer tagged to several businesses holds one of these
/// per business, keyed by business id in [Customer.contractsByBusiness], so each
/// business's subscription, renewals and invoicing are tracked independently.
class BusinessContract {
  const BusinessContract({required this.active, this.history = const []});

  /// The current term — the most recent contract captured for this business.
  final ServiceContract active;

  /// Superseded terms, newest-first: each was replaced by a later renewal.
  final List<ServiceContract> history;

  /// How many terms have been recorded for this business (active + superseded).
  int get termCount => 1 + history.length;

  /// The result of renewing [active] with [renewal]: the current term is pushed
  /// to the front of [history] and [renewal] becomes the new active term.
  BusinessContract renewedWith(ServiceContract renewal) =>
      BusinessContract(active: renewal, history: [active, ...history]);

  Map<String, dynamic> toMap() => {
        'active': active.toMap(),
        if (history.isNotEmpty)
          'history': history.map((c) => c.toMap()).toList(),
      };

  factory BusinessContract.fromMap(Map<String, dynamic> map) =>
      BusinessContract(
        active: ServiceContract.fromMap(
            Map<String, dynamic>.from(map['active'] as Map)),
        history: [
          for (final c in (map['history'] as List<dynamic>? ?? const []))
            ServiceContract.fromMap(Map<String, dynamic>.from(c as Map)),
        ],
      );

  BusinessContract copyWith({
    ServiceContract? active,
    List<ServiceContract>? history,
  }) =>
      BusinessContract(
        active: active ?? this.active,
        history: history ?? this.history,
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
    this.contractsByBusiness = const {},
    this.contacts = const [],
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

  /// The customer's service contracts, keyed by business id. A customer tagged
  /// to several businesses can hold an independent contract (plus its own
  /// renewal history) for each. Empty until the deal is marked
  /// [DealStatus.successful] and a contract is captured for some business.
  ///
  /// Callers must scope to the business in view — see [activeContractFor] /
  /// [contractInScope] — so Admin/User (and the business filter) only ever see
  /// contracts for businesses they can access.
  final Map<String, BusinessContract> contractsByBusiness;

  /// The customer-side people (e.g. their CEO, Tech Lead, CSM). Embedded on the
  /// customer document, so they inherit the customer's read/write authorization.
  final List<Contact> contacts;

  final List<CustomerComment> comments;
  final AuditFields audit;

  /// True when a subscription contract has been recorded for any business.
  bool get hasServiceContract => contractsByBusiness.isNotEmpty;

  /// True when a contract exists for the given [businessId].
  bool hasContractFor(String businessId) =>
      contractsByBusiness.containsKey(businessId);

  /// The active (current) contract for [businessId], or null if none.
  ServiceContract? activeContractFor(String businessId) =>
      contractsByBusiness[businessId]?.active;

  /// The superseded terms for [businessId], newest-first (empty if none).
  List<ServiceContract> historyFor(String businessId) =>
      contractsByBusiness[businessId]?.history ?? const [];

  /// The active contract in scope for the selected business: the contract for
  /// [businessId], or null when [businessId] is null ("All Businesses" — the
  /// caller should render per-business instead) or no contract exists there.
  ServiceContract? contractInScope(String? businessId) =>
      businessId == null ? null : activeContractFor(businessId);

  /// Every active contract across all businesses (unordered).
  Iterable<ServiceContract> get allActiveContracts =>
      contractsByBusiness.values.map((c) => c.active);

  /// True when any business's contract has at least one superseded term.
  bool get hasContractHistory =>
      contractsByBusiness.values.any((c) => c.history.isNotEmpty);

  /// The total number of terms recorded across all businesses (active +
  /// superseded), i.e. how many times contracts have been established/renewed.
  int get contractTermCount =>
      contractsByBusiness.values.fold(0, (sum, c) => sum + c.termCount);

  /// Produces the customer that results from establishing or renewing the
  /// contract for [renewal]'s business ([ServiceContract.businessId]): if that
  /// business already has an active term it is pushed to the front of its
  /// history and [renewal] becomes its new active term; otherwise this is a
  /// first-time capture for that business. Contracts for other businesses are
  /// left untouched.
  Customer withRenewedContract(ServiceContract renewal) {
    final businessId = renewal.businessId;
    final existing = contractsByBusiness[businessId];
    final updated = existing == null
        ? BusinessContract(active: renewal)
        : existing.renewedWith(renewal);
    return copyWith(
      dealStatus: DealStatus.successful,
      contractsByBusiness: {...contractsByBusiness, businessId: updated},
    );
  }

  /// Produces the customer with the contract for [contract]'s business replaced
  /// in place (an edit, not a renewal — the history is preserved as-is). Used
  /// when correcting the current term rather than starting a new one.
  Customer withContract(ServiceContract contract) {
    final businessId = contract.businessId;
    final existing = contractsByBusiness[businessId];
    final updated = existing == null
        ? BusinessContract(active: contract)
        : existing.copyWith(active: contract);
    return copyWith(
      dealStatus: DealStatus.successful,
      contractsByBusiness: {...contractsByBusiness, businessId: updated},
    );
  }

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

  /// Reads the per-business contracts, tolerating the legacy single-contract
  /// shape (`serviceContract` + `contractHistory`) written before customers
  /// tracked contracts per business.
  ///
  /// The legacy pair is migrated under the business the contract was sold with
  /// ([ServiceContract.businessId]); if that is blank it falls back to the
  /// customer's first tagged business. A legacy contract that can be tied to no
  /// business at all is dropped rather than filed under an empty key.
  static Map<String, BusinessContract> _readContractsByBusiness(
      Map<String, dynamic> map) {
    final raw = map['contractsByBusiness'];
    if (raw is Map) {
      return {
        for (final e in raw.entries)
          e.key.toString():
              BusinessContract.fromMap(Map<String, dynamic>.from(e.value as Map)),
      };
    }

    // Legacy migration: a single embedded serviceContract (+ history).
    final legacyActive = map['serviceContract'];
    if (legacyActive is! Map) return const {};
    final active =
        ServiceContract.fromMap(Map<String, dynamic>.from(legacyActive));
    final history = [
      for (final c in (map['contractHistory'] as List<dynamic>? ?? const []))
        ServiceContract.fromMap(Map<String, dynamic>.from(c as Map)),
    ];

    var businessId = active.businessId;
    if (businessId.isEmpty) {
      final tagged = _readBusinessIds(map);
      if (tagged.isEmpty) return const {}; // untaggable — drop rather than orphan
      businessId = tagged.first;
    }
    return {businessId: BusinessContract(active: active, history: history)};
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
        if (contractsByBusiness.isNotEmpty)
          'contractsByBusiness': {
            for (final e in contractsByBusiness.entries)
              e.key: e.value.toMap(),
          },
        'contacts': contacts.map((c) => c.toMap()).toList(),
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
        contractsByBusiness: _readContractsByBusiness(map),
        contacts: Contact.listFrom(map['contacts']),
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
    Map<String, BusinessContract>? contractsByBusiness,
    List<Contact>? contacts,
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
        contractsByBusiness: contractsByBusiness ?? this.contractsByBusiness,
        contacts: contacts ?? this.contacts,
        comments: comments ?? this.comments,
        audit: audit ?? this.audit,
      );
}
