import 'package:flutter/material.dart';

import '../permissions.dart';

/// Canonical route paths used across the app.
class Routes {
  Routes._();
  static const login = '/login';
  static const forgotPassword = '/forgot-password';
  static const dashboard = '/dashboard';
  static const businesses = '/businesses';
  static const products = '/products';
  static const productDetail = '/products/:id';
  static const campaigns = '/campaigns';
  static const orders = '/orders';
  static const expenses = '/expenses';
  static const dealers = '/dealers';
  static const customers = '/customers';
  static const customerDetail = '/customers/:id';
  static const reports = '/reports';
  static const users = '/users';
  static const settings = '/settings';

  static String productDetailPath(String id) => '/products/$id';
  static String customerDetailPath(String id) => '/customers/$id';
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
