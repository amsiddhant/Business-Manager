import 'package:flutter_test/flutter_test.dart';
import 'package:salesforce_business_manager/core/app_exception.dart';
import 'package:salesforce_business_manager/core/enums.dart';
import 'package:salesforce_business_manager/core/utils/money.dart';
import 'package:salesforce_business_manager/data/backend.dart';
import 'package:salesforce_business_manager/data/repository.dart';
import 'package:salesforce_business_manager/models/app_user.dart';
import 'package:salesforce_business_manager/models/customer.dart';

/// A minimal in-memory [Backend] for exercising repository authorization and
/// scoping logic without Firebase or SharedPreferences. Only the data methods
/// used by the customer flows are meaningful; auth methods throw.
class _FakeBackend implements Backend {
  final Map<String, Map<String, Map<String, dynamic>>> store = {};

  /// Records every `fetchCollection`/`fetchWhereArrayContains` call so tests can
  /// assert the *shape* of the queries the repository issues (e.g. that no
  /// non-authorizable scalar `businessId` customer query is reintroduced).
  final List<String> queryLog = [];

  @override
  String get label => 'Fake';

  @override
  Future<List<Map<String, dynamic>>> fetchCollection(String collection,
      {String? businessId}) async {
    queryLog.add('fetchCollection($collection, businessId: $businessId)');
    final coll = store[collection];
    if (coll == null) return [];
    final all = coll.values.map((e) => Map<String, dynamic>.from(e)).toList();
    if (businessId == null) return all;
    return all.where((d) => d['businessId'] == businessId).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> fetchWhereArrayContains(
      String collection, String field, String value) async {
    queryLog.add('fetchWhereArrayContains($collection, $field, $value)');
    final coll = store[collection];
    if (coll == null) return [];
    return coll.values
        .map((e) => Map<String, dynamic>.from(e))
        .where((d) => d[field] is List && (d[field] as List).contains(value))
        .toList();
  }

  @override
  Future<Map<String, dynamic>?> fetchDoc(String collection, String id) async {
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

  // ---- Unused auth surface --------------------------------------------------
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

AppUser _admin(List<String> businesses) => AppUser(
      uid: 'admin',
      loginId: 'admin',
      name: 'Admin',
      email: 'admin@example.com',
      role: UserRole.admin,
      assignedBusinessIds: businesses,
    );

void main() {
  group('Customer.fromMap backward compatibility', () {
    test('reads the new businessIds array', () {
      final c = Customer.fromMap({
        'id': 'CUST-00001',
        'businessIds': ['BIZ-1', 'BIZ-2'],
        'name': 'Acme',
      });
      expect(c.businessIds, ['BIZ-1', 'BIZ-2']);
    });

    test('migrates a legacy scalar businessId into a single-element list', () {
      final c = Customer.fromMap({
        'id': 'CUST-00001',
        'businessId': 'BIZ-9',
        'name': 'Legacy Co',
      });
      expect(c.businessIds, ['BIZ-9']);
    });

    test('empty when neither field is present', () {
      final c = Customer.fromMap({'id': 'CUST-00001', 'name': 'Nomad'});
      expect(c.businessIds, isEmpty);
    });

    test('round-trips businessIds through toMap', () {
      const c = Customer(
        id: 'CUST-00001',
        businessIds: ['BIZ-1', 'BIZ-3'],
        name: 'Acme',
      );
      final restored = Customer.fromMap(c.toMap());
      expect(restored.businessIds, ['BIZ-1', 'BIZ-3']);
      // The legacy scalar key is no longer written.
      expect(c.toMap().containsKey('businessId'), isFalse);
    });
  });

  group('Repository customer scoping (business isolation)', () {
    late _FakeBackend backend;

    setUp(() {
      backend = _FakeBackend();
      // Two customers: one tagged to BIZ-1 only, one tagged to BIZ-1 & BIZ-2.
      backend.store['customers'] = {
        'CUST-00001': const Customer(
          id: 'CUST-00001',
          businessIds: ['BIZ-1'],
          name: 'Only One',
        ).toMap(),
        'CUST-00002': const Customer(
          id: 'CUST-00002',
          businessIds: ['BIZ-1', 'BIZ-2'],
          name: 'Shared',
        ).toMap(),
        'CUST-00003': const Customer(
          id: 'CUST-00003',
          businessIds: ['BIZ-3'],
          name: 'Elsewhere',
        ).toMap(),
      };
    });

    test('owner sees every customer', () async {
      final repo = Repository(backend: backend, currentUser: _owner());
      final all = await repo.fetchCustomers();
      expect(all.map((c) => c.id).toSet(),
          {'CUST-00001', 'CUST-00002', 'CUST-00003'});
    });

    test('admin only sees customers tagged to an assigned business', () async {
      final repo =
          Repository(backend: backend, currentUser: _admin(['BIZ-2']));
      final scoped = await repo.fetchCustomers();
      // BIZ-2 only tags CUST-00002.
      expect(scoped.map((c) => c.id).toList(), ['CUST-00002']);
    });

    test('a shared customer is de-duplicated across assigned businesses',
        () async {
      final repo = Repository(
          backend: backend, currentUser: _admin(['BIZ-1', 'BIZ-2']));
      final scoped = await repo.fetchCustomers();
      // CUST-00002 matches both BIZ-1 and BIZ-2 but must appear once.
      final shared =
          scoped.where((c) => c.id == 'CUST-00002').toList();
      expect(shared.length, 1);
      expect(scoped.map((c) => c.id).toSet(), {'CUST-00001', 'CUST-00002'});
    });

    test(
        'a non-owner customer read issues ONLY array-contains queries '
        '(no non-authorizable scalar businessId query)', () async {
      // Firestore "rules are not filters": a scalar where(businessId==id)
      // customer query is not provably authorizable and would reject the whole
      // read, locking out every non-owner. The repository must scope customers
      // exclusively via array-contains on `businessIds`.
      final repo = Repository(
          backend: backend, currentUser: _admin(['BIZ-1', 'BIZ-2']));
      backend.queryLog.clear();
      await repo.fetchCustomers();

      final customerQueries = backend.queryLog
          .where((q) => q.contains('customers'))
          .toList();
      // One array-contains query per assigned business, and nothing else.
      expect(
        customerQueries,
        containsAll([
          'fetchWhereArrayContains(customers, businessIds, BIZ-1)',
          'fetchWhereArrayContains(customers, businessIds, BIZ-2)',
        ]),
      );
      expect(
        customerQueries.any((q) => q.startsWith('fetchCollection(customers')),
        isFalse,
        reason: 'scalar businessId customer query must not be issued',
      );
    });

    test('minting a non-owner customer id also avoids the scalar query',
        () async {
      // The next-id scan for an array-scoped collection must likewise use
      // array-contains, never a scalar businessId filter.
      final repo =
          Repository(backend: backend, currentUser: _admin(['BIZ-1']));
      backend.queryLog.clear();
      await repo.saveCustomer(
        const Customer(id: '', businessIds: ['BIZ-1'], name: 'Fresh'),
        isNew: true,
      );
      final customerReads = backend.queryLog
          .where((q) => q.contains('customers') && q.startsWith('fetch'))
          .toList();
      expect(
        customerReads.any((q) => q.startsWith('fetchCollection(customers')),
        isFalse,
        reason: 'id minting must not issue a scalar businessId customer query',
      );
    });
  });

  group('Repository saveCustomer (tag authorization)', () {
    late _FakeBackend backend;

    setUp(() {
      backend = _FakeBackend();
    });

    test('a non-owner cannot tag a business they are not assigned to',
        () async {
      final repo =
          Repository(backend: backend, currentUser: _admin(['BIZ-1']));
      expect(
        () => repo.saveCustomer(
          const Customer(
              id: '', businessIds: ['BIZ-1', 'BIZ-9'], name: 'Sneaky'),
          isNew: true,
        ),
        throwsA(isA<PermissionDeniedException>()),
      );
    });

    test('editing preserves tags to businesses the caller cannot see',
        () async {
      // Existing customer tagged to BIZ-1 (visible) and BIZ-2 (hidden).
      backend.store['customers'] = {
        'CUST-00001': const Customer(
          id: 'CUST-00001',
          businessIds: ['BIZ-1', 'BIZ-2'],
          name: 'Shared',
        ).toMap(),
      };
      final repo =
          Repository(backend: backend, currentUser: _admin(['BIZ-1']));

      // The admin only sees/submits BIZ-1; the hidden BIZ-2 tag must survive.
      await repo.saveCustomer(
        const Customer(
          id: 'CUST-00001',
          businessIds: ['BIZ-1'],
          name: 'Shared Renamed',
        ),
        isNew: false,
      );

      final saved =
          Customer.fromMap(backend.store['customers']!['CUST-00001']!);
      expect(saved.name, 'Shared Renamed');
      expect(saved.businessIds.toSet(), {'BIZ-1', 'BIZ-2'});
    });

    test('a non-owner cannot smuggle in a new hidden tag on edit', () async {
      backend.store['customers'] = {
        'CUST-00001': const Customer(
          id: 'CUST-00001',
          businessIds: ['BIZ-1'],
          name: 'Shared',
        ).toMap(),
      };
      final repo =
          Repository(backend: backend, currentUser: _admin(['BIZ-1']));

      // Attempt to add BIZ-9 (not assigned) — it must be dropped, not stored.
      await repo.saveCustomer(
        const Customer(
          id: 'CUST-00001',
          businessIds: ['BIZ-1', 'BIZ-9'],
          name: 'Shared',
        ),
        isNew: false,
      );

      final saved =
          Customer.fromMap(backend.store['customers']!['CUST-00001']!);
      expect(saved.businessIds, ['BIZ-1']);
    });

    test('owner may tag any businesses on create', () async {
      final repo = Repository(backend: backend, currentUser: _owner());
      final saved = await repo.saveCustomer(
        const Customer(
            id: '', businessIds: ['BIZ-1', 'BIZ-2', 'BIZ-3'], name: 'Global'),
        isNew: true,
      );
      expect(saved.businessIds.toSet(), {'BIZ-1', 'BIZ-2', 'BIZ-3'});
      expect(saved.id, startsWith('CUST-'));
    });

    test('creating with no businesses is rejected', () async {
      final repo = Repository(backend: backend, currentUser: _owner());
      expect(
        () => repo.saveCustomer(
          const Customer(id: '', businessIds: [], name: 'Orphan'),
          isNew: true,
        ),
        throwsA(isA<PermissionDeniedException>()),
      );
    });

    test('a non-owner minting ids does not collide with existing customers',
        () async {
      // A customer already exists in the admin's assigned business. Because
      // customers store `businessIds` (an array), the next-id scan must use an
      // array-contains query — a scalar `businessId` filter would match nothing
      // and every new customer would collide at CUST-00001, overwriting data.
      final repo =
          Repository(backend: backend, currentUser: _admin(['BIZ-1']));
      final first = await repo.saveCustomer(
        const Customer(id: '', businessIds: ['BIZ-1'], name: 'First'),
        isNew: true,
      );
      final second = await repo.saveCustomer(
        const Customer(id: '', businessIds: ['BIZ-1'], name: 'Second'),
        isNew: true,
      );
      expect(first.id, isNot(second.id));
      expect(backend.store['customers']!.length, 2);
    });
  });

  group('Repository saveCustomer (per-business contract authorization)', () {
    late _FakeBackend backend;

    setUp(() {
      backend = _FakeBackend();
    });

    test('a contract keyed under an untagged business is rejected on create',
        () async {
      final repo = Repository(backend: backend, currentUser: _owner());
      expect(
        () => repo.saveCustomer(
          const Customer(
            id: '',
            businessIds: ['BIZ-1'],
            name: 'Acme',
            contractsByBusiness: {
              'BIZ-2': BusinessContract(
                  active: ServiceContract(businessId: 'BIZ-2')),
            },
          ),
          isNew: true,
        ),
        throwsA(isA<PermissionDeniedException>()),
      );
    });

    test('an editing non-owner cannot drop a contract for a hidden business',
        () async {
      // Stored: contracts under BIZ-1 (visible) and BIZ-2 (hidden).
      backend.store['customers'] = {
        'CUST-00001': const Customer(
          id: 'CUST-00001',
          businessIds: ['BIZ-1', 'BIZ-2'],
          name: 'Shared',
          contractsByBusiness: {
            'BIZ-1': BusinessContract(
                active: ServiceContract(businessId: 'BIZ-1')),
            'BIZ-2': BusinessContract(
                active: ServiceContract(businessId: 'BIZ-2')),
          },
        ).toMap(),
      };
      final repo =
          Repository(backend: backend, currentUser: _admin(['BIZ-1']));

      // The admin edits from a BIZ-1-scoped view, submitting only BIZ-1's
      // contract. The hidden BIZ-2 contract must be merged back, not dropped.
      await repo.saveCustomer(
        const Customer(
          id: 'CUST-00001',
          businessIds: ['BIZ-1'],
          name: 'Shared Renamed',
          contractsByBusiness: {
            'BIZ-1': BusinessContract(
                active: ServiceContract(businessId: 'BIZ-1')),
          },
        ),
        isNew: false,
      );

      final saved =
          Customer.fromMap(backend.store['customers']!['CUST-00001']!);
      expect(saved.name, 'Shared Renamed');
      expect(saved.hasContractFor('BIZ-1'), isTrue);
      expect(saved.hasContractFor('BIZ-2'), isTrue);
    });

    test('a non-owner cannot forge or overwrite a hidden business contract',
        () async {
      // Stored: only BIZ-1 (visible) has a contract; BIZ-2 (hidden) has none.
      backend.store['customers'] = {
        'CUST-00001': const Customer(
          id: 'CUST-00001',
          businessIds: ['BIZ-1', 'BIZ-2'],
          name: 'Shared',
          contractsByBusiness: {
            'BIZ-1': BusinessContract(
                active: ServiceContract(businessId: 'BIZ-1', price: Money(100))),
          },
        ).toMap(),
      };
      final repo =
          Repository(backend: backend, currentUser: _admin(['BIZ-1']));

      // The admin tries to smuggle in a contract for the hidden BIZ-2 — it must
      // be stripped, leaving BIZ-2 without a contract.
      await repo.saveCustomer(
        const Customer(
          id: 'CUST-00001',
          businessIds: ['BIZ-1'],
          name: 'Shared',
          contractsByBusiness: {
            'BIZ-1': BusinessContract(
                active: ServiceContract(businessId: 'BIZ-1', price: Money(100))),
            'BIZ-2': BusinessContract(
                active: ServiceContract(
                    businessId: 'BIZ-2', price: Money(999999))),
          },
        ),
        isNew: false,
      );

      final saved =
          Customer.fromMap(backend.store['customers']!['CUST-00001']!);
      expect(saved.hasContractFor('BIZ-2'), isFalse);
      expect(saved.activeContractFor('BIZ-1')!.price, const Money(100));
    });

    test('owner may record independent contracts per tagged business',
        () async {
      final repo = Repository(backend: backend, currentUser: _owner());
      final saved = await repo.saveCustomer(
        const Customer(
          id: '',
          businessIds: ['BIZ-1', 'BIZ-2'],
          name: 'Global',
          contractsByBusiness: {
            'BIZ-1': BusinessContract(
                active: ServiceContract(businessId: 'BIZ-1', price: Money(500))),
            'BIZ-2': BusinessContract(
                active: ServiceContract(businessId: 'BIZ-2', price: Money(900))),
          },
        ),
        isNew: true,
      );
      expect(saved.activeContractFor('BIZ-1')!.price, const Money(500));
      expect(saved.activeContractFor('BIZ-2')!.price, const Money(900));

      final restored =
          Customer.fromMap(backend.store['customers']![saved.id]!);
      expect(restored.allActiveContracts.length, 2);
    });
  });
}
