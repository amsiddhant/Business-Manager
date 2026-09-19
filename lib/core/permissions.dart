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
  viewReports,
  exportData,
  manageUsers,
  configureFirebase,
  manageSettings,
}

/// Central role→permission resolver. UI hiding is a convenience; the same
/// checks are also enforced in the service layer (see repository guards).
class Permissions {
  Permissions._();

  /// Permissions granted to a plain USER: view + add on core modules, no
  /// deletes, no settings/user/firebase administration.
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
    Permission.viewDealer,
    Permission.viewReports,
  };

  /// Everything an ADMIN can do within assigned businesses (no owner-only
  /// administration such as user management or firebase configuration).
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
    Permission.viewReports,
    Permission.exportData,
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
