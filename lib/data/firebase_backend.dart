import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_exception.dart';
import '../models/firebase_config.dart';
import 'backend.dart';
import 'backend_capabilities.dart';

/// Real Firebase Auth + Cloud Firestore backend.
///
/// Activated at runtime once the Owner completes the setup wizard. Uses the
/// suggested Firestore layout: top-level collections keyed by document id, with
/// business-scoped documents carrying a `businessId` field so queries can be
/// filtered and security rules can enforce per-business access.
///
/// Firestore keeps an on-device cache (IndexedDB) so the app can paint from
/// it instantly on the next visit; set `--dart-define=BM_FS_CACHE=false` to
/// fall back to the in-memory cache.
class FirebaseBackend
    implements
        Backend,
        BatchCapable,
        CounterCapable,
        FieldUpdateCapable,
        QueryCapable,
        CacheCapable,
        PublicLookupCapable,
        UsageMeter {
  FirebaseBackend._(this._app, this._auth, this._firestore, this._prefs);

  final FirebaseApp _app;
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final SharedPreferences _prefs;

  static const bool _persistentCache =
      bool.fromEnvironment('BM_FS_CACHE', defaultValue: true);
  static const int _cacheSizeBytes = 40 * 1024 * 1024;
  static const String _cachedUidKey = 'sbm_cache_uid';

  // Set (via a zone) while [fromCache] runs, so concurrent reads elsewhere in
  // the app still go to the server.
  static final Object _cacheOnlyKey = Object();

  int _reads = 0;
  int _writes = 0;

  @override
  String get label => 'Firebase';

  @override
  int get readCount => _reads;

  @override
  int get writeCount => _writes;

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
    if (_persistentCache) {
      // Applied when Firestore is first used; ignored if it already was.
      try {
        firestore.settings = const Settings(
          persistenceEnabled: true,
          cacheSizeBytes: _cacheSizeBytes,
          webPersistentTabManager: WebPersistentMultipleTabManager(),
        );
      } catch (_) {
        // Keep the default in-memory cache.
      }
    }
    final prefs = await SharedPreferences.getInstance();
    return FirebaseBackend._(app, auth, firestore, prefs);
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

  bool get _cacheOnly => Zone.current[_cacheOnlyKey] == true;

  GetOptions? get _getOptions =>
      _cacheOnly ? const GetOptions(source: Source.cache) : null;

  List<Map<String, dynamic>> _docs(QuerySnapshot<Map<String, dynamic>> snap) {
    // A server query is billed one read per document, and at least one.
    if (!snap.metadata.isFromCache) _reads += max(1, snap.docs.length);
    return snap.docs.map((d) => {...d.data(), 'id': d.id}).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> fetchCollection(String collection,
      {String? businessId}) async {
    try {
      Query<Map<String, dynamic>> query = _col(collection);
      if (businessId != null) {
        query = query.where('businessId', isEqualTo: businessId);
      }
      return _docs(await query.get(_getOptions));
    } on FirebaseException catch (e) {
      throw AppException(ErrorMapper.friendly(e), code: e.code);
    }
  }

  @override
  Future<List<Map<String, dynamic>>> fetchWhereArrayContains(
      String collection, String field, String value) async {
    try {
      return _docs(await _col(collection)
          .where(field, arrayContains: value)
          .get(_getOptions));
    } on FirebaseException catch (e) {
      throw AppException(ErrorMapper.friendly(e), code: e.code);
    }
  }

  @override
  Future<List<Map<String, dynamic>>> fetchLatest(String collection,
      {required String orderBy, required int limit}) async {
    try {
      return _docs(await _col(collection)
          .orderBy(orderBy, descending: true)
          .limit(limit)
          .get(_getOptions));
    } on FirebaseException catch (e) {
      throw AppException(ErrorMapper.friendly(e), code: e.code);
    }
  }

  @override
  Future<Map<String, dynamic>?> fetchDoc(String collection, String id) async {
    try {
      final snap = await _col(collection).doc(id).get(_getOptions);
      if (!snap.metadata.isFromCache) _reads++;
      if (!snap.exists) return null;
      return {...snap.data()!, 'id': snap.id};
    } on FirebaseException catch (e) {
      throw AppException(ErrorMapper.friendly(e), code: e.code);
    }
  }

  @override
  Future<Map<String, dynamic>?> fetchPublicDoc(String collection, String id) =>
      fetchDoc(collection, id);

  @override
  Future<void> setDoc(
      String collection, String id, Map<String, dynamic> data) async {
    try {
      await _col(collection).doc(id).set(data);
      _writes++;
    } on FirebaseException catch (e) {
      throw AppException(ErrorMapper.friendly(e), code: e.code);
    }
  }

  @override
  Future<void> deleteDoc(String collection, String id) async {
    try {
      await _col(collection).doc(id).delete();
      _writes++;
    } on FirebaseException catch (e) {
      throw AppException(ErrorMapper.friendly(e), code: e.code);
    }
  }

  @override
  Future<void> updateFields(
      String collection, String id, Map<String, dynamic> fields) async {
    try {
      await _col(collection).doc(id).update(fields);
      _writes++;
    } on FirebaseException catch (e) {
      throw AppException(ErrorMapper.friendly(e), code: e.code);
    }
  }

  @override
  Future<void> commit(List<WriteOp> ops) async {
    if (ops.isEmpty) return;
    final batch = _firestore.batch();
    for (final op in ops) {
      final ref = _col(op.collection).doc(op.id);
      switch (op) {
        case SetOp(:final data):
          batch.set(ref, data);
        case DeleteOp():
          batch.delete(ref);
      }
    }
    try {
      await batch.commit();
      _writes += ops.length;
    } on FirebaseException catch (e) {
      throw AppException(ErrorMapper.friendly(e), code: e.code);
    }
  }

  @override
  Future<int?> reserveNumbers(String prefix, int count,
      {int floor = 0, bool create = false}) async {
    final ref = _col(Collections.counters).doc(prefix);
    try {
      final first = await _firestore.runTransaction<int?>((tx) async {
        final snap = await tx.get(ref);
        _reads++;
        final stored =
            snap.exists ? (snap.data()?['value'] as num?)?.toInt() ?? 0 : null;
        if (stored == null && !create) return null;
        final base = max(stored ?? 0, floor);
        tx.set(ref, {'value': base + count});
        return base + 1;
      });
      if (first != null) _writes++;
      return first;
    } on FirebaseException catch (e) {
      throw AppException(ErrorMapper.friendly(e), code: e.code);
    }
  }

  @override
  Future<void> ensureAtLeast(String prefix, int value) async {
    final ref = _col(Collections.counters).doc(prefix);
    try {
      final wrote = await _firestore.runTransaction<bool>((tx) async {
        final snap = await tx.get(ref);
        _reads++;
        final stored =
            snap.exists ? (snap.data()?['value'] as num?)?.toInt() : null;
        if (stored != null && stored >= value) return false;
        tx.set(ref, {'value': value});
        return true;
      });
      if (wrote) _writes++;
    } on FirebaseException catch (e) {
      throw AppException(ErrorMapper.friendly(e), code: e.code);
    }
  }

  // ---- On-device cache -------------------------------------------------------

  @override
  Future<T> fromCache<T>(Future<T> Function() body) =>
      runZoned(body, zoneValues: {_cacheOnlyKey: true});

  @override
  String? get cachedUid =>
      _persistentCache ? _prefs.getString(_cachedUidKey) : null;

  @override
  Future<void> setCachedUid(String? uid) async {
    if (uid == null) {
      await _prefs.remove(_cachedUidKey);
    } else {
      await _prefs.setString(_cachedUidKey, uid);
    }
  }

  @override
  Future<void> clearCache() async {
    await setCachedUid(null);
    if (!_persistentCache) return;
    try {
      await _firestore.terminate();
      await _firestore.clearPersistence();
    } catch (_) {
      // Another tab still has the cache open; the uid guard above still stops
      // the next person from seeing it.
    }
  }
}
