import 'enums.dart';

/// The full catalogue of permission flags checked throughout the app.
enum Permission {
  viewDashboard,
  viewBusiness,
  createBusiness,
  editBusiness,
  deleteBusiness,
  viewProduct,
  createProduct,
  editProduct,
  deleteProduct,
  viewCampaign,
  createCampaign,
  editCampaign,
  deleteCampaign,
  viewOrder,
  createOrder,
  editOrder,
  deleteOrder,
  viewExpense,
  createExpense,
  editExpense,
  deleteExpense,
  viewDealer,
  createDealer,
  editDealer,
  deleteDealer,
  viewCustomer,
  createCustomer,
  editCustomer,
  deleteCustomer,
  viewReports,
  exportData,
  manageUsers,
  configureFirebase,
  manageSettings,

  /// Set and edit goals & targets for the businesses one can access.
  manageGoals,
}

/// Central role→permission resolver. UI hiding is a convenience; the same
/// checks are also enforced in the service layer (see repository guards).
class Permissions {
  Permissions._();

  /// Permissions granted to a plain USER: view + add on core modules
  /// (products, campaigns, orders and expenses), no edits, no deletes, no
  /// settings/user/firebase administration.
  static const Set<Permission> _userPermissions = {
    Permission.viewDashboard,
    Permission.viewBusiness,
    Permission.viewProduct,
    Permission.createProduct,
    Permission.viewCampaign,
    Permission.createCampaign,
    Permission.viewOrder,
    Permission.createOrder,
    Permission.viewExpense,
    Permission.createExpense,
    Permission.viewDealer,
    // Customers: a user may view, add and edit but never delete.
    Permission.viewCustomer,
    Permission.createCustomer,
    Permission.editCustomer,
    Permission.viewReports,
  };

  /// Everything an ADMIN can do within assigned businesses, plus the
  /// organisation's settings and goals (no owner-only administration such as
  /// user management, firebase configuration, the danger zone or the audit
  /// log). The Owner can revoke `manageSettings` / `manageGoals` per Admin.
  static const Set<Permission> _adminPermissions = {
    Permission.viewDashboard,
    Permission.viewBusiness,
    Permission.viewProduct,
    Permission.createProduct,
    Permission.editProduct,
    Permission.deleteProduct,
    Permission.viewCampaign,
    Permission.createCampaign,
    Permission.editCampaign,
    Permission.deleteCampaign,
    Permission.viewOrder,
    Permission.createOrder,
    Permission.editOrder,
    Permission.deleteOrder,
    Permission.viewExpense,
    Permission.createExpense,
    Permission.editExpense,
    Permission.deleteExpense,
    Permission.viewDealer,
    Permission.createDealer,
    Permission.editDealer,
    Permission.deleteDealer,
    Permission.viewCustomer,
    Permission.createCustomer,
    Permission.editCustomer,
    Permission.deleteCustomer,
    Permission.viewReports,
    Permission.exportData,
    Permission.manageSettings,
    Permission.manageGoals,
  };

  /// Resolves the default permission set for a role. OWNER gets everything.
  static Set<Permission> forRole(UserRole role) {
    switch (role) {
      case UserRole.owner:
        return Permission.values.toSet();
      case UserRole.admin:
        return _adminPermissions;
      case UserRole.user:
        return _userPermissions;
    }
  }

  /// Resolves effective permissions given a role plus optional per-user
  /// overrides. [granted] adds extra permissions; [revoked] removes some.
  static Set<Permission> resolve(
    UserRole role, {
    Set<Permission> granted = const {},
    Set<Permission> revoked = const {},
  }) {
    if (role == UserRole.owner) return Permission.values.toSet();
    return {...forRole(role), ...granted}..removeAll(revoked);
  }
}
