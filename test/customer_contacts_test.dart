import 'package:flutter_test/flutter_test.dart';
import 'package:salesforce_business_manager/core/app_exception.dart';
import 'package:salesforce_business_manager/core/enums.dart';
import 'package:salesforce_business_manager/core/permissions.dart';
import 'package:salesforce_business_manager/data/backend.dart';
import 'package:salesforce_business_manager/data/repository.dart';
import 'package:salesforce_business_manager/models/app_user.dart';
import 'package:salesforce_business_manager/models/contact.dart';
import 'package:salesforce_business_manager/models/customer.dart';
import 'package:salesforce_business_manager/view_models/customer_contacts_view_model.dart';

/// Unit tests for the customer-side Contacts feature: the embedded [Contact]
/// value type (map round-trip, legacy tolerance, copyWith), its embedding on
/// the [Customer] document, and the [CustomerContactsViewModel] — both its pure
/// list transforms and its persistence path through the repository (which must
/// keep enforcing the customer's edit permission, since a contact is just a
/// customer-document update).
void main() {
  group('Contact map round-trip', () {
    test('toMap/fromMap preserves every field', () {
      final c = Contact(
        id: 'ct1',
        name: 'Jane Cooper',
        email: 'jane@acme.com',
        designation: 'CEO',
        number: '+91 98765 43210',
        description: 'Primary decision maker',
        createdAt: DateTime(2026, 9, 20, 14, 30),
      );
      final restored = Contact.fromMap(c.toMap());
      expect(restored.id, 'ct1');
      expect(restored.name, 'Jane Cooper');
      expect(restored.email, 'jane@acme.com');
      expect(restored.designation, 'CEO');
      expect(restored.number, '+91 98765 43210');
      expect(restored.description, 'Primary decision maker');
      expect(restored.createdAt, DateTime(2026, 9, 20, 14, 30));
    });

    test('omits createdAt from the map when null', () {
      const c = Contact(id: 'ct1', name: 'No Date');
      expect(c.toMap().containsKey('createdAt'), isFalse);
      expect(Contact.fromMap(c.toMap()).createdAt, isNull);
    });

    test('defaults every string field for a sparse/legacy map', () {
      final c = Contact.fromMap({'id': 'ct9'});
      expect(c.id, 'ct9');
      expect(c.name, '');
      expect(c.email, '');
      expect(c.designation, '');
      expect(c.number, '');
      expect(c.description, '');
      expect(c.createdAt, isNull);
    });
  });

  group('Contact.listFrom', () {
    test('decodes a list of maps', () {
      final list = Contact.listFrom([
        {'id': 'ct1', 'name': 'A'},
        {'id': 'ct2', 'name': 'B'},
      ]);
      expect(list.map((c) => c.id).toList(), ['ct1', 'ct2']);
      expect(list.map((c) => c.name).toList(), ['A', 'B']);
    });

    test('returns const empty for a missing/non-list value', () {
      expect(Contact.listFrom(null), isEmpty);
      expect(Contact.listFrom('nope'), isEmpty);
      expect(Contact.listFrom(42), isEmpty);
    });

    test('skips malformed (non-map) entries rather than throwing', () {
      final list = Contact.listFrom([
        {'id': 'ct1', 'name': 'Keep'},
        'garbage',
        null,
        42,
      ]);
      expect(list.length, 1);
      expect(list.single.id, 'ct1');
    });
  });

  group('Contact.copyWith', () {
    test('overrides only the given fields and keeps the id', () {
      const c = Contact(id: 'ct1', name: 'Old', email: 'old@x.com');
      final updated = c.copyWith(name: 'New');
      expect(updated.id, 'ct1'); // id is never replaced
      expect(updated.name, 'New');
      expect(updated.email, 'old@x.com'); // untouched
    });

    test('preserves createdAt when not supplied', () {
      final c = Contact(id: 'ct1', createdAt: DateTime(2026, 1, 1));
      expect(c.copyWith(name: 'x').createdAt, DateTime(2026, 1, 1));
    });
  });

  group('Customer embeds contacts', () {
    test('round-trips contacts through toMap/fromMap', () {
      const c = Customer(
        id: 'CUST-00001',
        businessIds: ['BIZ-1'],
        name: 'Acme',
        contacts: [
          Contact(id: 'ct1', name: 'Jane', designation: 'CEO'),
          Contact(id: 'ct2', name: 'John', designation: 'CTO'),
        ],
      );
      final restored = Customer.fromMap(c.toMap());
      expect(restored.contacts.map((x) => x.id).toList(), ['ct1', 'ct2']);
      expect(restored.contacts.first.designation, 'CEO');
    });

    test('defaults to an empty list for a legacy customer document', () {
      final c = Customer.fromMap({
        'id': 'CUST-00001',
        'businessIds': ['BIZ-1'],
        'name': 'Legacy',
      });
      expect(c.contacts, isEmpty);
    });

    test('copyWith replaces the contacts list', () {
      const c = Customer(id: 'CUST-00001', businessIds: ['BIZ-1'], name: 'Acme');
      final updated =
          c.copyWith(contacts: const [Contact(id: 'ct1', name: 'Jane')]);
      expect(updated.contacts.single.name, 'Jane');
      // Original is untouched (immutability).
      expect(c.contacts, isEmpty);
    });
  });

  group('CustomerContactsViewModel pure transforms', () {
    const a = Contact(id: 'ct1', name: 'A');
    const b = Contact(id: 'ct2', name: 'B');

    test('withAdded appends preserving order', () {
      final r = CustomerContactsViewModel.withAdded(const [a], b);
      expect(r.map((c) => c.id).toList(), ['ct1', 'ct2']);
    });

    test('withUpdated replaces the matching id in place', () {
      const edited = Contact(id: 'ct2', name: 'B-edited');
      final r = CustomerContactsViewModel.withUpdated(const [a, b], edited);
      expect(r.map((c) => c.id).toList(), ['ct1', 'ct2']); // order kept
      expect(r[1].name, 'B-edited');
    });

    test('withUpdated leaves the list unchanged when no id matches', () {
      const ghost = Contact(id: 'ct9', name: 'Ghost');
      final r = CustomerContactsViewModel.withUpdated(const [a, b], ghost);
      expect(r.map((c) => c.id).toList(), ['ct1', 'ct2']);
    });

    test('withRemoved drops only the matching id', () {
      final r = CustomerContactsViewModel.withRemoved(const [a, b], 'ct1');
      expect(r.map((c) => c.id).toList(), ['ct2']);
    });
  });

  group('CustomerContactsViewModel.buildDraft', () {
    test('trims every field and stamps id + createdAt', () {
      final vm = CustomerContactsViewModel(
        Repository(backend: _FakeBackend(), currentUser: _owner()),
        idFactory: () => 'ct-fixed',
      );
      final draft = vm.buildDraft(
        name: '  Jane  ',
        email: '  jane@acme.com ',
        designation: ' CEO ',
        number: ' 123 ',
        description: '  notes ',
      );
      expect(draft.id, 'ct-fixed');
      expect(draft.name, 'Jane');
      expect(draft.email, 'jane@acme.com');
      expect(draft.designation, 'CEO');
      expect(draft.number, '123');
      expect(draft.description, 'notes');
      expect(draft.createdAt, isNotNull);
    });
  });

  group('CustomerContactsViewModel persistence', () {
    late _FakeBackend backend;

    setUp(() {
      backend = _FakeBackend();
      backend.store['customers'] = {
        'CUST-00001': const Customer(
          id: 'CUST-00001',
          businessIds: ['BIZ-1'],
          name: 'Acme',
        ).toMap(),
      };
    });

    Customer stored() =>
        Customer.fromMap(backend.store['customers']!['CUST-00001']!);

    test('add persists the new contact onto the customer document', () async {
      final vm = CustomerContactsViewModel(
          Repository(backend: backend, currentUser: _owner()));
      const customer = Customer(
          id: 'CUST-00001', businessIds: ['BIZ-1'], name: 'Acme');
      const contact = Contact(id: 'ct1', name: 'Jane', designation: 'CEO');

      final saved = await vm.add(customer, contact);
      expect(saved.contacts.single.id, 'ct1');
      expect(stored().contacts.single.name, 'Jane');
    });

    test('update replaces an existing contact', () async {
      final vm = CustomerContactsViewModel(
          Repository(backend: backend, currentUser: _owner()));
      const customer = Customer(
        id: 'CUST-00001',
        businessIds: ['BIZ-1'],
        name: 'Acme',
        contacts: [Contact(id: 'ct1', name: 'Jane', designation: 'CEO')],
      );

      await vm.update(
          customer, const Contact(id: 'ct1', name: 'Jane', designation: 'CFO'));
      expect(stored().contacts.single.designation, 'CFO');
    });

    test('remove deletes the contact', () async {
      final vm = CustomerContactsViewModel(
          Repository(backend: backend, currentUser: _owner()));
      const customer = Customer(
        id: 'CUST-00001',
        businessIds: ['BIZ-1'],
        name: 'Acme',
        contacts: [
          Contact(id: 'ct1', name: 'Jane'),
          Contact(id: 'ct2', name: 'John'),
        ],
      );

      await vm.remove(customer, 'ct1');
      expect(stored().contacts.map((c) => c.id).toList(), ['ct2']);
    });

    test('a user without editCustomer is denied (enforced in the service '
        'layer, not just the UI)', () async {
      final vm = CustomerContactsViewModel(
          Repository(backend: backend, currentUser: _noEditUser()));
      const customer = Customer(
          id: 'CUST-00001', businessIds: ['BIZ-1'], name: 'Acme');

      expect(
        () => vm.add(customer, const Contact(id: 'ct1', name: 'Jane')),
        throwsA(isA<PermissionDeniedException>()),
      );
    });
  });
}

// ---------------------------------------------------------------------------

/// A minimal in-memory [Backend] — only the document read/write methods used by
/// [Repository.saveCustomer] are meaningful; the auth surface throws.
class _FakeBackend implements Backend {
  final Map<String, Map<String, Map<String, dynamic>>> store = {};

  @override
  String get label => 'Fake';

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

/// A USER with edit rights explicitly revoked — proves the service layer, not
/// the UI, is what actually blocks the write. (By default a USER *can* edit
/// customers, so contact CRUD is permitted for the standard role.)
AppUser _noEditUser() => const AppUser(
      uid: 'user',
      loginId: 'user',
      name: 'Viewer',
      email: 'user@example.com',
      role: UserRole.user,
      assignedBusinessIds: ['BIZ-1'],
      revokedPermissions: {Permission.editCustomer},
    );
