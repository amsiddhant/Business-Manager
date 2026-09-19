import 'package:flutter_test/flutter_test.dart';
import 'package:salesforce_business_manager/core/enums.dart';
import 'package:salesforce_business_manager/core/permissions.dart';
import 'package:salesforce_business_manager/models/app_user.dart';

AppUser _user(
  UserRole role, {
  List<String> businesses = const [],
  Set<Permission> granted = const {},
  Set<Permission> revoked = const {},
  AccountStatus status = AccountStatus.active,
}) =>
    AppUser(
      uid: 'u1',
      loginId: 'login',
      name: 'Test',
      email: 'test@example.com',
      role: role,
      status: status,
      assignedBusinessIds: businesses,
      grantedPermissions: granted,
      revokedPermissions: revoked,
    );

void main() {
  group('Permissions.forRole', () {
    test('owner gets every permission', () {
      expect(Permissions.forRole(UserRole.owner),
          Permission.values.toSet());
    });

    test('admin can manage records but not owner-only administration', () {
      final admin = Permissions.forRole(UserRole.admin);
      expect(admin.contains(Permission.deleteProduct), isTrue);
      expect(admin.contains(Permission.editOrder), isTrue);
      expect(admin.contains(Permission.exportData), isTrue);
      expect(admin.contains(Permission.manageUsers), isFalse);
      expect(admin.contains(Permission.configureFirebase), isFalse);
      expect(admin.contains(Permission.manageSettings), isFalse);
      expect(admin.contains(Permission.createBusiness), isFalse);
    });

    test('user has view + add only, no deletes or administration', () {
      final user = Permissions.forRole(UserRole.user);
      expect(user.contains(Permission.viewProduct), isTrue);
      expect(user.contains(Permission.createProduct), isTrue);
      expect(user.contains(Permission.createOrder), isTrue);
      expect(user.contains(Permission.deleteProduct), isFalse);
      expect(user.contains(Permission.deleteOrder), isFalse);
      expect(user.contains(Permission.manageUsers), isFalse);
      expect(user.contains(Permission.exportData), isFalse);
    });
  });

  group('Permissions.resolve (overrides)', () {
    test('granted permissions are added to a user', () {
      final resolved = Permissions.resolve(
        UserRole.user,
        granted: {Permission.deleteProduct},
      );
      expect(resolved.contains(Permission.deleteProduct), isTrue);
    });

    test('revoked permissions are removed from an admin', () {
      final resolved = Permissions.resolve(
        UserRole.admin,
        revoked: {Permission.deleteProduct},
      );
      expect(resolved.contains(Permission.deleteProduct), isFalse);
      expect(resolved.contains(Permission.editProduct), isTrue);
    });

    test('owner ignores overrides and always gets everything', () {
      final resolved = Permissions.resolve(
        UserRole.owner,
        revoked: {Permission.deleteProduct, Permission.manageUsers},
      );
      expect(resolved, Permission.values.toSet());
    });

    test('revoked wins when a permission is both granted and revoked', () {
      final resolved = Permissions.resolve(
        UserRole.user,
        granted: {Permission.deleteProduct},
        revoked: {Permission.deleteProduct},
      );
      expect(resolved.contains(Permission.deleteProduct), isFalse);
    });
  });

  group('AppUser.can (enforced with account status)', () {
    test('active admin can perform granted actions', () {
      final admin = _user(UserRole.admin);
      expect(admin.can(Permission.editProduct), isTrue);
      expect(admin.can(Permission.manageUsers), isFalse);
    });

    test('disabled users cannot do anything', () {
      final disabled = _user(UserRole.owner, status: AccountStatus.disabled);
      expect(disabled.can(Permission.viewDashboard), isFalse);
      expect(disabled.can(Permission.manageUsers), isFalse);
    });

    test('per-user overrides flow through can()', () {
      final user = _user(UserRole.user, granted: {Permission.exportData});
      expect(user.can(Permission.exportData), isTrue);
      expect(user.can(Permission.deleteProduct), isFalse);
    });
  });

  group('AppUser.canAccessBusiness (business isolation)', () {
    test('owner can access any business', () {
      final owner = _user(UserRole.owner);
      expect(owner.canAccessBusiness('BIZ-any'), isTrue);
    });

    test('non-owner only accesses assigned businesses', () {
      final admin = _user(UserRole.admin, businesses: ['BIZ-1', 'BIZ-2']);
      expect(admin.canAccessBusiness('BIZ-1'), isTrue);
      expect(admin.canAccessBusiness('BIZ-3'), isFalse);
    });

    test('user with no assignments accesses nothing', () {
      final user = _user(UserRole.user);
      expect(user.canAccessBusiness('BIZ-1'), isFalse);
    });
  });
}
