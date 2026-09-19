import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_exception.dart';
import '../core/utils/date_utils.dart';
import '../data/backend.dart';
import '../data/config_store.dart';
import '../data/firebase_backend.dart';
import '../data/local_backend.dart';
import '../data/repository.dart';
import '../models/app_user.dart';
import '../models/firebase_config.dart';

/// Authentication lifecycle status.
enum AuthStatus { initializing, signedOut, signedIn }

/// Root application controller: owns the active backend, repository, the
/// signed-in user profile, and drives auth state. Screens obtain data through
/// [repository] and observe [status]/[currentUser] here.
class AppState extends ChangeNotifier {
  AppState._(this._prefs, this._configStore, this._backend)
      : repository = Repository(backend: _backend);

  final SharedPreferences _prefs;
  final ConfigStore _configStore;
  Backend _backend;

  final Repository repository;

  AuthStatus _status = AuthStatus.initializing;
  AuthStatus get status => _status;

  AppUser? _currentUser;
  AppUser? get currentUser => _currentUser;

  String? _authError;
  String? get authError => _authError;

  StreamSubscription<AuthAccount?>? _authSub;

  ConfigStore get configStore => _configStore;
  Backend get backend => _backend;
  bool get isFirebaseMode => _configStore.isFirebaseMode;
  String get appName => _configStore.appName;
  String get dateFormat => _configStore.dateFormat;

  /// Persists a new application display name and notifies observers so the
  /// header/title update live.
  Future<void> setAppName(String name) async {
    await _configStore.setAppName(name.trim());
    notifyListeners();
  }

  /// Persists the preferred date display format, applies it globally and
  /// notifies observers.
  Future<void> setDateFormat(String format) async {
    final trimmed = format.trim();
    await _configStore.setDateFormat(trimmed);
    AppDate.configureDisplayFormat(trimmed);
    notifyListeners();
  }

  /// Builds and initialises the AppState, choosing the Firebase backend if the
  /// Owner has previously configured it, otherwise the local demo backend.
  static Future<AppState> create() async {
    final prefs = await SharedPreferences.getInstance();
    final configStore = ConfigStore(prefs);

    Backend backend;
    if (configStore.isFirebaseMode && configStore.firebaseConfig != null) {
      try {
        backend = await FirebaseBackend.initialize(configStore.firebaseConfig!);
      } catch (_) {
        // Fall back to local demo if Firebase initialisation fails.
        final local = LocalBackend(prefs);
        await local.initialize();
        await configStore.setFirebaseMode(false);
        backend = local;
      }
    } else {
      final local = LocalBackend(prefs);
      await local.initialize();
      backend = local;
    }

    // Apply the persisted long-date display preference globally.
    AppDate.configureDisplayFormat(configStore.dateFormat);

    final state = AppState._(prefs, configStore, backend);
    await state._start();
    return state;
  }

  Future<void> _start() async {
    _authSub = _backend.authStateChanges().listen(_onAuthChanged);
    // Prime with the current account synchronously if available.
    await _onAuthChanged(_backend.currentAccount);
  }

  Future<void> _onAuthChanged(AuthAccount? account) async {
    if (account == null) {
      _currentUser = null;
      repository.setCurrentUser(null);
      _status = AuthStatus.signedOut;
      notifyListeners();
      return;
    }
    try {
      var profile = await repository.fetchUserByUid(account.uid);
      if (profile == null) {
        // No profile yet. On a brand-new project the first user to sign in
        // claims it as the Owner; otherwise access must be granted by the
        // existing Owner, so we sign out with an explanatory message.
        profile = await repository.bootstrapFirstOwnerIfNeeded(account);
        if (profile == null) {
          // Record a pending access request *before* signing out, while the
          // requester is still authenticated (the rules only permit them to
          // write their own request). The Owner approves it later, which
          // provisions a profile against this existing account.
          await repository.recordAccessRequest(account);
          _authError =
              'Your account is awaiting approval. An owner has been notified — '
              "you'll be able to sign in once access is granted.";
          await _backend.signOut();
          return;
        }
      }
      if (!profile.isActive) {
        _authError = 'This account has been disabled.';
        await _backend.signOut();
        return;
      }
      _currentUser = profile;
      repository.setCurrentUser(profile);
      _status = AuthStatus.signedIn;
      _authError = null;
      notifyListeners();
    } catch (e) {
      _authError = ErrorMapper.friendly(e);
      _status = AuthStatus.signedOut;
      notifyListeners();
    }
  }

  // ---- Auth actions ---------------------------------------------------------

  /// Signs in with a friendly login id OR email plus password. The login id is
  /// resolved to the underlying email first.
  Future<void> signIn(String loginOrEmail, String password) async {
    _authError = null;
    final profile = await repository.resolveUserByLogin(loginOrEmail);
    final email = profile?.email ?? loginOrEmail;
    final account = await _backend.signIn(email, password);
    await repository.touchLastLogin(account.uid);
    // _onAuthChanged (via the stream) finalises the session.
  }

  /// Signs in with Google (Firebase popup). The auth-state stream finalises the
  /// session via [_onAuthChanged], including first-Owner bootstrap.
  Future<void> signInWithGoogle() async {
    _authError = null;
    await _backend.signInWithGoogle();
  }

  Future<void> signOut() async {
    await _backend.signOut();
  }

  Future<void> sendPasswordReset(String loginOrEmail) async {
    final profile = await repository.resolveUserByLogin(loginOrEmail);
    final email = profile?.email ?? loginOrEmail;
    await _backend.sendPasswordReset(email);
  }

  Future<void> changePassword(
      String currentPassword, String newPassword) async {
    await _backend.changePassword(
        currentPassword: currentPassword, newPassword: newPassword);
  }

  /// Reloads the current user's profile (e.g. after self-edits).
  Future<void> refreshCurrentUser() async {
    final uid = _currentUser?.uid;
    if (uid == null) return;
    final profile = await repository.fetchUserByUid(uid);
    if (profile != null) {
      _currentUser = profile;
      repository.setCurrentUser(profile);
      notifyListeners();
    }
  }

  // ---- Firebase configuration -----------------------------------------------

  /// Validates a Firebase config by initialising a backend and pinging it.
  /// Does not switch the app over — used by the wizard's "Test Connection".
  Future<void> testFirebaseConfig(FirebaseConfig config) async {
    final backend = await FirebaseBackend.initialize(config);
    await backend.testConnection();
  }

  /// Persists the Firebase config, switches the active backend to Firebase and
  /// signs the current session out so the user re-authenticates against it.
  Future<void> activateFirebase(FirebaseConfig config) async {
    final backend = await FirebaseBackend.initialize(config);
    await _configStore.saveFirebaseConfig(config);
    await _configStore.setFirebaseMode(true);
    await _swapBackend(backend);
  }

  /// Reverts to the local demo backend.
  Future<void> deactivateFirebase() async {
    await _configStore.clearFirebaseConfig();
    final local = LocalBackend(_prefs);
    await local.initialize();
    await _swapBackend(local);
  }

  Future<void> _swapBackend(Backend backend) async {
    await _authSub?.cancel();
    _backend = backend;
    repository.rebind(backend: backend, currentUser: null);
    _currentUser = null;
    _status = AuthStatus.signedOut;
    _authSub = _backend.authStateChanges().listen(_onAuthChanged);
    await _onAuthChanged(_backend.currentAccount);
    notifyListeners();
  }

  /// Resets the local demo data (local backend only).
  Future<void> resetDemoData() async {
    final backend = _backend;
    if (backend is LocalBackend) {
      await backend.resetToSeed();
      await backend.signOut();
    } else {
      throw const AppException('Demo reset is only available in demo mode.');
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }
}
