import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'state/app_state.dart';
import 'state/data_controller.dart';
import 'state/filter_controller.dart';

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
  AuthStatus? _lastStatus;

  @override
  void initState() {
    super.initState();
    widget.appState.addListener(_onAppStateChanged);
    // Handle a session that was already primed during AppState.create().
    WidgetsBinding.instance.addPostFrameCallback((_) => _onAppStateChanged());
  }

  @override
  void dispose() {
    widget.appState.removeListener(_onAppStateChanged);
    super.dispose();
  }

  void _onAppStateChanged() {
    if (!mounted) return;
    final status = widget.appState.status;
    if (status == _lastStatus) return;
    _lastStatus = status;

    final data = context.read<DataController>();
    if (status == AuthStatus.signedIn) {
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
    return MaterialApp.router(
      title: 'Salesforce Business Manager',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: _router,
    );
  }
}
