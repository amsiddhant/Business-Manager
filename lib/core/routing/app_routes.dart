import 'package:flutter/material.dart';

import '../../models/app_user.dart';
import '../permissions.dart';

/// Canonical route paths used across the app.
class Routes {
  Routes._();
  static const login = '/login';
  static const forgotPassword = '/forgot-password';
  static const dashboard = '/dashboard';
  static const alerts = '/alerts';
  static const businesses = '/businesses';
  static const businessDetail = '/businesses/:id';
  static const products = '/products';
  static const productDetail = '/products/:id';
  static const campaigns = '/campaigns';
  static const campaignDetail = '/campaigns/:id';
  static const orders = '/orders';
  static const orderDetail = '/orders/:id';
  static const expenses = '/expenses';
  static const expenseDetail = '/expenses/:id';
  static const dealers = '/dealers';
  static const dealerDetail = '/dealers/:id';
  static const customers = '/customers';
  static const customerDetail = '/customers/:id';
  static const reports = '/reports';
  static const users = '/users';
  static const settings = '/settings';
  static const whatsNew = '/whats-new';

  static String businessDetailPath(String id) => '/businesses/$id';
  static String productDetailPath(String id) => '/products/$id';
  static String campaignDetailPath(String id) => '/campaigns/$id';
  static String orderDetailPath(String id) => '/orders/$id';
  static String expenseDetailPath(String id) => '/expenses/$id';
  static String dealerDetailPath(String id) => '/dealers/$id';
  static String customerDetailPath(String id) => '/customers/$id';

  /// A Reports tab: `sales`, `expenses`, `marketing`, `products` or
  /// `business`.
  static String reportsTab(String tab) => '$reports?tab=$tab';

  /// The top-level section a location belongs to:
  /// `/customers/CUST-00001?tab=2` → `/customers`. Null for `/`.
  static String? sectionOf(String location) {
    final path = Uri.tryParse(location)?.path ?? location;
    final first = path.split('/').firstWhere((s) => s.isNotEmpty,
        orElse: () => '');
    return first.isEmpty ? null : '/$first';
  }

  /// The navigation entry whose access rule guards [location]. Detail pages
  /// inherit their list's rule (`/orders/ORD-000001` needs `viewOrder`).
  ///
  /// Null means any signed-in user may open it. Settings is one of these: its
  /// Profile and Password sections are for everyone, and the screen hides the
  /// sections a user can't manage.
  static NavDestination? accessFor(String location) {
    final section = sectionOf(location);
    if (section == null || section == settings) return null;
    for (final d in kNavDestinations) {
      if (d.route == section) return d;
    }
    return null;
  }

  /// Whether [user] may open [location].
  static bool canOpen(AppUser? user, String location) {
    if (user == null) return false;
    final access = accessFor(location);
    if (access == null) return true;
    return user.can(access.permission) && (!access.ownerOnly || user.isOwner);
  }
}

/// A primary navigation destination shown in the sidebar / drawer.
class NavDestination {
  const NavDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.route,
    required this.permission,
    this.ownerOnly = false,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String route;

  /// Permission required to see this destination.
  final Permission permission;

  /// When true, only the Owner sees it (e.g. Users, Settings).
  final bool ownerOnly;
}

/// The ordered set of sidebar destinations (spec §4).
const List<NavDestination> kNavDestinations = [
  NavDestination(
    label: 'Dashboard',
    icon: Icons.dashboard_outlined,
    selectedIcon: Icons.dashboard,
    route: Routes.dashboard,
    permission: Permission.viewDashboard,
  ),
  NavDestination(
    label: 'Alerts',
    icon: Icons.notifications_outlined,
    selectedIcon: Icons.notifications,
    route: Routes.alerts,
    permission: Permission.viewDashboard,
  ),
  NavDestination(
    label: 'Businesses',
    icon: Icons.business_outlined,
    selectedIcon: Icons.business,
    route: Routes.businesses,
    permission: Permission.viewBusiness,
  ),
  NavDestination(
    label: 'Products',
    icon: Icons.inventory_2_outlined,
    selectedIcon: Icons.inventory_2,
    route: Routes.products,
    permission: Permission.viewProduct,
  ),
  NavDestination(
    label: 'Campaigns',
    icon: Icons.campaign_outlined,
    selectedIcon: Icons.campaign,
    route: Routes.campaigns,
    permission: Permission.viewCampaign,
  ),
  NavDestination(
    label: 'Orders',
    icon: Icons.receipt_long_outlined,
    selectedIcon: Icons.receipt_long,
    route: Routes.orders,
    permission: Permission.viewOrder,
  ),
  NavDestination(
    label: 'Expenses',
    icon: Icons.account_balance_wallet_outlined,
    selectedIcon: Icons.account_balance_wallet,
    route: Routes.expenses,
    permission: Permission.viewExpense,
  ),
  NavDestination(
    label: 'Dealers',
    icon: Icons.handshake_outlined,
    selectedIcon: Icons.handshake,
    route: Routes.dealers,
    permission: Permission.viewDealer,
  ),
  NavDestination(
    label: 'Customers',
    icon: Icons.people_outline,
    selectedIcon: Icons.people,
    route: Routes.customers,
    permission: Permission.viewCustomer,
  ),
  NavDestination(
    label: 'Reports',
    icon: Icons.assessment_outlined,
    selectedIcon: Icons.assessment,
    route: Routes.reports,
    permission: Permission.viewReports,
  ),
  NavDestination(
    label: 'Users',
    icon: Icons.group_outlined,
    selectedIcon: Icons.group,
    route: Routes.users,
    permission: Permission.manageUsers,
    ownerOnly: true,
  ),
  NavDestination(
    label: 'Settings',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings,
    route: Routes.settings,
    permission: Permission.manageSettings,
  ),
];
