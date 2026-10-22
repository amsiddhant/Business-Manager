import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_exception.dart';
import 'backend.dart';
import 'backend_capabilities.dart';
import 'demo_seed.dart';

/// A browser-persisted backend (via SharedPreferences) used as the default so
/// the application runs standalone with demo data and no external setup.
///
/// This is *not* a security boundary — it exists so the product is immediately
/// demonstrable. Real deployments switch to [FirebaseBackend] via the Owner's
/// in-app setup wizard, where Firestore security rules enforce authorization.
///
/// The store is saved shortly after the last change (see [flush]), so a burst
/// of writes such as a CSV import serialises it once rather than per row.
class LocalBackend
    implements
        Backend,
        BatchCapable,
        CounterCapable,
        FieldUpdateCapable,
        QueryCapable {
  LocalBackend(this._prefs);

  static const Duration _persistDelay = Duration(milliseconds: 250);
  Timer? _persistTimer;

  final SharedPreferences _prefs;

  static const _storeKey = 'sbm_local_store_v1';
  static const _credsKey = 'sbm_local_creds_v1';
  static const _sessionKey = 'sbm_local_session_v1';

  // collection -> (docId -> data)
  final Map<String, Map<String, Map<String, dynamic>>> _store = {};
  // email -> password (demo only)
  final Map<String, String> _creds = {};

  final _authController = StreamController<AuthAccount?>.broadcast();
  AuthAccount? _current;

  @override
  String get label => 'Local (Demo)';

  /// Loads persisted state, seeding demo data on first run.
  Future<void> initialize() async {
    final rawStore = _prefs.getString(_storeKey);
    if (rawStore == null) {
      _seed();
    } else {
      _loadStore(rawStore);
      final rawCreds = _prefs.getString(_credsKey);
      if (rawCreds != null) {
        final decoded = jsonDecode(rawCreds) as Map<String, dynamic>;
        _creds
          ..clear()
          ..addAll(decoded.map((k, v) => MapEntry(k, v as String)));
      }
    }

    // Restore any previous session.
    final session = _prefs.getString(_sessionKey);
    if (session != null) {
      final decoded = jsonDecode(session) as Map<String, dynamic>;
      _current = AuthAccount(
        uid: decoded['uid'] as String,
        email: decoded['email'] as String,
      );
    }
  }

  void _seed() {
    final seed = DemoSeed(DateTime.now());
    final built = seed.buildStore();
    _store
      ..clear()
      ..addAll(built);
    _creds
      ..clear()
      ..addAll({
        DemoSeed.ownerEmail: DemoSeed.password,
        DemoSeed.adminEmail: DemoSeed.password,
        DemoSeed.userEmail: DemoSeed.password,
      });
    _persist();
    _persistCreds();
  }

  void _loadStore(String raw) {
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    _store.clear();
    decoded.forEach((collection, docs) {
      final coll = <String, Map<String, dynamic>>{};
      (docs as Map<String, dynamic>).forEach((id, data) {
        coll[id] = Map<String, dynamic>.from(data as Map);
      });
      _store[collection] = coll;
    });
  }

  void _persist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(_persistDelay, flush);
  }

  /// Saves any pending changes now (e.g. when the tab is being hidden).
  void flush() {
    final pending = _persistTimer;
    if (pending == null) return;
    pending.cancel();
    _persistTimer = null;
    _prefs.setString(_storeKey, jsonEncode(_store));
  }

  void _persistCreds() => _prefs.setString(_credsKey, jsonEncode(_creds));

  /// Clears everything and re-seeds. Used by "Reset demo data".
  Future<void> resetToSeed() async {
    _seed();
    flush();
  }

  // ---- Auth -----------------------------------------------------------------

  @override
  Stream<AuthAccount?> authStateChanges() async* {
    yield _current;
    yield* _authController.stream;
  }

  @override
  AuthAccount? get currentAccount => _current;

  @override
  Future<AuthAccount> signIn(String email, String password) async {
    await _fakeLatency();
    final normalized = email.trim().toLowerCase();
    final stored = _creds[normalized];
    if (stored == null || stored != password) {
      throw const AppException('Incorrect email or password.',
          code: 'invalid-credential');
    }
    final userDoc = _findUserByEmail(normalized);
    if (userDoc == null) {
      throw const AppException('No profile found for this account.',
          code: 'user-not-found');
    }
    final account =
        AuthAccount(uid: userDoc['uid'] as String, email: normalized);
    _current = account;
    _prefs.setString(_sessionKey, jsonEncode({'uid': account.uid, 'email': normalized}));
    _authController.add(account);
    return account;
  }

  Map<String, dynamic>? _findUserByEmail(String email) {
    final users = _store[Collections.users];
    if (users == null) return null;
    for (final doc in users.values) {
      if ((doc['email'] as String?)?.toLowerCase() == email) return doc;
    }
    return null;
  }

  @override
  Future<AuthAccount> signInWithGoogle() async {
    // The demo backend has no real Google provider; sign in as the demo Owner
    // so "Continue with Google" still works out-of-the-box in demo mode.
    return signIn(DemoSeed.ownerEmail, DemoSeed.password);
  }

  @override
  Future<void> signOut() async {
    _current = null;
    _prefs.remove(_sessionKey);
    _authController.add(null);
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    await _fakeLatency();
    // Local backend cannot send email; treat as success if the account exists.
    final normalized = email.trim().toLowerCase();
    if (!_creds.containsKey(normalized)) {
      // Do not reveal whether the account exists.
      return;
    }
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await _fakeLatency();
    final account = _current;
    if (account == null) {
      throw const AppException('You must be signed in.', code: 'unauthenticated');
    }
    if (_creds[account.email] != currentPassword) {
      throw const AppException('Your current password is incorrect.',
          code: 'wrong-password');
    }
    _creds[account.email] = newPassword;
    _persistCreds();
  }

  @override
  Future<String> createAccount(String email, String password) async {
    await _fakeLatency();
    final normalized = email.trim().toLowerCase();
    if (_creds.containsKey(normalized)) {
      throw const AppException('An account with that email already exists.',
          code: 'email-already-in-use');
    }
    _creds[normalized] = password;
    _persistCreds();
    // Deterministic-ish uid for the local backend.
    return 'local-${normalized.hashCode.toUnsigned(32)}';
  }

  // ---- Data -----------------------------------------------------------------

  @override
  Future<List<Map<String, dynamic>>> fetchCollection(String collection,
      {String? businessId}) async {
    final coll = _store[collection];
    if (coll == null) return [];
    final all = coll.values.map((e) => Map<String, dynamic>.from(e)).toList();
    if (businessId == null) return all;
    return all.where((doc) => doc['businessId'] == businessId).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> fetchWhereArrayContains(
      String collection, String field, String value) async {
    final coll = _store[collection];
    if (coll == null) return [];
    return coll.values
        .map((e) => Map<String, dynamic>.from(e))
        .where((doc) {
          final raw = doc[field];
          return raw is List && raw.contains(value);
        })
        .toList();
  }

  @override
  Future<Map<String, dynamic>?> fetchDoc(String collection, String id) async {
    final doc = _store[collection]?[id];
    return doc == null ? null : Map<String, dynamic>.from(doc);
  }

  @override
  Future<void> setDoc(
      String collection, String id, Map<String, dynamic> data) async {
    final coll = _store.putIfAbsent(collection, () => {});
    coll[id] = Map<String, dynamic>.from(data);
    _persist();
  }

  @override
  Future<void> deleteDoc(String collection, String id) async {
    _store[collection]?.remove(id);
    _persist();
  }

  @override
  Future<void> updateFields(
      String collection, String id, Map<String, dynamic> fields) async {
    final doc = _store[collection]?[id];
    if (doc == null) throw const NotFoundException();
    doc.addAll(fields);
    _persist();
  }

  @override
  Future<void> commit(List<WriteOp> ops) async {
    for (final op in ops) {
      switch (op) {
        case SetOp(:final collection, :final id, :final data):
          _store.putIfAbsent(collection, () => {})[id] =
              Map<String, dynamic>.from(data);
        case DeleteOp(:final collection, :final id):
          _store[collection]?.remove(id);
      }
    }
    _persist();
  }

  @override
  Future<int?> reserveNumbers(String prefix, int count,
      {int floor = 0, bool create = false}) async {
    final counters = _store.putIfAbsent(Collections.counters, () => {});
    final stored = (counters[prefix]?['value'] as num?)?.toInt();
    if (stored == null && !create) return null;
    final base = max(stored ?? 0, floor);
    counters[prefix] = {'value': base + count};
    _persist();
    return base + 1;
  }

  @override
  Future<void> ensureAtLeast(String prefix, int value) async {
    final counters = _store.putIfAbsent(Collections.counters, () => {});
    final stored = (counters[prefix]?['value'] as num?)?.toInt();
    if (stored != null && stored >= value) return;
    counters[prefix] = {'value': value};
    _persist();
  }

  @override
  Future<List<Map<String, dynamic>>> fetchLatest(String collection,
      {required String orderBy, required int limit}) async {
    final all = await fetchCollection(collection);
    String key(Map<String, dynamic> d) => d[orderBy]?.toString() ?? '';
    all.sort((a, b) => key(b).compareTo(key(a)));
    return all.take(limit).toList();
  }

  Future<void> _fakeLatency() =>
      Future<void>.delayed(const Duration(milliseconds: 120));
}
