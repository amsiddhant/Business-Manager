import 'audit_fields.dart';

/// A single point-of-contact on a customer's side (e.g. their CEO, Tech Lead or
/// CSM). Stored as an embedded list inside the customer document — there is no
/// separate collection or security rule, so a contact inherits the exact
/// read/write authorization of the customer it belongs to (mirroring
/// [CustomerComment]).
///
/// Carries exactly the five business fields captured in the UI — [name],
/// [email], [designation], [number] and [description] — plus a stable [id] used
/// as the list key and a [createdAt] stamp. The display picture is not stored:
/// it is auto-generated from [name] via `InitialsAvatar` at render time.
class Contact {
  const Contact({
    required this.id,
    this.name = '',
    this.email = '',
    this.designation = '',
    this.number = '',
    this.description = '',
    this.createdAt,
  });

  final String id;
  final String name;
  final String email;
  final String designation;
  final String number;
  final String description;
  final DateTime? createdAt;

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'email': email,
        'designation': designation,
        'number': number,
        'description': description,
        if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
      };

  factory Contact.fromMap(Map<String, dynamic> map) => Contact(
        id: map['id'] as String? ?? '',
        name: map['name'] as String? ?? '',
        email: map['email'] as String? ?? '',
        designation: map['designation'] as String? ?? '',
        number: map['number'] as String? ?? '',
        description: map['description'] as String? ?? '',
        createdAt: parseDate(map['createdAt']),
      );

  /// Reads a `contacts` list off a document map, tolerating a missing/legacy
  /// field. Malformed entries are skipped rather than throwing.
  static List<Contact> listFrom(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((m) => Contact.fromMap(Map<String, dynamic>.from(m)))
        .toList();
  }

  Contact copyWith({
    String? name,
    String? email,
    String? designation,
    String? number,
    String? description,
    DateTime? createdAt,
  }) =>
      Contact(
        id: id,
        name: name ?? this.name,
        email: email ?? this.email,
        designation: designation ?? this.designation,
        number: number ?? this.number,
        description: description ?? this.description,
        createdAt: createdAt ?? this.createdAt,
      );
}
