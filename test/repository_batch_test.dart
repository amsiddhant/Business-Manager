import 'package:flutter_test/flutter_test.dart';
import 'package:salesforce_business_manager/core/enums.dart';
import 'package:salesforce_business_manager/data/backend.dart';
import 'package:salesforce_business_manager/data/backend_capabilities.dart';
import 'package:salesforce_business_manager/data/repo_change.dart';
import 'package:salesforce_business_manager/data/repository.dart';
import 'package:salesforce_business_manager/models/app_user.dart';
import 'package:salesforce_business_manager/models/business.dart';
import 'package:salesforce_business_manager/models/product.dart';

import 'support/memory_backend.dart';

const _owner = AppUser(
  uid: 'owner',
  loginId: 'owner',
  name: 'Owner',
  email: 'owner@example.com',
  role: UserRole.owner,
);

const _product = Product(id: '', businessId: 'BIZ-1', name: 'Widget');

T _seed<T extends MemoryBackend>(T backend) => backend
  ..put(
    Collections.businesses,
    'BIZ-1',
    const Business(id: 'BIZ-1', name: 'Acme').toMap(),
  );

void main() {
  group('Repository writes, batch backend', () {
    test('the record and its audit entry go in one commit', () async {
      final backend = _seed(BatchMemoryBackend());
      final repo = Repository(backend: backend, currentUser: _owner);

      final saved = await repo.saveProduct(_product, isNew: true);

      expect(backend.commits, hasLength(1));
      final collections = backend.commits.single
          .map((op) => op.collection)
          .toList();
      expect(collections, [Collections.products, Collections.auditLogs]);
      expect(backend.store[Collections.products]!.keys, [saved.id]);
      expect(backend.setDocCalls, 0);
    });

    test('a refused audit entry still saves the record, and says so', () async {
      final backend = _seed(BatchMemoryBackend())
        ..denyWrites.add(Collections.auditLogs);
      final repo = Repository(backend: backend, currentUser: _owner);

      final saved = await repo.saveProduct(_product, isNew: true);

      expect(backend.store[Collections.products]!.keys, [saved.id]);
      expect(backend.store[Collections.auditLogs], isNull);
      expect(backend.commits.single.single, isA<SetOp>());
      expect(repo.diagnostics.single, contains('auditLogs'));
    });

    test('a refused record is an error, not a silent skip', () async {
      final backend = _seed(BatchMemoryBackend())
        ..denyWrites.add(Collections.products);
      final repo = Repository(backend: backend, currentUser: _owner);

      await expectLater(
        repo.saveProduct(_product, isNew: true),
        throwsA(anything),
      );
      expect(backend.store[Collections.products], isNull);
    });

    test('delete with the known entity needs no read', () async {
      final backend = _seed(BatchMemoryBackend());
      final repo = Repository(backend: backend, currentUser: _owner);
      final saved = await repo.saveProduct(_product, isNew: true);
      backend.store[Collections.products]!.clear(); // a read would now fail

      await repo.deleteProduct(saved.id, known: saved);

      expect(backend.commits.last.first, isA<DeleteOp>());
    });
  });

  group('Repository writes, plain backend', () {
    test('writes one by one; a failing audit entry is ignored', () async {
      final backend = _seed(MemoryBackend())
        ..denyWrites.add(Collections.auditLogs);
      final repo = Repository(backend: backend, currentUser: _owner);

      final saved = await repo.saveProduct(_product, isNew: true);

      expect(backend.store[Collections.products]!.keys, [saved.id]);
      expect(saved.id, 'PROD-00001');
    });
  });

  group('Repository.changes', () {
    test('announces saves and deletes', () async {
      final backend = _seed(BatchMemoryBackend());
      final repo = Repository(backend: backend, currentUser: _owner);
      final changes = <RepoChange>[];
      final sub = repo.changes.listen(changes.add);

      final saved = await repo.saveProduct(_product, isNew: true);
      await repo.saveProduct(saved.copyWith(name: 'Gadget'), isNew: false);
      await repo.deleteProduct(saved.id, known: saved);
      await sub.cancel();

      expect(changes, hasLength(3));
      expect(changes[0], isA<Upserted>());
      expect(((changes[1] as Upserted).entity as Product).name, 'Gadget');
      expect(changes[2], isA<Removed>());
      expect(changes.map((c) => c.id).toSet(), {saved.id});
    });

    test('a failed write announces nothing', () async {
      final backend = _seed(BatchMemoryBackend())
        ..denyWrites.add(Collections.products);
      final repo = Repository(backend: backend, currentUser: _owner);
      final changes = <RepoChange>[];
      final sub = repo.changes.listen(changes.add);

      await expectLater(
        repo.saveProduct(_product, isNew: true),
        throwsA(anything),
      );
      await sub.cancel();

      expect(changes, isEmpty);
    });
  });

  group('Repository user cache', () {
    test('fetchUsersCached reads once until a user is written', () async {
      final backend = BatchMemoryBackend()
        ..put(Collections.users, 'owner', _owner.toMap());
      final repo = Repository(backend: backend, currentUser: _owner);

      final first = await repo.fetchUsersCached();
      backend.put(
        Collections.users,
        'u2',
        const AppUser(
          uid: 'u2',
          loginId: 'u2',
          name: 'Second',
          email: 'u2@example.com',
          role: UserRole.user,
        ).toMap(),
      );
      expect(await repo.fetchUsersCached(), same(first));

      await repo.saveUserProfile(
        _owner.copyWith(name: 'Renamed'),
        previous: _owner,
      );
      final after = await repo.fetchUsersCached();
      expect(after, hasLength(2));
    });
  });
}
