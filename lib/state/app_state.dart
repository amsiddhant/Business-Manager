import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_html/html.dart' as html;

import '../core/app_exception.dart';
import '../core/app_info.dart';
import '../core/utils/date_utils.dart';
import '../data/backend.dart';
import '../data/backend_capabilities.dart';
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

  /// This browser's shared_preferences (used by `UserPrefs` and the theme).
  SharedPreferences get prefs => _prefs;

  ConfigStore get configStore => _configStore;
  Backend get backend => _backend;
  bool get isFirebaseMode => _configStore.isFirebaseMode;
  String get appName => _configStore.appName;
  String get dateFormat => _configStore.dateFormat;

  static const _seenReleaseKey = 'sbm_last_seen_release';

  /// True when this browser hasn't been told about the current version yet
  /// (after an upgrade, or the first time the app is opened here).
  bool get hasUnseenRelease => _prefs.getString(_seenReleaseKey) != kAppVersion;

  Future<void> markReleaseSeen() =>
      _prefs.setString(_seenReleaseKey, kAppVersion);

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

  Future<void>? _profileLoad;
  String? _profileLoadUid;

  /// Handles an auth event. The same account is often reported twice in a row
  /// (the start-up prime and the stream's first event), so its profile is read
  /// once: a repeat while that read runs, or once signed in, is ignored.
  Future<void> _onAuthChanged(AuthAccount? account) {
    if (account == null) {
      _profileLoad = null;
      _profileLoadUid = null;
      _currentUser = null;
      repository.setCurrentUser(null);
      _status = AuthStatus.signedOut;
      notifyListeners();
      return Future.value();
    }
    if (_status == AuthStatus.signedIn && _currentUser?.uid == account.uid) {
      return Future.value();
    }
    final running = _profileLoad;
    if (running != null && _profileLoadUid == account.uid) return running;
    late final Future<void> load;
    load = _loadProfile(account).whenComplete(() {
      if (identical(_profileLoad, load)) {
        _profileLoad = null;
        _profileLoadUid = null;
      }
    });
    _profileLoad = load;
    _profileLoadUid = account.uid;
    return load;
  }

  Future<void> _loadProfile(AuthAccount account) async {
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
          await _signOutBackend();
          return;
        }
      }
      if (!profile.isActive) {
        _authError = 'This account has been disabled.';
        await _signOutBackend();
        return;
      }
      // Signed out (or switched account) while the profile was loading.
      if (_backend.currentAccount?.uid != account.uid) return;
      _currentUser = profile;
      repository.setCurrentUser(profile);
      _status = AuthStatus.signedIn;
      _authError = null;
      notifyListeners();
      // Covers every way in (password, Google, a restored session); at most
      // one write per person per day.
      unawaited(repository.touchLastLogin(profile));
    } catch (e) {
      _authError = ErrorMapper.friendly(e);
      _status = AuthStatus.signedOut;
      notifyListeners();
    }
  }

  // ---- Auth actions ---------------------------------------------------------

  /// Signs in with a friendly login id OR email plus password. An email signs
  /// in directly; a login id is first looked up in the sign-in index (one
  /// document read, allowed before sign-in) to find its email.
  Future<void> signIn(String loginOrEmail, String password) async {
    _authError = null;
    final email = await repository.emailForLogin(loginOrEmail);
    if (email == null) {
      throw const AppException(
          'Incorrect login ID or password. You can also sign in with your '
          'email address.',
          code: 'invalid-credential');
    }
    await _backend.signIn(email, password);
    // _onAuthChanged (via the stream) finalises the session.
  }

  /// Signs in with Google (Firebase popup). The auth-state stream finalises the
  /// session via [_onAuthChanged], including first-Owner bootstrap.
  Future<void> signInWithGoogle() async {
    _authError = null;
    await _backend.signInWithGoogle();
  }

  /// Signs out. With Firebase, the on-device copy of the data is wiped too so
  /// the next person on this device can't read it, and the page reloads (the
  /// wiped Firestore instance can't be used again).
  Future<void> signOut() async {
    final backend = _backend;
    await _runSignOutHooks();
    await backend.signOut();
    if (backend case final CacheCapable cache) {
      await cache.clearCache();
      if (kIsWeb) html.window.location.reload();
    }
  }

  final List<Future<void> Function()> _signOutHooks = [];

  /// How long all sign-out hooks together may take before sign-out goes on.
  static const signOutHookTimeout = Duration(seconds: 4);

  /// Runs [hook] before every sign-out (e.g. to stop a worker and wipe what
  /// it kept on this device).
  void addSignOutHook(Future<void> Function() hook) => _signOutHooks.add(hook);

  void removeSignOutHook(Future<void> Function() hook) =>
      _signOutHooks.remove(hook);

  /// Runs the hooks, each guarded, bounded as a whole; never throws.
  Future<void> _runSignOutHooks() async {
    if (_signOutHooks.isEmpty) return;
    Future<void> guarded(Future<void> Function() hook) async {
      try {
        await hook();
      } catch (_) {}
    }

    try {
      await Future.wait([for (final h in [..._signOutHooks]) guarded(h)])
          .timeout(signOutHookTimeout);
    } catch (_) {}
  }

  Future<void> _signOutBackend() async {
    await _runSignOutHooks();
    await _backend.signOut();
  }

  /// Sends a reset link for a login id or email. Says nothing about whether
  /// the account exists: an unknown login id or email simply sends nothing.
  Future<void> sendPasswordReset(String loginOrEmail) async {
    final email = await repository.emailForLogin(loginOrEmail);
    if (email == null) return;
    try {
      await _backend.sendPasswordReset(email);
    } on AppException catch (e) {
      if (e.code != 'user-not-found') rethrow;
    }
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
    _profileLoad = null;
    _profileLoadUid = null;
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
      await _signOutBackend();
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
