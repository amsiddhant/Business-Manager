import 'audit_fields.dart';

/// A pending request for application access.
///
/// Raised automatically when a signed-in identity (typically Google Sign-In)
/// authenticates successfully but has no `users/{uid}` profile yet and the
/// project has already been claimed by an Owner. The request is keyed by the
/// Firebase Auth [uid] so the Owner can provision a profile against the
/// *existing* account — avoiding the "email already in use" collision that
/// happens when trying to create a brand-new auth account for the same email.
class AccessRequest {
  const AccessRequest({
    required this.uid,
    required this.email,
    this.displayName = '',
    this.requestedAt,
  });

  final String uid;
  final String email;

  /// Human name from the identity provider, when available.
  final String displayName;
  final DateTime? requestedAt;

  Map<String, dynamic> toMap() => {
        'uid': uid,
        'email': email,
        'displayName': displayName,
        if (requestedAt != null) 'requestedAt': requestedAt!.toIso8601String(),
      };

  factory AccessRequest.fromMap(Map<String, dynamic> map) => AccessRequest(
        uid: map['uid'] as String? ?? '',
        email: map['email'] as String? ?? '',
        displayName: map['displayName'] as String? ?? '',
        requestedAt: parseDate(map['requestedAt']),
      );
}
