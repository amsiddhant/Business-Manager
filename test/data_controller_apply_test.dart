import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:salesforce_business_manager/core/enums.dart';
import 'package:salesforce_business_manager/data/backend.dart';
import 'package:salesforce_business_manager/data/repository.dart';
import 'package:salesforce_business_manager/models/app_user.dart';
import 'package:salesforce_business_manager/models/business.dart';
import 'package:salesforce_business_manager/models/product.dart';
import 'package:salesforce_business_manager/state/data_controller.dart';

import 'support/memory_backend.dart';

const _owner = AppUser(
  uid: 'owner',
  loginId: 'owner',
  name: 'Owner',
  email: 'owner@example.com',
  role: UserRole.owner,
);

const _new = Product(id: '', businessId: 'BIZ-1', name: 'Widget');

/// A backend whose reads wait for [gate], to hold a load in flight.
class _SlowBackend extends BatchMemoryBackend {
  Completer<void>? gate;

  @override
  Future<List<Map<String, dynamic>>> fetchCollection(
    String collection, {
    String? businessId,
  }) async {
    await gate?.future;
    return super.fetchCollection(collection, businessId: businessId);
  }
}

Future<(Repository, DataController, BatchMemoryBackend)> _loaded() async {
  final backend = BatchMemoryBackend()
    ..put(
      Collections.businesses,
      'BIZ-1',
      const Business(id: 'BIZ-1', name: 'Acme').toMap(),
    )
    ..put(
      Collections.businesses,
      'BIZ-2',
      const Business(id: 'BIZ-2', name: 'Beta').toMap(),
    );
  final repo = Repository(backend: backend, currentUser: _owner);
  final data = DataController(repo);
  await data.load();
  return (repo, data, backend);
}

/// Lets the controller's coalesced notification run.
Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('a save shows up without reloading anything', () async {
    final (repo, data, backend) = await _loaded();
    backend.fetched.clear();
    var notified = 0;
    data.addListener(() => notified++);
    final version = data.version;

    final saved = await repo.saveProduct(_new, isNew: true);
    await _settle();

    expect(data.productById(saved.id)?.name, 'Widget');
    expect(data.productsFor('BIZ-1').map((p) => p.id), [saved.id]);
    expect(data.productsFor('BIZ-2'), isEmpty);
    expect(data.version, greaterThan(version));
    expect(notified, 1);
    // One scan for the new id (this fake has no counter), and no reload.
    expect(backend.fetched, [Collections.products]);
  });

  test('an edit replaces the record in place', () async {
    final (repo, data, _) = await _loaded();
    final saved = await repo.saveProduct(_new, isNew: true);
    await repo.saveProduct(saved.copyWith(name: 'Gadget'), isNew: false);
    await _settle();

    expect(data.products, hasLength(1));
    expect(data.productById(saved.id)?.name, 'Gadget');
  });

  test('a delete removes the record', () async {
    final (repo, data, _) = await _loaded();
    final saved = await repo.saveProduct(_new, isNew: true);
    await repo.deleteProduct(saved.id, known: saved);
    await _settle();

    expect(data.products, isEmpty);
    expect(data.productById(saved.id), isNull);
  });

  test('several saves in a row notify once', () async {
    final (repo, data, _) = await _loaded();
    var notified = 0;
    data.addListener(() => notified++);

    await Future.wait([
      repo.saveProduct(_new, isNew: true),
      repo.saveProduct(_new.copyWith(name: 'Two'), isNew: true),
    ]);
    await _settle();

    expect(data.products, hasLength(2));
    expect(
      data.products.map((p) => p.id).toSet(),
      hasLength(2),
      reason: 'two creates in flight must not share an id',
    );
    expect(notified, 1);
  });

  test('earlier lists stay unchanged (copy-on-write)', () async {
    final (repo, data, _) = await _loaded();
    final before = data.products;
    await repo.saveProduct(_new, isNew: true);
    await _settle();

    expect(before, isEmpty);
    expect(data.products, hasLength(1));
  });

  test('highestIdNumber follows saved records', () async {
    final (repo, data, _) = await _loaded();
    await repo.saveProduct(_new, isNew: true);
    await repo.saveProduct(_new, isNew: true);
    await _settle();

    expect(data.highestIdNumber('PROD'), 2);
  });

  test('a save made while loading is kept once the load lands', () async {
    final backend = _SlowBackend()
      ..put(
        Collections.businesses,
        'BIZ-1',
        const Business(id: 'BIZ-1', name: 'Acme').toMap(),
      );
    final repo = Repository(backend: backend, currentUser: _owner);
    final data = DataController(repo);

    backend.gate = Completer<void>();
    final loading = data.load();
    // Written straight to the store, as if saved just after the load read it.
    final saved = await () async {
      final gate = backend.gate;
      backend.gate = null;
      final p = await repo.saveProduct(_new, isNew: true);
      backend.store[Collections.products]!.remove(p.id);
      backend.gate = gate;
      return p;
    }();
    backend.gate!.complete();
    await loading;
    await _settle();

    expect(data.productById(saved.id), isNotNull);
  });

  test('a second load while one is running shares it', () async {
    final (_, data, _) = await _loaded();
    final a = data.load();
    final b = data.load();
    expect(identical(a, b), isTrue);
    await a;
  });
}
