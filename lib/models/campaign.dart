import '../core/enums.dart';
import '../core/utils/money.dart';
import 'audit_fields.dart';

/// A marketing campaign for a product.
class Campaign {
  const Campaign({
    required this.id,
    required this.businessId,
    required this.productId,
    required this.name,
    this.platform = CampaignPlatform.other,
    this.type = '',
    this.startDate,
    this.endDate,
    this.budget = Money.zero,
    this.amountInvested = Money.zero,
    this.impressions = 0,
    this.clicks = 0,
    this.conversions = 0,
    this.status = CampaignStatus.draft,
    this.url = '',
    this.notes = '',
    this.audit = const AuditFields(),
  });

  final String id;
  final String businessId;
  final String productId;
  final String name;
  final CampaignPlatform platform;
  final String type;
  final DateTime? startDate;
  final DateTime? endDate;
  final Money budget;

  /// Actual marketing spend — this feeds profitability calculations.
  final Money amountInvested;

  final int impressions;
  final int clicks;
  final int conversions;
  final CampaignStatus status;
  final String url;
  final String notes;
  final AuditFields audit;

  /// The date used to attribute this campaign's spend to a reporting period.
  DateTime? get spendDate => startDate ?? audit.createdAt;

  /// Click-through rate as a percentage.
  double get ctr => impressions == 0 ? 0 : clicks / impressions * 100;

  /// Conversion rate as a percentage.
  double get conversionRate => clicks == 0 ? 0 : conversions / clicks * 100;

  Map<String, dynamic> toMap() => {
        'id': id,
        'businessId': businessId,
        'productId': productId,
        'name': name,
        'platform': platform.wire,
        'type': type,
        if (startDate != null) 'startDate': startDate!.toIso8601String(),
        if (endDate != null) 'endDate': endDate!.toIso8601String(),
        'budgetMinor': budget.minor,
        'amountInvestedMinor': amountInvested.minor,
        'impressions': impressions,
        'clicks': clicks,
        'conversions': conversions,
        'status': status.wire,
        'url': url,
        'notes': notes,
        ...audit.toMap(),
      };

  factory Campaign.fromMap(Map<String, dynamic> map) => Campaign(
        id: map['id'] as String? ?? '',
        businessId: map['businessId'] as String? ?? '',
        productId: map['productId'] as String? ?? '',
        name: map['name'] as String? ?? '',
        platform: CampaignPlatform.fromWire(map['platform'] as String?),
        type: map['type'] as String? ?? '',
        startDate: parseDate(map['startDate']),
        endDate: parseDate(map['endDate']),
        budget: Money((map['budgetMinor'] as num?)?.toInt() ?? 0),
        amountInvested:
            Money((map['amountInvestedMinor'] as num?)?.toInt() ?? 0),
        impressions: (map['impressions'] as num?)?.toInt() ?? 0,
        clicks: (map['clicks'] as num?)?.toInt() ?? 0,
        conversions: (map['conversions'] as num?)?.toInt() ?? 0,
        status: CampaignStatus.fromWire(map['status'] as String?),
        url: map['url'] as String? ?? '',
        notes: map['notes'] as String? ?? '',
        audit: AuditFields.fromMap(map),
      );

  Campaign copyWith({
    String? productId,
    String? name,
    CampaignPlatform? platform,
    String? type,
    DateTime? startDate,
    DateTime? endDate,
    Money? budget,
    Money? amountInvested,
    int? impressions,
    int? clicks,
    int? conversions,
    CampaignStatus? status,
    String? url,
    String? notes,
    AuditFields? audit,
  }) =>
      Campaign(
        id: id,
        businessId: businessId,
        productId: productId ?? this.productId,
        name: name ?? this.name,
        platform: platform ?? this.platform,
        type: type ?? this.type,
        startDate: startDate ?? this.startDate,
        endDate: endDate ?? this.endDate,
        budget: budget ?? this.budget,
        amountInvested: amountInvested ?? this.amountInvested,
        impressions: impressions ?? this.impressions,
        clicks: clicks ?? this.clicks,
        conversions: conversions ?? this.conversions,
        status: status ?? this.status,
        url: url ?? this.url,
        notes: notes ?? this.notes,
        audit: audit ?? this.audit,
      );
}
