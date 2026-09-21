import 'package:flutter_test/flutter_test.dart';
import 'package:salesforce_business_manager/core/app_exception.dart';
import 'package:salesforce_business_manager/core/enums.dart';
import 'package:salesforce_business_manager/data/backend.dart';
import 'package:salesforce_business_manager/data/repository.dart';
import 'package:salesforce_business_manager/models/app_user.dart';
import 'package:salesforce_business_manager/models/business.dart';
import 'package:salesforce_business_manager/models/customer.dart';
import 'package:salesforce_business_manager/state/data_controller.dart';

/// In-memory [Backend] that can be told to reject reads for a specific
/// collection, so we can exercise [DataController.load]'s failure isolation
/// (one collection denied by the rules must not blank the whole app).
class _FaultyBackend implements Backend {
  _FaultyBackend({this.failCollection});

  /// When set, any read of this collection throws a permission-denied error,
  /// mimicking a Firestore rules rejection ("rules are not filters").
  final String? failCollection;

  final Map<String, Map<String, Map<String, dynamic>>> store = {};

  void _maybeFail(String collection) {
    if (collection == failCollection) {
      throw const PermissionDeniedException();
    }
  }

  @override
  String get label => 'Faulty';

  @override
  Future<List<Map<String, dynamic>>> fetchCollection(String collection,
      {String? businessId}) async {
    _maybeFail(collection);
    final coll = store[collection];
    if (coll == null) return [];
    final all = coll.values.map((e) => Map<String, dynamic>.from(e)).toList();
    if (businessId == null) return all;
    return all.where((d) => d['businessId'] == businessId).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> fetchWhereArrayContains(
      String collection, String field, String value) async {
    _maybeFail(collection);
    final coll = store[collection];
    if (coll == null) return [];
    return coll.values
        .map((e) => Map<String, dynamic>.from(e))
        .where((d) => d[field] is List && (d[field] as List).contains(value))
        .toList();
  }

  @override
  Future<Map<String, dynamic>?> fetchDoc(String collection, String id) async {
    _maybeFail(collection);
    final doc = store[collection]?[id];
    return doc == null ? null : Map<String, dynamic>.from(doc);
  }

  @override
  Future<void> setDoc(
      String collection, String id, Map<String, dynamic> data) async {
    (store[collection] ??= {})[id] = Map<String, dynamic>.from(data);
  }

  @override
  Future<void> deleteDoc(String collection, String id) async {
    store[collection]?.remove(id);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

AppUser _owner() => const AppUser(
      uid: 'owner',
      loginId: 'owner',
      name: 'Owner',
      email: 'owner@example.com',
      role: UserRole.owner,
    );

void _seed(_FaultyBackend backend) {
  backend.store['businesses'] = {
    'BIZ-1': const Business(id: 'BIZ-1', name: 'Acme').toMap(),
  };
  backend.store['customers'] = {
    'CUST-00001': const Customer(
      id: 'CUST-00001',
      businessIds: ['BIZ-1'],
      name: 'Someone',
    ).toMap(),
  };
}

void main() {
  group('DataController.load failure isolation', () {
    test('a single non-critical collection failure degrades to a warning',
        () async {
      final backend = _FaultyBackend(failCollection: Collections.customers);
      _seed(backend);
      final repo = Repository(backend: backend, currentUser: _owner());
      final controller = DataController(repo);

      await controller.load();

      // The app is usable: loaded, no full-screen error.
      expect(controller.loaded, isTrue);
      expect(controller.error, isNull);
      // The failing collection is empty; a warning captures the failure.
      expect(controller.customers, isEmpty);
      expect(controller.hasWarnings, isTrue);
      expect(controller.warnings.single, startsWith('Customers:'));
      // The businesses the user CAN read still loaded.
      expect(controller.businesses.map((b) => b.id), ['BIZ-1']);
    });

    test('an all-success load records no warnings', () async {
      final backend = _FaultyBackend();
      _seed(backend);
      final repo = Repository(backend: backend, currentUser: _owner());
      final controller = DataController(repo);

      await controller.load();

      expect(controller.loaded, isTrue);
      expect(controller.error, isNull);
      expect(controller.hasWarnings, isFalse);
      expect(controller.customers.map((c) => c.id), ['CUST-00001']);
    });

    test('a businesses (scope root) failure hard-fails full-screen', () async {
      final backend = _FaultyBackend(failCollection: Collections.businesses);
      _seed(backend);
      final repo = Repository(backend: backend, currentUser: _owner());
      final controller = DataController(repo);

      await controller.load();

      // Without the scope root there is nothing to render: surface full-screen.
      expect(controller.loaded, isFalse);
      expect(controller.error, isNotNull);
      // No misleading per-collection warnings in the essential-failure path.
      expect(controller.hasWarnings, isFalse);
    });

    test('warnings are cleared on a subsequent successful reload', () async {
      final backend = _FaultyBackend(failCollection: Collections.customers);
      _seed(backend);
      final repo = Repository(backend: backend, currentUser: _owner());
      final controller = DataController(repo);

      await controller.load();
      expect(controller.hasWarnings, isTrue);

      // Repair the backend and reload; warnings must not linger.
      final healthy = _FaultyBackend();
      _seed(healthy);
      controller.rebind(Repository(backend: healthy, currentUser: _owner()));
      await controller.refresh();

      expect(controller.hasWarnings, isFalse);
      expect(controller.customers, isNotEmpty);
    });
  });
}
