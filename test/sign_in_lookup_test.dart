import 'package:flutter_test/flutter_test.dart';
import 'package:salesforce_business_manager/core/enums.dart';
import 'package:salesforce_business_manager/data/backend.dart';
import 'package:salesforce_business_manager/data/repository.dart';
import 'package:salesforce_business_manager/models/app_user.dart';

import 'support/memory_backend.dart';

const _sam = AppUser(
  uid: 'u-sam',
  loginId: 'Sam.K',
  name: 'Sam',
  email: 'sam@example.com',
  role: UserRole.user,
);

void main() {
  group('Repository.emailForLogin (Firebase-style backend)', () {
    test('an email is used as typed, with no lookup', () async {
      final backend = LookupMemoryBackend();
      final repo = Repository(backend: backend);

      expect(await repo.emailForLogin(' sam@example.com '), 'sam@example.com');
      expect(backend.lookups, 0);
    });

    test('a login ID is found with one get of the sign-in index', () async {
      final backend = LookupMemoryBackend()
        ..put(Collections.loginIndex, 'sam.k', {'email': 'sam@example.com'});
      final repo = Repository(backend: backend);

      expect(await repo.emailForLogin('SAM.K'), 'sam@example.com');
      expect(backend.lookups, 1);
    });

    test('an unknown login ID is null, never a users listing', () async {
      final backend = LookupMemoryBackend();
      final repo = Repository(backend: backend);

      expect(await repo.emailForLogin('nobody'), isNull);
    });

    test('ids that cannot be document keys are rejected up front', () async {
      final backend = LookupMemoryBackend();
      final repo = Repository(backend: backend);

      for (final bad in ['', '  ', 'a/b', '..', '__x__']) {
        expect(await repo.emailForLogin(bad), isNull, reason: bad);
      }
      expect(backend.lookups, 0);
    });
  });

  group('Repository.emailForLogin (demo backend)', () {
    test('scans users, matching the login ID case-insensitively', () async {
      final backend = MemoryBackend()
        ..put(Collections.users, _sam.uid, _sam.toMap());
      final repo = Repository(backend: backend);

      expect(await repo.emailForLogin('sam.k'), 'sam@example.com');
      expect(await repo.emailForLogin('someone'), isNull);
    });
  });

  group('sign-in index upkeep', () {
    test('saving a user writes the index entry; renaming moves it', () async {
      const owner = AppUser(
        uid: 'owner',
        loginId: 'owner',
        name: 'Owner',
        email: 'owner@example.com',
        role: UserRole.owner,
      );
      final backend = BatchMemoryBackend()
        ..put(Collections.users, _sam.uid, _sam.toMap());
      final repo = Repository(backend: backend, currentUser: owner);

      await repo.saveUserProfile(_sam, previous: _sam);
      expect(backend.store[Collections.loginIndex]?['sam.k'], {
        'email': 'sam@example.com',
      });

      final renamed = _sam.copyWith(loginId: 'samk');
      await repo.saveUserProfile(renamed, previous: _sam);
      expect(backend.store[Collections.loginIndex]!.keys, ['samk']);
    });
  });
}
