import '../core/enums.dart';
import '../core/utils/money.dart';
import 'audit_fields.dart';

/// A dealer / vendor / supplier for a business. A dealer's recurring cost is
/// mirrored into Business Expenses (category = Dealer) via the service layer.
class Dealer {
  const Dealer({
    required this.id,
    required this.businessId,
    required this.name,
    this.url = '',
    this.description = '',
    this.cost = Money.zero,
    this.costFrequency = RecurrenceFrequency.monthly,
    this.startDate,
    this.endDate,
    this.status = EntityStatus.active,
    this.contactName = '',
    this.contactInfo = '',
    this.notes = '',
    this.audit = const AuditFields(),
  });

  final String id;
  final String businessId;
  final String name;
  final String url;
  final String description;
  final Money cost;
  final RecurrenceFrequency costFrequency;
  final DateTime? startDate;
  final DateTime? endDate;
  final EntityStatus status;
  final String contactName;
  final String contactInfo;
  final String notes;
  final AuditFields audit;

  bool get isActive => status == EntityStatus.active;

  Map<String, dynamic> toMap() => {
        'id': id,
        'businessId': businessId,
        'name': name,
        'url': url,
        'description': description,
        'costMinor': cost.minor,
        'costFrequency': costFrequency.wire,
        if (startDate != null) 'startDate': startDate!.toIso8601String(),
        if (endDate != null) 'endDate': endDate!.toIso8601String(),
        'status': status.wire,
        'contactName': contactName,
        'contactInfo': contactInfo,
        'notes': notes,
        ...audit.toMap(),
      };

  factory Dealer.fromMap(Map<String, dynamic> map) => Dealer(
        id: map['id'] as String? ?? '',
        businessId: map['businessId'] as String? ?? '',
        name: map['name'] as String? ?? '',
        url: map['url'] as String? ?? '',
        description: map['description'] as String? ?? '',
        cost: Money((map['costMinor'] as num?)?.toInt() ?? 0),
        costFrequency:
            RecurrenceFrequency.fromWire(map['costFrequency'] as String?),
        startDate: parseDate(map['startDate']),
        endDate: parseDate(map['endDate']),
        status: EntityStatus.fromWire(map['status'] as String?),
        contactName: map['contactName'] as String? ?? '',
        contactInfo: map['contactInfo'] as String? ?? '',
        notes: map['notes'] as String? ?? '',
        audit: AuditFields.fromMap(map),
      );

  Dealer copyWith({
    String? name,
    String? url,
    String? description,
    Money? cost,
    RecurrenceFrequency? costFrequency,
    DateTime? startDate,
    DateTime? endDate,
    EntityStatus? status,
    String? contactName,
    String? contactInfo,
    String? notes,
    AuditFields? audit,
  }) =>
      Dealer(
        id: id,
        businessId: businessId,
        name: name ?? this.name,
        url: url ?? this.url,
        description: description ?? this.description,
        cost: cost ?? this.cost,
        costFrequency: costFrequency ?? this.costFrequency,
        startDate: startDate ?? this.startDate,
        endDate: endDate ?? this.endDate,
        status: status ?? this.status,
        contactName: contactName ?? this.contactName,
        contactInfo: contactInfo ?? this.contactInfo,
        notes: notes ?? this.notes,
        audit: audit ?? this.audit,
      );
}
