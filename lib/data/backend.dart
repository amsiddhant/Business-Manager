/// Backend abstraction decoupling the app from any specific persistence engine.
///
/// Two implementations exist:
///  * [LocalBackend] — browser-persisted (SharedPreferences) store used by
///    default so the app runs standalone with demo data.
///  * [FirebaseBackend] — real Firebase Auth + Cloud Firestore, activated once
///    the Owner completes the in-app Firebase setup wizard.
///
/// Repositories and services depend only on this interface, never on Firebase
/// types directly, which keeps business logic out of the persistence details.
library;

/// Identifies a signed-in principal.
class AuthAccount {
  const AuthAccount({
    required this.uid,
    required this.email,
    this.displayName = '',
  });
  final String uid;
  final String email;

  /// Human name from the identity provider (e.g. Google), when available.
  /// Used to pre-fill a profile on first sign-in.
  final String displayName;
}

/// Auth capabilities required by the app.
abstract class AuthBackend {
  /// Emits the current account (or null when signed out) and on every change.
  Stream<AuthAccount?> authStateChanges();

  AuthAccount? get currentAccount;

  Future<AuthAccount> signIn(String email, String password);

  /// Signs in with the Google identity provider (web popup). Throws
  /// [UnsupportedError]-equivalent [AppException] on backends without it.
  Future<AuthAccount> signInWithGoogle();

  Future<void> signOut();

  Future<void> sendPasswordReset(String email);

  /// Changes the currently signed-in user's password. [currentPassword] is used
  /// to reauthenticate where the backend requires it.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  });

  /// Creates an auth account without disturbing the current session, returning
  /// the new uid. Used by Owner user-management.
  Future<String> createAccount(String email, String password);
}

/// Simple document/collection data capabilities. Collections are flat and
/// top-level; documents scoped to a business carry a `businessId` field.
abstract class DataBackend {
  /// Reads all documents in [collection], optionally filtered to a single
  /// [businessId].
  Future<List<Map<String, dynamic>>> fetchCollection(
    String collection, {
    String? businessId,
  });

  Future<Map<String, dynamic>?> fetchDoc(String collection, String id);

  Future<void> setDoc(
      String collection, String id, Map<String, dynamic> data);

  Future<void> deleteDoc(String collection, String id);
}

/// Convenience aggregate used throughout the app.
abstract class Backend implements AuthBackend, DataBackend {
  /// A short human name for diagnostics ("Local", "Firebase").
  String get label;
}

/// Well-known collection names.
class Collections {
  Collections._();
  static const users = 'users';
  static const businesses = 'businesses';
  static const products = 'products';
  static const campaigns = 'campaigns';
  static const orders = 'orders';
  static const expenses = 'expenses';
  static const dealers = 'dealers';
  static const customers = 'customers';
  static const auditLogs = 'auditLogs';

  /// Pending access requests raised when a signed-in identity (e.g. Google)
  /// has no `users/{uid}` profile yet. Keyed by the auth uid so the Owner can
  /// provision a profile against the *existing* account.
  static const accessRequests = 'accessRequests';

  /// Application metadata (e.g. the `meta/system` bootstrap sentinel that marks
  /// the first Owner as having claimed the project).
  static const meta = 'meta';
}
