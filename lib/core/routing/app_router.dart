import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../screens/auth/forgot_password_screen.dart';
import '../../screens/auth/login_screen.dart';
import '../../screens/businesses/business_detail_screen.dart';
import '../../screens/businesses/businesses_screen.dart';
import '../../screens/campaigns/campaign_detail_screen.dart';
import '../../screens/campaigns/campaigns_screen.dart';
import '../../screens/customers/customer_detail_screen.dart';
import '../../screens/customers/customers_screen.dart';
import '../../screens/alerts/alerts_screen.dart';
import '../../screens/dashboard/dashboard_screen.dart';
import '../../screens/dealers/dealer_detail_screen.dart';
import '../../screens/dealers/dealers_screen.dart';
import '../../screens/expenses/expense_detail_screen.dart';
import '../../screens/expenses/expenses_screen.dart';
import '../../screens/orders/order_detail_screen.dart';
import '../../screens/orders/orders_screen.dart';
import '../../screens/products/product_detail_screen.dart';
import '../../screens/products/products_screen.dart';
// Rarely-opened, heavy screens load on first visit (smaller main.dart.js).
import '../../screens/reports/reports_screen.dart' deferred as reports;
import '../../screens/settings/settings_screen.dart' deferred as settings;
import '../../screens/users/users_screen.dart' deferred as users;
import '../../screens/whats_new/whats_new_screen.dart';
import '../../state/app_state.dart';
import '../../widgets/common/state_views.dart';
import '../../widgets/layout/app_shell.dart';
import '../theme/app_theme.dart';
import '../theme/theme_x.dart';
import 'app_routes.dart';

/// Builds the application router, wiring authentication redirects and the
/// persistent app shell around the authenticated routes.
///
/// [appState] is used as the router's [refreshListenable] so navigation
/// re-evaluates whenever the auth status changes.
///
/// Each section is its own shell branch with its own navigator, so switching
/// sections and coming back keeps the list's scroll, search and sort.
GoRouter buildRouter(AppState appState) {
  Widget guard(GoRouterState state, Widget child) => PermissionGuard(
        appState: appState,
        location: state.matchedLocation,
        child: child,
      );

  /// A section branch: its list page and (optionally) its `:id` detail page.
  StatefulShellBranch section(
    String path,
    Widget Function(GoRouterState state) list, {
    Widget Function(String id)? detail,
  }) {
    return StatefulShellBranch(
      routes: [
        GoRoute(
          path: path,
          builder: (_, state) => guard(state, list(state)),
          routes: [
            if (detail != null)
              GoRoute(
                path: ':id',
                builder: (_, state) =>
                    guard(state, detail(state.pathParameters['id']!)),
              ),
          ],
        ),
      ],
    );
  }

  return GoRouter(
    initialLocation: Routes.dashboard,
    refreshListenable: appState,
    redirect: (context, state) {
      final status = appState.status;
      final loc = state.matchedLocation;
      final isAuthRoute = loc == Routes.login || loc == Routes.forgotPassword;

      // While the backend is initialising, hold on the splash.
      if (status == AuthStatus.initializing) return null;

      final signedIn = status == AuthStatus.signedIn;
      if (!signedIn) {
        return isAuthRoute ? null : Routes.login;
      }
      // Signed in but sitting on an auth route (or the bare root) → dashboard.
      if (isAuthRoute || loc == '/') return Routes.dashboard;
      return null;
    },
    routes: [
      GoRoute(path: Routes.login, builder: (_, _) => const LoginScreen()),
      GoRoute(
        path: Routes.forgotPassword,
        builder: (_, _) => const ForgotPasswordScreen(),
      ),
      // Authenticated shell. Branches must follow [kShellBranches].
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => AppShell(
          navigationShell: navigationShell,
          location: state.uri.toString(),
        ),
        branches: [
          section(Routes.dashboard, (_) => const DashboardScreen()),
          section(Routes.alerts, (_) => const AlertsScreen()),
          section(
            Routes.businesses,
            (_) => const BusinessesScreen(),
            detail: (id) => BusinessDetailScreen(businessId: id),
          ),
          section(
            Routes.products,
            (_) => const ProductsScreen(),
            detail: (id) => ProductDetailScreen(productId: id),
          ),
          section(
            Routes.campaigns,
            (_) => const CampaignsScreen(),
            detail: (id) => CampaignDetailScreen(campaignId: id),
          ),
          section(
            Routes.orders,
            (_) => const OrdersScreen(),
            detail: (id) => OrderDetailScreen(orderId: id),
          ),
          section(
            Routes.expenses,
            (_) => const ExpensesScreen(),
            detail: (id) => ExpenseDetailScreen(expenseId: id),
          ),
          section(
            Routes.dealers,
            (_) => const DealersScreen(),
            detail: (id) => DealerDetailScreen(dealerId: id),
          ),
          section(
            Routes.customers,
            (_) => const CustomersScreen(),
            detail: (id) => CustomerDetailScreen(customerId: id),
          ),
          section(
            Routes.reports,
            (state) => DeferredPage(
              loader: reports.loadLibrary,
              builder: () => reports.ReportsScreen(
                  initialTab: state.uri.queryParameters['tab']),
            ),
          ),
          section(
            Routes.users,
            (_) => DeferredPage(
              loader: users.loadLibrary,
              builder: () => users.UsersScreen(),
            ),
          ),
          section(
            Routes.settings,
            (_) => DeferredPage(
              loader: settings.loadLibrary,
              builder: () => settings.SettingsScreen(),
            ),
          ),
          section(Routes.whatsNew, (_) => const WhatsNewScreen()),
        ],
      ),
    ],
    errorBuilder: (context, state) =>
        _RouteError(message: state.error?.message),
  );
}

/// Shows [builder]'s page once its deferred library ([loader]) has loaded.
class DeferredPage extends StatefulWidget {
  const DeferredPage({super.key, required this.loader, required this.builder});

  final Future<void> Function() loader;
  final Widget Function() builder;

  @override
  State<DeferredPage> createState() => _DeferredPageState();
}

class _DeferredPageState extends State<DeferredPage> {
  late Future<void> _load = widget.loader();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _load,
      builder: (context, snap) {
        if (snap.hasError) {
          return ErrorView(
            message: "This page couldn't be loaded. Check your connection "
                'and try again.',
            onRetry: () => setState(() => _load = widget.loader()),
          );
        }
        if (snap.connectionState != ConnectionState.done) {
          return const LoadingView();
        }
        return widget.builder();
      },
    );
  }
}

/// Guards a shell route by the rule in [Routes.accessFor], rendering an
/// access-denied panel otherwise. Typing a URL (or following an old link) to a
/// section the user can't see lands here instead of on the page.
class PermissionGuard extends StatelessWidget {
  const PermissionGuard({
    super.key,
    required this.appState,
    required this.location,
    required this.child,
  });

  final AppState appState;
  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) => Routes.canOpen(appState.currentUser, location)
          ? child
          : const _AccessDenied(),
    );
  }
}

class _AccessDenied extends StatelessWidget {
  const _AccessDenied();

  @override
  Widget build(BuildContext context) {
    return _Notice(
      icon: Icons.lock_outline,
      color: context.tokens.warning,
      surface: context.tokens.warningSurface,
      title: 'You don’t have access to this page',
      message: 'Ask the owner to grant you access, or head back to the '
          'dashboard.',
    );
  }
}

class _RouteError extends StatelessWidget {
  const _RouteError({this.message});
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _Notice(
        icon: Icons.explore_off_outlined,
        color: context.tokens.error,
        surface: context.tokens.errorSurface,
        title: 'Page not found',
        message: message ?? 'The page you asked for doesn’t exist.',
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.color,
    required this.surface,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final Color surface;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration:
                    BoxDecoration(color: surface, shape: BoxShape.circle),
                child: Icon(icon, size: 30, color: color),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: context.tokens.textSecondary, height: 1.4),
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: () => GoRouter.of(context).go(Routes.dashboard),
                icon: const Icon(Icons.dashboard_outlined, size: 18),
                label: const Text('Go to dashboard'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
