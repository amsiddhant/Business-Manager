import '../core/enums.dart';
import 'audit_fields.dart';

/// An entry in the audit trail (`auditLogs/{logId}`).
class AuditLog {
  const AuditLog({
    required this.id,
    required this.userId,
    required this.userName,
    required this.action,
    required this.entityType,
    required this.entityId,
    this.businessId,
    this.timestamp,
    this.summary = '',
  });

  final String id;
  final String userId;
  final String userName;
  final AuditAction action;
  final String entityType;
  final String entityId;
  final String? businessId;
  final DateTime? timestamp;
  final String summary;

  Map<String, dynamic> toMap() => {
        'id': id,
        'userId': userId,
        'userName': userName,
        'action': action.wire,
        'entityType': entityType,
        'entityId': entityId,
        if (businessId != null) 'businessId': businessId,
        if (timestamp != null) 'timestamp': timestamp!.toIso8601String(),
        'summary': summary,
      };

  factory AuditLog.fromMap(Map<String, dynamic> map) => AuditLog(
        id: map['id'] as String? ?? '',
        userId: map['userId'] as String? ?? '',
        userName: map['userName'] as String? ?? '',
        action: AuditAction.fromWire(map['action'] as String?),
        entityType: map['entityType'] as String? ?? '',
        entityId: map['entityId'] as String? ?? '',
        businessId: map['businessId'] as String?,
        timestamp: parseDate(map['timestamp']),
        summary: map['summary'] as String? ?? '',
      );
}
