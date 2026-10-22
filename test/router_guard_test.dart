import 'package:flutter_test/flutter_test.dart';
import 'package:salesforce_business_manager/core/enums.dart';
import 'package:salesforce_business_manager/core/permissions.dart';
import 'package:salesforce_business_manager/core/routing/app_routes.dart';
import 'package:salesforce_business_manager/models/app_user.dart';

AppUser _user(UserRole role, {Set<Permission> revoked = const {}}) => AppUser(
      uid: role.name,
      loginId: role.name,
      name: role.name,
      email: '${role.name}@example.com',
      role: role,
      assignedBusinessIds: const ['BIZ-1'],
      revokedPermissions: revoked,
    );

void main() {
  group('Routes.sectionOf', () {
    test('maps a location to its top-level section', () {
      expect(Routes.sectionOf('/orders'), Routes.orders);
      expect(Routes.sectionOf('/orders/ORD-000001'), Routes.orders);
      expect(Routes.sectionOf('/customers/CUST-00001?tab=2'), Routes.customers);
      expect(Routes.sectionOf('/'), isNull);
      expect(Routes.sectionOf(''), isNull);
    });
  });

  group('Routes.accessFor', () {
    test('detail pages inherit their list rule', () {
      expect(Routes.accessFor('/orders/ORD-000001')?.permission,
          Permission.viewOrder);
      expect(Routes.accessFor('/dealers/DLR-00001')?.permission,
          Permission.viewDealer);
    });

    test('Users is owner-only', () {
      expect(Routes.accessFor(Routes.users)?.ownerOnly, isTrue);
    });

    test("Settings and What's new are open to every signed-in user", () {
      expect(Routes.accessFor(Routes.settings), isNull);
      expect(Routes.accessFor(Routes.whatsNew), isNull);
    });

    test('every navigation destination guards its own route', () {
      for (final d in kNavDestinations) {
        if (d.route == Routes.settings) continue;
        expect(Routes.accessFor(d.route), same(d), reason: d.route);
      }
    });
  });

  group('Routes.canOpen', () {
    test('nobody signed in opens nothing', () {
      expect(Routes.canOpen(null, Routes.dashboard), isFalse);
    });

    test('the owner opens everything', () {
      final owner = _user(UserRole.owner);
      for (final d in kNavDestinations) {
        expect(Routes.canOpen(owner, d.route), isTrue, reason: d.route);
      }
    });

    test('an admin is kept out of Users but can open Settings', () {
      final admin = _user(UserRole.admin);
      expect(Routes.canOpen(admin, Routes.users), isFalse);
      expect(Routes.canOpen(admin, Routes.settings), isTrue);
      expect(Routes.canOpen(admin, '/orders/ORD-000001'), isTrue);
    });

    test('a revoked view permission blocks the list and its details', () {
      final admin =
          _user(UserRole.admin, revoked: {Permission.viewReports});
      expect(Routes.canOpen(admin, Routes.reports), isFalse);
    });

    test('a user opens what their role can view', () {
      final user = _user(UserRole.user);
      for (final d in kNavDestinations) {
        if (d.route == Routes.settings) continue;
        expect(Routes.canOpen(user, d.route),
            user.can(d.permission) && !d.ownerOnly,
            reason: d.route);
      }
    });
  });
}
