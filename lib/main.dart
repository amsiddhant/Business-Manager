import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'core/routing/app_router.dart';
import 'core/theme/app_motion.dart';
import 'data/local_backend.dart';
import 'state/alert_controller.dart';
import 'state/app_state.dart';
import 'state/data_controller.dart';
import 'state/filter_controller.dart';
import 'state/theme_controller.dart';
import 'state/user_prefs.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final appState = await AppState.create();
  runApp(SalesforceBusinessManagerApp(appState: appState));
}

/// Root of the application. Wires the global providers, the theme and the
/// go_router configuration (with its authentication redirect).
class SalesforceBusinessManagerApp extends StatelessWidget {
  const SalesforceBusinessManagerApp({super.key, required this.appState});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: appState),
        ChangeNotifierProvider<DataController>(
          create: (_) => DataController(appState.repository),
        ),
        ChangeNotifierProvider<FilterController>(
          create: (_) => FilterController(),
        ),
        ChangeNotifierProvider<UserPrefs>(
          create: (_) =>
              UserPrefs(appState.prefs)..bindUser(appState.currentUser?.uid),
        ),
        ChangeNotifierProvider<ThemeController>(
          create: (c) => ThemeController(appState.prefs, c.read<UserPrefs>()),
        ),
        ChangeNotifierProvider<AlertController>(
          create: (c) => AlertController(c.read<UserPrefs>()),
        ),
      ],
      child: _AppView(appState: appState),
    );
  }
}

/// Bridges auth state to the working data set: loads everything the signed-in
/// user can access on sign-in, and clears it on sign-out. Owns the single
/// router instance so its [refreshListenable] is wired exactly once.
class _AppView extends StatefulWidget {
  const _AppView({required this.appState});

  final AppState appState;

  @override
  State<_AppView> createState() => _AppViewState();
}

class _AppViewState extends State<_AppView> {
  late final GoRouter _router = buildRouter(widget.appState);
  late final AppLifecycleListener _lifecycle;
  AuthStatus? _lastStatus;

  @override
  void initState() {
    super.initState();
    widget.appState.addListener(_onAppStateChanged);
    context.read<FilterController>().addListener(_saveScope);
    context.read<DataController>().addListener(_checkScope);
    // Handle a session that was already primed during AppState.create().
    WidgetsBinding.instance.addPostFrameCallback((_) => _onAppStateChanged());
    _lifecycle = AppLifecycleListener(
      // Back on the tab after a while: pick up other people's changes.
      onResume: () {
        if (widget.appState.status == AuthStatus.signedIn) {
          context.read<DataController>().softSyncIfStale();
        }
      },
      // The tab may be closed next: save any pending demo-data changes.
      onHide: _flushLocal,
      onPause: _flushLocal,
    );
  }

  void _flushLocal() {
    final backend = widget.appState.backend;
    if (backend is LocalBackend) backend.flush();
  }

  /// Remembers the business + period selection for this user.
  void _saveScope() {
    if (widget.appState.status != AuthStatus.signedIn) return;
    context
        .read<UserPrefs>()
        .setScope(context.read<FilterController>().toJson());
  }

  /// A remembered business the user can no longer see falls back to "All".
  void _checkScope() {
    final data = context.read<DataController>();
    final filter = context.read<FilterController>();
    final id = filter.selectedBusinessId;
    if (!data.loaded || id == null) return;
    if (!data.selectableBusinesses.any((b) => b.id == id)) {
      filter.selectBusiness(null);
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    widget.appState.removeListener(_onAppStateChanged);
    super.dispose();
  }

  void _onAppStateChanged() {
    if (!mounted) return;
    context.read<UserPrefs>().bindUser(widget.appState.currentUser?.uid);
    final status = widget.appState.status;
    if (status == _lastStatus) return;
    _lastStatus = status;

    final data = context.read<DataController>();
    if (status == AuthStatus.signedIn) {
      context.read<FilterController>().restore(context.read<UserPrefs>().scope);
      // The repository may have been rebound (e.g. Firebase activation); point
      // the data controller at the current repository before loading.
      data.rebind(widget.appState.repository);
      data.load();
    } else if (status == AuthStatus.signedOut) {
      data.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>();
    final title = context.select<AppState, String>((s) => s.appName);
    return MaterialApp.router(
      title: title.isEmpty ? 'Business Manager' : title,
      debugShowCheckedModeBanner: false,
      theme: theme.light,
      darkTheme: theme.dark,
      themeMode: theme.mode,
      themeAnimationDuration: AppMotion(theme.motion).slow,
      themeAnimationCurve: AppMotion.standard,
      routerConfig: _router,
    );
  }
}
