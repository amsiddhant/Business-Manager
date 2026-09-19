import '../core/utils/date_utils.dart';

/// Common audit metadata attached to persisted entities.
class AuditFields {
  const AuditFields({
    this.createdAt,
    this.updatedAt,
    this.createdBy,
    this.updatedBy,
  });

  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? createdBy;
  final String? updatedBy;

  Map<String, dynamic> toMap() => {
        if (createdAt != null) 'createdAt': AppDate.iso(createdAt!),
        if (updatedAt != null) 'updatedAt': AppDate.iso(updatedAt!),
        if (createdBy != null) 'createdBy': createdBy,
        if (updatedBy != null) 'updatedBy': updatedBy,
      };

  factory AuditFields.fromMap(Map<String, dynamic> map) => AuditFields(
        createdAt: _parseDate(map['createdAt']),
        updatedAt: _parseDate(map['updatedAt']),
        createdBy: map['createdBy'] as String?,
        updatedBy: map['updatedBy'] as String?,
      );

  AuditFields copyWith({
    DateTime? createdAt,
    DateTime? updatedAt,
    String? createdBy,
    String? updatedBy,
  }) =>
      AuditFields(
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        createdBy: createdBy ?? this.createdBy,
        updatedBy: updatedBy ?? this.updatedBy,
      );
}

/// Tolerant date parser: accepts ISO strings, epoch millis, or DateTime.
DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is String) return DateTime.tryParse(value);
  // Firestore Timestamp exposes toDate().
  try {
    // ignore: avoid_dynamic_calls
    return value.toDate() as DateTime;
  } catch (_) {
    return null;
  }
}

/// Shared helper reused by model `fromMap` factories.
DateTime? parseDate(dynamic value) => _parseDate(value);
