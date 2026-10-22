import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:salesforce_business_manager/core/enums.dart';
import 'package:salesforce_business_manager/data/backend.dart';
import 'package:salesforce_business_manager/data/local_backend.dart';
import 'package:salesforce_business_manager/data/repository.dart';
import 'package:salesforce_business_manager/models/app_user.dart';
import 'package:salesforce_business_manager/models/business.dart';
import 'package:salesforce_business_manager/models/product.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _owner = AppUser(
  uid: 'owner',
  loginId: 'owner',
  name: 'Owner',
  email: 'owner@example.com',
  role: UserRole.owner,
);

const _admin = AppUser(
  uid: 'admin',
  loginId: 'admin',
  name: 'Admin',
  email: 'admin@example.com',
  role: UserRole.admin,
  assignedBusinessIds: ['BIZ-1'],
);

/// A demo backend holding two businesses: BIZ-1 has PROD-00003, BIZ-2 (which
/// the admin can't see) has PROD-00007.
Future<LocalBackend> _backend({Map<String, int> counters = const {}}) async {
  Map<String, dynamic> product(String id, String biz) =>
      Product(id: id, businessId: biz, name: id).toMap();
  SharedPreferences.setMockInitialValues({
    'sbm_local_store_v1': jsonEncode({
      Collections.businesses: {
        'BIZ-1': const Business(id: 'BIZ-1', name: 'One').toMap(),
        'BIZ-2': const Business(id: 'BIZ-2', name: 'Two').toMap(),
      },
      Collections.products: {
        'PROD-00003': product('PROD-00003', 'BIZ-1'),
        'PROD-00007': product('PROD-00007', 'BIZ-2'),
      },
      Collections.counters: {
        for (final e in counters.entries) e.key: {'value': e.value},
      },
    }),
  });
  final backend = LocalBackend(await SharedPreferences.getInstance());
  await backend.initialize();
  return backend;
}

Future<int?> _counter(LocalBackend backend, String prefix) async =>
    ((await backend.fetchDoc(Collections.counters, prefix))?['value'] as num?)
        ?.toInt();

const _new = Product(id: '', businessId: 'BIZ-1', name: 'New');

void main() {
  test("the owner's first create seeds the counter from one scan", () async {
    final backend = await _backend();
    final repo = Repository(backend: backend, currentUser: _owner);

    expect((await repo.saveProduct(_new, isNew: true)).id, 'PROD-00008');
    expect(await _counter(backend, 'PROD'), 8);
    expect((await repo.saveProduct(_new, isNew: true)).id, 'PROD-00009');
    expect(await _counter(backend, 'PROD'), 9);
  });

  test(
    'with a counter, an admin never reuses an id from another business',
    () async {
      final backend = await _backend(counters: {'PROD': 7});
      final repo = Repository(backend: backend, currentUser: _admin);

      // A scan of BIZ-1 alone would have produced PROD-00004 — and later
      // collided with ids in businesses the admin can't see.
      expect((await repo.saveProduct(_new, isNew: true)).id, 'PROD-00008');
    },
  );

  test('without a counter, an admin falls back to the old scan', () async {
    final backend = await _backend();
    final repo = Repository(backend: backend, currentUser: _admin);

    expect((await repo.saveProduct(_new, isNew: true)).id, 'PROD-00004');
    expect(
      await _counter(backend, 'PROD'),
      isNull,
      reason: 'only the owner creates counters',
    );
  });

  test('a lagging counter heals from the highest id already loaded', () async {
    final backend = await _backend(counters: {'PROD': 2});
    final repo = Repository(backend: backend, currentUser: _owner)
      ..idHint = (prefix) => prefix == 'PROD' ? 7 : 0;

    expect((await repo.saveProduct(_new, isNew: true)).id, 'PROD-00008');
  });

  test('healIdCounters raises counters for the owner only', () async {
    final backend = await _backend(counters: {'PROD': 2});

    await Repository(
      backend: backend,
      currentUser: _admin,
    ).healIdCounters({'PROD': 7});
    expect(await _counter(backend, 'PROD'), 2);

    await Repository(
      backend: backend,
      currentUser: _owner,
    ).healIdCounters({'PROD': 7, 'ORD': 12});
    expect(await _counter(backend, 'PROD'), 7);
    expect(await _counter(backend, 'ORD'), 12);
  });

  test('an import reserves a block of ids in one go', () async {
    final backend = await _backend(counters: {'PROD': 7});
    final repo = Repository(backend: backend, currentUser: _owner);

    await repo.reserveIdsFor(Collections.products, 3);
    expect(await _counter(backend, 'PROD'), 10);

    final ids = [
      for (var i = 0; i < 3; i++)
        (await repo.saveProduct(_new, isNew: true)).id,
    ];
    expect(ids, ['PROD-00008', 'PROD-00009', 'PROD-00010']);
    expect(await _counter(backend, 'PROD'), 10);

    repo.releaseReservedIds();
    expect((await repo.saveProduct(_new, isNew: true)).id, 'PROD-00011');
  });
}
