import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:salesforce_business_manager/core/enums.dart';
import 'package:salesforce_business_manager/core/permissions.dart';
import 'package:salesforce_business_manager/core/routing/app_router.dart';
import 'package:salesforce_business_manager/core/routing/app_routes.dart';
import 'package:salesforce_business_manager/core/routing/nav_registry.dart';
import 'package:salesforce_business_manager/models/app_user.dart';
import 'package:salesforce_business_manager/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  TestWidgetsFlutterBinding.ensureInitialized();

  group('shell branches', () {
    test('every navigation section has a branch, plus What\'s new', () {
      for (final d in kNavDestinations) {
        expect(kShellBranches, contains(d.route), reason: d.label);
      }
      expect(kShellBranches, contains(Routes.whatsNew));
      expect(kShellBranches, contains(Routes.settings));
      expect(kShellBranches.toSet().length, kShellBranches.length,
          reason: 'no duplicates');
    });

    test('the router declares the branches in kShellBranches order',
        () async {
      SharedPreferences.setMockInitialValues({});
      final appState = await AppState.create();
      final router = buildRouter(appState);
      addTearDown(router.dispose);

      final shell = router.configuration.routes
          .whereType<StatefulShellRoute>()
          .single;
      expect(
        [for (final b in shell.branches) (b.routes.first as GoRoute).path],
        kShellBranches,
      );
    });

    test('every sidebar group route is a known destination', () {
      for (final g in kNavGroups) {
        for (final r in g.routes) {
          expect(NavRegistry.destinationFor(r), isNotNull, reason: r);
        }
      }
      final grouped = {for (final g in kNavGroups) ...g.routes};
      for (final d in kNavDestinations) {
        expect(grouped, contains(d.route), reason: '${d.label} has a group');
      }
    });
  });

  test('detail pages, queries and unknown paths map to a branch (or none)',
      () {
    expect(NavRegistry.branchIndexOf('/orders/ORD-000001'),
        kShellBranches.indexOf(Routes.orders));
    expect(NavRegistry.branchIndexOf('/customers/CUST-00001?tab=2'),
        kShellBranches.indexOf(Routes.customers));
    expect(NavRegistry.branchIndexOf(Routes.whatsNew),
        kShellBranches.indexOf(Routes.whatsNew));
    expect(NavRegistry.branchIndexOf('/nowhere'), isNull);
    expect(NavRegistry.branchIndexOf('/'), isNull);
  });

  group('visibility by role', () {
    test('owners see every section, including Users', () {
      final owner = _user(UserRole.owner);
      expect([for (final d in NavRegistry.visible(owner)) d.route],
          containsAll(kNavDestinations.map((d) => d.route)));
    });

    test('Users is hidden from admins and users', () {
      for (final role in [UserRole.admin, UserRole.user]) {
        final routes = [
          for (final d in NavRegistry.visible(_user(role))) d.route
        ];
        expect(routes, isNot(contains(Routes.users)), reason: role.name);
        expect(routes, contains(Routes.dashboard), reason: role.name);
      }
    });

    test('a revoked permission hides its section everywhere', () {
      final u = _user(UserRole.admin, revoked: {Permission.viewOrder});
      bool hasOrders(Iterable<NavDestination> ds) =>
          ds.any((d) => d.route == Routes.orders);
      expect(hasOrders(NavRegistry.visible(u)), isFalse);
      expect(hasOrders(NavRegistry.mobilePrimary(u)), isFalse);
      expect(
          hasOrders(NavRegistry.groupsFor(u).expand((g) => g.items)), isFalse);
    });

    test('groups with nothing visible are dropped', () {
      final u = _user(UserRole.user, revoked: {
        Permission.viewExpense,
        Permission.viewDealer,
      });
      expect([for (final g in NavRegistry.groupsFor(u)) g.group.label],
          isNot(contains('Spend')));
    });

    test('the bottom bar has at most four sections, primary ones first', () {
      for (final role in UserRole.values) {
        final items = NavRegistry.mobilePrimary(_user(role));
        expect(items.length, lessThanOrEqualTo(4), reason: role.name);
        expect(items.first.route, Routes.dashboard, reason: role.name);
      }
      // Losing a primary section tops the bar up from the rest.
      final u = _user(UserRole.admin, revoked: {Permission.viewReports});
      final items = NavRegistry.mobilePrimary(u);
      expect(items.length, 4);
      expect(items.map((d) => d.route), isNot(contains(Routes.reports)));
    });
  });

  test('scope selectors follow what the page shows', () {
    expect(NavRegistry.scopeFor(Routes.dashboard), ScopeUse.businessAndPeriod);
    expect(NavRegistry.scopeFor('/reports?tab=2'), ScopeUse.businessAndPeriod);
    expect(NavRegistry.scopeFor(Routes.orders), ScopeUse.business);
    expect(NavRegistry.scopeFor('/orders/ORD-000001'), ScopeUse.none);
    expect(NavRegistry.scopeFor('/products/PRD-00001'), ScopeUse.period);
    expect(NavRegistry.scopeFor(Routes.businesses), ScopeUse.none);
    expect(NavRegistry.scopeFor('/businesses/BIZ-00001'), ScopeUse.period);
    expect(NavRegistry.scopeFor(Routes.settings), ScopeUse.none);
    expect(NavRegistry.scopeFor(Routes.whatsNew), ScopeUse.none);
  });

  test('section roots and titles', () {
    expect(NavRegistry.isSectionRoot(Routes.orders), isTrue);
    expect(NavRegistry.isSectionRoot('/orders?status=open'), isTrue);
    expect(NavRegistry.isSectionRoot('/orders/ORD-000001'), isFalse);
    expect(NavRegistry.titleFor('/orders/ORD-000001'), 'Orders');
    expect(NavRegistry.titleFor(Routes.whatsNew), "What's new");
    expect(NavRegistry.titleFor('/'), 'Business Manager');
  });
}
