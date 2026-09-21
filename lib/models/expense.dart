import '../core/enums.dart';
import '../core/utils/money.dart';
import 'audit_fields.dart';
import 'entity_comment.dart';

/// A business operating expense. May be one-time or recurring; recurring
/// expenses are prorated to reporting periods by the profit engine.
class Expense {
  const Expense({
    required this.id,
    required this.businessId,
    required this.name,
    this.category = ExpenseCategory.other,
    this.description = '',
    this.amount = Money.zero,
    this.frequency = RecurrenceFrequency.oneTime,
    this.startDate,
    this.endDate,
    this.vendor = '',
    this.status = EntityStatus.active,
    this.notes = '',
    this.sourceDealerId,
    this.comments = const [],
    this.audit = const AuditFields(),
  });

  final String id;
  final String businessId;
  final String name;
  final ExpenseCategory category;
  final String description;

  /// The amount per occurrence (per month, per year, etc. depending on
  /// [frequency]); for one-time expenses this is the full amount.
  final Money amount;

  final RecurrenceFrequency frequency;
  final DateTime? startDate;
  final DateTime? endDate;
  final String vendor;
  final EntityStatus status;
  final String notes;

  /// If this expense is auto-generated from a dealer, the dealer id. Such
  /// expenses are managed via the dealer, not edited directly.
  final String? sourceDealerId;

  /// Discussion thread embedded on the expense document.
  final List<EntityComment> comments;

  final AuditFields audit;

  bool get isActive => status == EntityStatus.active;
  bool get isFromDealer => sourceDealerId != null;

  /// Annualised cost = amount × occurrences-per-year (one-time returns the
  /// full amount, treated as incurred once).
  Money get annualisedAmount {
    if (frequency == RecurrenceFrequency.oneTime) return amount;
    return amount * frequency.occurrencesPerYear;
  }

  /// Newest signal of activity: latest comment, else the updated/created audit
  /// timestamp. Powers detail views' "Last Activity" card.
  DateTime? get lastActivityAt {
    DateTime? newest;
    for (final c in comments) {
      final d = c.createdAt;
      if (d != null && (newest == null || d.isAfter(newest))) newest = d;
    }
    return newest ?? audit.updatedAt ?? audit.createdAt;
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'businessId': businessId,
        'name': name,
        'category': category.wire,
        'description': description,
        'amountMinor': amount.minor,
        'frequency': frequency.wire,
        if (startDate != null) 'startDate': startDate!.toIso8601String(),
        if (endDate != null) 'endDate': endDate!.toIso8601String(),
        'vendor': vendor,
        'status': status.wire,
        'notes': notes,
        if (sourceDealerId != null) 'sourceDealerId': sourceDealerId,
        'comments': comments.map((c) => c.toMap()).toList(),
        ...audit.toMap(),
      };

  factory Expense.fromMap(Map<String, dynamic> map) => Expense(
        id: map['id'] as String? ?? '',
        businessId: map['businessId'] as String? ?? '',
        name: map['name'] as String? ?? '',
        category: ExpenseCategory.fromWire(map['category'] as String?),
        description: map['description'] as String? ?? '',
        amount: Money((map['amountMinor'] as num?)?.toInt() ?? 0),
        frequency: RecurrenceFrequency.fromWire(map['frequency'] as String?),
        startDate: parseDate(map['startDate']),
        endDate: parseDate(map['endDate']),
        vendor: map['vendor'] as String? ?? '',
        status: EntityStatus.fromWire(map['status'] as String?),
        notes: map['notes'] as String? ?? '',
        sourceDealerId: map['sourceDealerId'] as String?,
        comments: EntityComment.listFrom(map['comments']),
        audit: AuditFields.fromMap(map),
      );

  Expense copyWith({
    String? id,
    String? name,
    ExpenseCategory? category,
    String? description,
    Money? amount,
    RecurrenceFrequency? frequency,
    DateTime? startDate,
    DateTime? endDate,
    String? vendor,
    EntityStatus? status,
    String? notes,
    String? sourceDealerId,
    List<EntityComment>? comments,
    AuditFields? audit,
  }) =>
      Expense(
        id: id ?? this.id,
        businessId: businessId,
        name: name ?? this.name,
        category: category ?? this.category,
        description: description ?? this.description,
        amount: amount ?? this.amount,
        frequency: frequency ?? this.frequency,
        startDate: startDate ?? this.startDate,
        endDate: endDate ?? this.endDate,
        vendor: vendor ?? this.vendor,
        status: status ?? this.status,
        notes: notes ?? this.notes,
        sourceDealerId: sourceDealerId ?? this.sourceDealerId,
        comments: comments ?? this.comments,
        audit: audit ?? this.audit,
      );
}
