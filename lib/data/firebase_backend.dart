import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../core/app_exception.dart';
import '../models/firebase_config.dart';
import 'backend.dart';

/// Real Firebase Auth + Cloud Firestore backend.
///
/// Activated at runtime once the Owner completes the setup wizard. Uses the
/// suggested Firestore layout: top-level collections keyed by document id, with
/// business-scoped documents carrying a `businessId` field so queries can be
/// filtered and security rules can enforce per-business access.
class FirebaseBackend implements Backend {
  FirebaseBackend._(this._app, this._auth, this._firestore);

  final FirebaseApp _app;
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  @override
  String get label => 'Firebase';

  /// Initialises a secondary Firebase app from the wizard [config] and returns
  /// a ready backend. Using a named app avoids clashing with any default app
  /// and lets us (re)initialise from runtime configuration.
  static Future<FirebaseBackend> initialize(FirebaseConfig config) async {
    const appName = 'sbm-runtime';
    final options = FirebaseOptions(
      apiKey: config.apiKey,
      authDomain: config.authDomain,
      projectId: config.projectId,
      storageBucket: config.storageBucket,
      messagingSenderId: config.messagingSenderId,
      appId: config.appId,
      measurementId: config.measurementId.isEmpty ? null : config.measurementId,
      databaseURL: config.databaseURL.isEmpty ? null : config.databaseURL,
    );

    FirebaseApp app;
    try {
      app = Firebase.app(appName);
      // Already initialised with (presumably) the same options.
    } catch (_) {
      app = await Firebase.initializeApp(name: appName, options: options);
    }

    final auth = FirebaseAuth.instanceFor(app: app);
    final firestore = FirebaseFirestore.instanceFor(app: app);
    return FirebaseBackend._(app, auth, firestore);
  }

  /// Lightweight connectivity check used by the wizard's "Test Connection".
  Future<void> testConnection() async {
    try {
      // A metadata-only read against a well-known doc path. Permission errors
      // still prove connectivity (project reachable, config valid).
      await _firestore
          .collection('__connection_test__')
          .doc('ping')
          .get(const GetOptions(source: Source.server));
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') return; // reachable, just protected
      rethrow;
    }
  }

  CollectionReference<Map<String, dynamic>> _col(String name) =>
      _firestore.collection(name);

  // ---- Auth -----------------------------------------------------------------

  @override
  Stream<AuthAccount?> authStateChanges() =>
      _auth.authStateChanges().map(_toAccount);

  AuthAccount? _toAccount(User? user) => user == null
      ? null
      : AuthAccount(
          uid: user.uid,
          email: user.email ?? '',
          displayName: user.displayName ?? '',
        );

  @override
  AuthAccount? get currentAccount => _toAccount(_auth.currentUser);

  @override
  Future<AuthAccount> signIn(String email, String password) async {
    try {
      final cred = await _auth.signInWithEmailAndPassword(
          email: email.trim(), password: password);
      return _toAccount(cred.user)!;
    } on FirebaseAuthException catch (e) {
      throw AppException(ErrorMapper.friendly(e), code: e.code);
    }
  }

  @override
  Future<AuthAccount> signInWithGoogle() async {
    try {
      final provider = GoogleAuthProvider()
        ..setCustomParameters({'prompt': 'select_account'});
      // Web: a popup is the simplest, most reliable Google sign-in flow.
      final cred = await _auth.signInWithPopup(provider);
      return _toAccount(cred.user)!;
    } on FirebaseAuthException catch (e) {
      throw AppException(ErrorMapper.friendly(e), code: e.code);
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      throw AppException(ErrorMapper.friendly(e), code: e.code);
    }
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) {
      throw const AppException('You must be signed in.',
          code: 'unauthenticated');
    }
    try {
      final cred = EmailAuthProvider.credential(
          email: user.email!, password: currentPassword);
      await user.reauthenticateWithCredential(cred);
      await user.updatePassword(newPassword);
    } on FirebaseAuthException catch (e) {
      throw AppException(ErrorMapper.friendly(e), code: e.code);
    }
  }

  @override
  Future<String> createAccount(String email, String password) async {
    // Create the account on a throwaway secondary app instance so the current
    // Owner session is not replaced by the newly created user.
    const tempName = 'sbm-user-provisioning';
    FirebaseApp tempApp;
    try {
      tempApp = Firebase.app(tempName);
    } catch (_) {
      tempApp = await Firebase.initializeApp(
          name: tempName, options: _app.options);
    }
    final tempAuth = FirebaseAuth.instanceFor(app: tempApp);
    try {
      final cred = await tempAuth.createUserWithEmailAndPassword(
          email: email.trim(), password: password);
      final uid = cred.user!.uid;
      await tempAuth.signOut();
      return uid;
    } on FirebaseAuthException catch (e) {
      throw AppException(ErrorMapper.friendly(e), code: e.code);
    }
  }

  // ---- Data -----------------------------------------------------------------

  @override
  Future<List<Map<String, dynamic>>> fetchCollection(String collection,
      {String? businessId}) async {
    try {
      Query<Map<String, dynamic>> query = _col(collection);
      if (businessId != null) {
        query = query.where('businessId', isEqualTo: businessId);
      }
      final snap = await query.get();
      return snap.docs.map((d) => {...d.data(), 'id': d.id}).toList();
    } on FirebaseException catch (e) {
      throw AppException(ErrorMapper.friendly(e), code: e.code);
    }
  }

  @override
  Future<List<Map<String, dynamic>>> fetchWhereArrayContains(
      String collection, String field, String value) async {
    try {
      final snap =
          await _col(collection).where(field, arrayContains: value).get();
      return snap.docs.map((d) => {...d.data(), 'id': d.id}).toList();
    } on FirebaseException catch (e) {
      throw AppException(ErrorMapper.friendly(e), code: e.code);
    }
  }

  @override
  Future<Map<String, dynamic>?> fetchDoc(String collection, String id) async {
    try {
      final snap = await _col(collection).doc(id).get();
      if (!snap.exists) return null;
      return {...snap.data()!, 'id': snap.id};
    } on FirebaseException catch (e) {
      throw AppException(ErrorMapper.friendly(e), code: e.code);
    }
  }

  @override
  Future<void> setDoc(
      String collection, String id, Map<String, dynamic> data) async {
    try {
      await _col(collection).doc(id).set(data);
    } on FirebaseException catch (e) {
      throw AppException(ErrorMapper.friendly(e), code: e.code);
    }
  }

  @override
  Future<void> deleteDoc(String collection, String id) async {
    try {
      await _col(collection).doc(id).delete();
    } on FirebaseException catch (e) {
      throw AppException(ErrorMapper.friendly(e), code: e.code);
    }
  }
}
