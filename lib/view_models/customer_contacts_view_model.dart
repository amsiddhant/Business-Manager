import '../data/repository.dart';
import '../models/contact.dart';
import '../models/customer.dart';

/// View model for the customer-side Contacts section on the Customer Details
/// page. Encapsulates the add / update / delete logic so the widget stays dumb
/// and the mutation rules are unit-testable without a UI.
///
/// A contact is embedded in the customer document (see [Customer.contacts]), so
/// every mutation is expressed as a whole-customer save through
/// [Repository.saveCustomer] with `isNew: false`. That reuses the customer's
/// existing permission gate ([Permission.editCustomer]), audit stamping and
/// business-scope authorization — no new collection, permission or Firestore
/// rule is introduced. Callers refresh the [DataController] afterwards.
///
/// The pure list transforms ([withAdded]/[withUpdated]/[withRemoved]) are static
/// so they can be exercised directly in tests; the instance methods layer
/// persistence on top.
class CustomerContactsViewModel {
  CustomerContactsViewModel(this._repo, {String Function()? idFactory})
      : _idFactory = idFactory ?? _defaultIdFactory;

  final Repository _repo;

  /// Mints a contact id. Injectable so tests are deterministic; production uses
  /// a microsecond timestamp (matching the embedded-comment convention).
  final String Function() _idFactory;

  static String _defaultIdFactory() =>
      'ct${DateTime.now().microsecondsSinceEpoch}';

  /// Builds a fresh [Contact] from field values, stamping a new id and
  /// [Contact.createdAt]. Values are trimmed so stored data stays clean.
  Contact buildDraft({
    required String name,
    required String email,
    required String designation,
    required String number,
    required String description,
  }) =>
      Contact(
        id: _idFactory(),
        name: name.trim(),
        email: email.trim(),
        designation: designation.trim(),
        number: number.trim(),
        description: description.trim(),
        createdAt: DateTime.now(),
      );

  /// Appends [contact] and persists. Returns the saved customer.
  Future<Customer> add(Customer customer, Contact contact) =>
      _persist(customer, withAdded(customer.contacts, contact));

  /// Replaces the contact sharing [contact]'s id (preserving order) and
  /// persists. If no contact matches, the list is left unchanged.
  Future<Customer> update(Customer customer, Contact contact) =>
      _persist(customer, withUpdated(customer.contacts, contact));

  /// Removes the contact with [contactId] and persists.
  Future<Customer> remove(Customer customer, String contactId) =>
      _persist(customer, withRemoved(customer.contacts, contactId));

  Future<Customer> _persist(Customer customer, List<Contact> contacts) =>
      _repo.saveCustomer(customer.copyWith(contacts: contacts), isNew: false);

  // ---- Pure list transforms (unit-testable) ---------------------------------

  static List<Contact> withAdded(List<Contact> existing, Contact contact) =>
      [...existing, contact];

  static List<Contact> withUpdated(List<Contact> existing, Contact contact) =>
      [for (final c in existing) c.id == contact.id ? contact : c];

  static List<Contact> withRemoved(List<Contact> existing, String contactId) =>
      existing.where((c) => c.id != contactId).toList();
}
