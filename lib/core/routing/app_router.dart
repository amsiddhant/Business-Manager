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
import '../../screens/dashboard/dashboard_screen.dart';
import '../../screens/dealers/dealer_detail_screen.dart';
import '../../screens/dealers/dealers_screen.dart';
import '../../screens/expenses/expense_detail_screen.dart';
import '../../screens/expenses/expenses_screen.dart';
import '../../screens/orders/order_detail_screen.dart';
import '../../screens/orders/orders_screen.dart';
import '../../screens/products/product_detail_screen.dart';
import '../../screens/products/products_screen.dart';
import '../../screens/reports/reports_screen.dart';
import '../../screens/settings/settings_screen.dart';
import '../../screens/users/users_screen.dart';
import '../../state/app_state.dart';
import '../../widgets/layout/app_shell.dart';
import '../permissions.dart';
import 'app_routes.dart';

/// Builds the application router, wiring authentication redirects and the
/// persistent app shell around the authenticated routes.
///
/// [appState] is used as the router's [refreshListenable] so navigation
/// re-evaluates whenever the auth status changes.
GoRouter buildRouter(AppState appState) {
  return GoRouter(
    initialLocation: Routes.dashboard,
    refreshListenable: appState,
    redirect: (context, state) {
      final status = appState.status;
      final loc = state.matchedLocation;
      final isAuthRoute =
          loc == Routes.login || loc == Routes.forgotPassword;

      // While the backend is initialising, hold on the splash.
      if (status == AuthStatus.initializing) return null;

      final signedIn = status == AuthStatus.signedIn;
      if (!signedIn) {
        return isAuthRoute ? null : Routes.login;
      }
      // Signed in but sitting on an auth route → go to the dashboard.
      if (isAuthRoute) return Routes.dashboard;
      return null;
    },
    routes: [
      GoRoute(
        path: Routes.login,
        builder: (_, _) => const LoginScreen(),
      ),
      GoRoute(
        path: Routes.forgotPassword,
        builder: (_, _) => const ForgotPasswordScreen(),
      ),
      // Authenticated shell.
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(currentRoute: state.matchedLocation, child: child),
        routes: [
          GoRoute(
            path: Routes.dashboard,
            builder: (_, _) => const DashboardScreen(),
          ),
          GoRoute(
            path: Routes.businesses,
            builder: (_, _) => const BusinessesScreen(),
          ),
          GoRoute(
            path: Routes.businessDetail,
            builder: (_, state) =>
                BusinessDetailScreen(businessId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: Routes.products,
            builder: (_, _) => const ProductsScreen(),
          ),
          GoRoute(
            path: Routes.productDetail,
            builder: (_, state) =>
                ProductDetailScreen(productId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: Routes.campaigns,
            builder: (_, _) => const CampaignsScreen(),
          ),
          GoRoute(
            path: Routes.campaignDetail,
            builder: (_, state) =>
                CampaignDetailScreen(campaignId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: Routes.orders,
            builder: (_, _) => const OrdersScreen(),
          ),
          GoRoute(
            path: Routes.orderDetail,
            builder: (_, state) =>
                OrderDetailScreen(orderId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: Routes.expenses,
            builder: (_, _) => const ExpensesScreen(),
          ),
          GoRoute(
            path: Routes.expenseDetail,
            builder: (_, state) =>
                ExpenseDetailScreen(expenseId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: Routes.dealers,
            builder: (_, _) => const DealersScreen(),
          ),
          GoRoute(
            path: Routes.dealerDetail,
            builder: (_, state) =>
                DealerDetailScreen(dealerId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: Routes.customers,
            builder: (_, _) => const CustomersScreen(),
          ),
          GoRoute(
            path: Routes.customerDetail,
            builder: (_, state) =>
                CustomerDetailScreen(customerId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: Routes.reports,
            builder: (_, _) => const ReportsScreen(),
          ),
          GoRoute(
            path: Routes.users,
            builder: (_, _) => const UsersScreen(),
          ),
          GoRoute(
            path: Routes.settings,
            builder: (_, _) => const SettingsScreen(),
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => _RouteError(message: state.error?.message),
  );
}

/// Guards a route by permission, rendering an access-denied panel otherwise.
class PermissionGuard extends StatelessWidget {
  const PermissionGuard({
    super.key,
    required this.appState,
    required this.permission,
    required this.child,
    this.ownerOnly = false,
  });

  final AppState appState;
  final Permission permission;
  final Widget child;
  final bool ownerOnly;

  @override
  Widget build(BuildContext context) {
    final user = appState.currentUser;
    final allowed = user != null &&
        user.can(permission) &&
        (!ownerOnly || user.isOwner);
    if (allowed) return child;
    return const _AccessDenied();
  }
}

class _AccessDenied extends StatelessWidget {
  const _AccessDenied();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 48, color: Color(0xFF9CA3AF)),
            SizedBox(height: 16),
            Text('Access denied',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            SizedBox(height: 8),
            Text("You don't have permission to view this page.",
                style: TextStyle(color: Color(0xFF6B7280))),
          ],
        ),
      ),
    );
  }
}

class _RouteError extends StatelessWidget {
  const _RouteError({this.message});
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Color(0xFFDC2626)),
            const SizedBox(height: 16),
            const Text('Page not found',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(message ?? 'The requested page could not be found.',
                style: const TextStyle(color: Color(0xFF6B7280))),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => GoRouter.of(context).go(Routes.dashboard),
              child: const Text('Go to dashboard'),
            ),
          ],
        ),
      ),
    );
  }
}
