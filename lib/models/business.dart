import '../core/enums.dart';
import 'audit_fields.dart';

/// A business/organisation. Top-level owner of products, campaigns, orders,
/// expenses and dealers.
class Business {
  const Business({
    required this.id,
    required this.name,
    this.description = '',
    this.type = '',
    this.website = '',
    this.currency = CurrencyCode.inr,
    this.country = 'India',
    this.status = EntityStatus.active,
    this.audit = const AuditFields(),
  });

  final String id;
  final String name;
  final String description;
  final String type;
  final String website;
  final CurrencyCode currency;
  final String country;
  final EntityStatus status;
  final AuditFields audit;

  bool get isActive => status == EntityStatus.active;

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'description': description,
        'type': type,
        'website': website,
        'currency': currency.wire,
        'country': country,
        'status': status.wire,
        ...audit.toMap(),
      };

  factory Business.fromMap(Map<String, dynamic> map) => Business(
        id: map['id'] as String? ?? '',
        name: map['name'] as String? ?? '',
        description: map['description'] as String? ?? '',
        type: map['type'] as String? ?? '',
        website: map['website'] as String? ?? '',
        currency: CurrencyCode.fromWire(map['currency'] as String?),
        country: map['country'] as String? ?? '',
        status: EntityStatus.fromWire(map['status'] as String?),
        audit: AuditFields.fromMap(map),
      );

  Business copyWith({
    String? name,
    String? description,
    String? type,
    String? website,
    CurrencyCode? currency,
    String? country,
    EntityStatus? status,
    AuditFields? audit,
  }) =>
      Business(
        id: id,
        name: name ?? this.name,
        description: description ?? this.description,
        type: type ?? this.type,
        website: website ?? this.website,
        currency: currency ?? this.currency,
        country: country ?? this.country,
        status: status ?? this.status,
        audit: audit ?? this.audit,
      );
}
