import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/permissions.dart';
import '../../core/routing/app_routes.dart';
import '../../core/routing/create_requests.dart';
import '../../models/app_settings.dart';
import '../../models/app_user.dart';
import '../../screens/businesses/businesses_screen.dart';
import '../../screens/campaigns/campaigns_screen.dart';
import '../../screens/customers/customers_screen.dart';
import '../../screens/dealers/dealers_screen.dart';
import '../../screens/expenses/expenses_screen.dart';
import '../../screens/orders/orders_screen.dart';
import '../../screens/products/products_screen.dart';
import '../../state/filter_controller.dart';

/// "New order", "New customer"… — one per section the user may create in.
/// Used by the top bar's + menu, the mobile FAB, the `N` shortcut and the
/// command palette. The form opens over the current page, pre-set to the
/// business picked in the scope selector.
class CreateAction {
  const CreateAction({
    required this.section,
    required this.label,
    required this.icon,
    required this.permission,
    required this.run,
    this.ownerOnly = false,
  });

  final String section;
  final String label;
  final IconData icon;
  final Permission permission;
  final bool ownerOnly;
  final Future<void> Function(BuildContext context) run;

  bool allowedFor(AppUser? user) =>
      user != null &&
      user.can(permission) &&
      (!ownerOnly || user.isOwner);
}

String? _biz(BuildContext context) =>
    context.read<FilterController>().selectedBusinessId;

final List<CreateAction> kCreateActions = [
  CreateAction(
    section: Routes.orders,
    label: 'New order',
    icon: Icons.receipt_long_outlined,
    permission: Permission.createOrder,
    run: (c) => OrdersScreen.openForm(c, null, _biz(c)),
  ),
  CreateAction(
    section: Routes.customers,
    label: 'New customer',
    icon: Icons.person_add_alt_outlined,
    permission: Permission.createCustomer,
    run: (c) => CustomersScreen.openForm(c, null, _biz(c)),
  ),
  CreateAction(
    section: Routes.expenses,
    label: 'New expense',
    icon: Icons.account_balance_wallet_outlined,
    permission: Permission.createExpense,
    run: (c) => ExpensesScreen.openForm(c, null, _biz(c)),
  ),
  CreateAction(
    section: Routes.campaigns,
    label: 'New campaign',
    icon: Icons.campaign_outlined,
    permission: Permission.createCampaign,
    run: (c) => CampaignsScreen.openForm(c, null, _biz(c)),
  ),
  CreateAction(
    section: Routes.products,
    label: 'New product',
    icon: Icons.inventory_2_outlined,
    permission: Permission.createProduct,
    run: (c) => ProductsScreen.openForm(c, null, _biz(c)),
  ),
  CreateAction(
    section: Routes.dealers,
    label: 'New dealer',
    icon: Icons.handshake_outlined,
    permission: Permission.createDealer,
    run: (c) => DealersScreen.openForm(c, null, _biz(c)),
  ),
  CreateAction(
    section: Routes.businesses,
    label: 'New business',
    icon: Icons.add_business_outlined,
    permission: Permission.createBusiness,
    run: (c) => BusinessesScreen.openForm(c, null),
  ),
  CreateAction(
    section: Routes.users,
    label: 'New user',
    icon: Icons.person_add_outlined,
    permission: Permission.manageUsers,
    ownerOnly: true,
    // The user form lives inside the Users screen (it refreshes its list).
    run: (c) async {
      c.go(Routes.users);
      CreateRequests.instance.request(Routes.users);
    },
  ),
];

/// The create actions [user] may use. Sections switched off in [modules] are
/// left out.
List<CreateAction> createActionsFor(AppUser? user, {ModuleSettings? modules}) =>
    [
      for (final a in kCreateActions)
        if (a.allowedFor(user) && (modules?.isEnabled(a.section) ?? true)) a,
    ];

/// The create action for the section [location] belongs to, if [user] may
/// use it (and the section is on).
CreateAction? createActionForLocation(
  AppUser? user,
  String location, {
  ModuleSettings? modules,
}) {
  final section = Routes.sectionOf(location);
  for (final a in kCreateActions) {
    if (a.section == section) {
      final on = modules?.isEnabled(a.section) ?? true;
      return a.allowedFor(user) && on ? a : null;
    }
  }
  return null;
}
