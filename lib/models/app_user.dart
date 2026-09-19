import '../core/enums.dart';
import '../core/permissions.dart';
import 'audit_fields.dart';

/// An application user profile. This is stored in `users/{uid}` and mapped to a
/// Firebase Auth account via [uid]. The [loginId] is the friendly username/ID
/// that the user types at login and is resolved to an email internally.
class AppUser {
  const AppUser({
    required this.uid,
    required this.loginId,
    required this.name,
    required this.email,
    required this.role,
    this.status = AccountStatus.active,
    this.assignedBusinessIds = const [],
    this.grantedPermissions = const {},
    this.revokedPermissions = const {},
    this.lastLoginAt,
    this.audit = const AuditFields(),
  });

  final String uid;
  final String loginId;
  final String name;
  final String email;
  final UserRole role;
  final AccountStatus status;

  /// Businesses this user may access. Ignored for OWNER (who sees everything).
  final List<String> assignedBusinessIds;

  /// Per-user permission overrides layered on top of the role defaults.
  final Set<Permission> grantedPermissions;
  final Set<Permission> revokedPermissions;

  final DateTime? lastLoginAt;
  final AuditFields audit;

  bool get isOwner => role == UserRole.owner;
  bool get isActive => status == AccountStatus.active;

  /// The effective permission set for this user.
  Set<Permission> get permissions => Permissions.resolve(
        role,
        granted: grantedPermissions,
        revoked: revokedPermissions,
      );

  bool can(Permission permission) =>
      isActive && permissions.contains(permission);

  /// Whether this user may access [businessId]. Owner → always; others → only
  /// if the business is in their assignment list.
  bool canAccessBusiness(String businessId) {
    if (isOwner) return true;
    return assignedBusinessIds.contains(businessId);
  }

  Map<String, dynamic> toMap() => {
        'uid': uid,
        'loginId': loginId,
        'name': name,
        'email': email,
        'role': role.wire,
        'status': status.wire,
        'assignedBusinessIds': assignedBusinessIds,
        'grantedPermissions':
            grantedPermissions.map((p) => p.name).toList(),
        'revokedPermissions':
            revokedPermissions.map((p) => p.name).toList(),
        if (lastLoginAt != null) 'lastLoginAt': lastLoginAt!.toIso8601String(),
        ...audit.toMap(),
      };

  factory AppUser.fromMap(Map<String, dynamic> map) => AppUser(
        uid: map['uid'] as String? ?? '',
        loginId: map['loginId'] as String? ?? '',
        name: map['name'] as String? ?? '',
        email: map['email'] as String? ?? '',
        role: UserRole.fromWire(map['role'] as String?),
        status: AccountStatus.fromWire(map['status'] as String?),
        assignedBusinessIds:
            (map['assignedBusinessIds'] as List?)?.cast<String>() ?? const [],
        grantedPermissions: _parsePermissions(map['grantedPermissions']),
        revokedPermissions: _parsePermissions(map['revokedPermissions']),
        lastLoginAt: parseDate(map['lastLoginAt']),
        audit: AuditFields.fromMap(map),
      );

  static Set<Permission> _parsePermissions(dynamic value) {
    if (value is! List) return {};
    final names = value.cast<String>().toSet();
    return Permission.values.where((p) => names.contains(p.name)).toSet();
  }

  AppUser copyWith({
    String? loginId,
    String? name,
    String? email,
    UserRole? role,
    AccountStatus? status,
    List<String>? assignedBusinessIds,
    Set<Permission>? grantedPermissions,
    Set<Permission>? revokedPermissions,
    DateTime? lastLoginAt,
    AuditFields? audit,
  }) =>
      AppUser(
        uid: uid,
        loginId: loginId ?? this.loginId,
        name: name ?? this.name,
        email: email ?? this.email,
        role: role ?? this.role,
        status: status ?? this.status,
        assignedBusinessIds: assignedBusinessIds ?? this.assignedBusinessIds,
        grantedPermissions: grantedPermissions ?? this.grantedPermissions,
        revokedPermissions: revokedPermissions ?? this.revokedPermissions,
        lastLoginAt: lastLoginAt ?? this.lastLoginAt,
        audit: audit ?? this.audit,
      );
}
