import '../core/enums.dart';
import 'audit_fields.dart';

/// A single comment on a customer's activity thread. Stored as an embedded list
/// inside the customer document (no separate collection / rules needed).
class CustomerComment {
  const CustomerComment({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.text,
    this.createdAt,
  });

  final String id;
  final String authorId;
  final String authorName;
  final String text;
  final DateTime? createdAt;

  Map<String, dynamic> toMap() => {
        'id': id,
        'authorId': authorId,
        'authorName': authorName,
        'text': text,
        if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
      };

  factory CustomerComment.fromMap(Map<String, dynamic> map) => CustomerComment(
        id: map['id'] as String? ?? '',
        authorId: map['authorId'] as String? ?? '',
        authorName: map['authorName'] as String? ?? '',
        text: map['text'] as String? ?? '',
        createdAt: parseDate(map['createdAt']),
      );
}

/// A customer / lead belonging to a business. Tracks CRM contact details and a
/// deal pipeline stage, plus an embedded activity comment thread.
class Customer {
  const Customer({
    required this.id,
    required this.businessId,
    required this.name,
    this.businessType = '',
    this.size = CompanySize.small,
    this.contactNo = '',
    this.email = '',
    this.city = '',
    this.state = '',
    this.country = 'India',
    this.socialMedia = '',
    this.dealStatus = DealStatus.pending,
    this.description = '',
    this.comments = const [],
    this.audit = const AuditFields(),
  });

  final String id;
  final String businessId;
  final String name;
  final String businessType;
  final CompanySize size;
  final String contactNo;
  final String email;
  final String city;
  final String state;
  final String country;
  final String socialMedia;
  final DealStatus dealStatus;
  final String description;
  final List<CustomerComment> comments;
  final AuditFields audit;

  /// A single-line location summary (e.g. "Mumbai, Maharashtra, India").
  String get location => [city, state, country]
      .where((p) => p.trim().isNotEmpty)
      .join(', ');

  /// The most recent activity date: newest comment, else last update/creation.
  DateTime? get lastActivityAt {
    DateTime? latest = audit.updatedAt ?? audit.createdAt;
    for (final c in comments) {
      final d = c.createdAt;
      if (d != null && (latest == null || d.isAfter(latest))) latest = d;
    }
    return latest;
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'businessId': businessId,
        'name': name,
        'businessType': businessType,
        'size': size.wire,
        'contactNo': contactNo,
        'email': email,
        'city': city,
        'state': state,
        'country': country,
        'socialMedia': socialMedia,
        'dealStatus': dealStatus.wire,
        'description': description,
        'comments': comments.map((c) => c.toMap()).toList(),
        ...audit.toMap(),
      };

  factory Customer.fromMap(Map<String, dynamic> map) => Customer(
        id: map['id'] as String? ?? '',
        businessId: map['businessId'] as String? ?? '',
        name: map['name'] as String? ?? '',
        businessType: map['businessType'] as String? ?? '',
        size: CompanySize.fromWire(map['size'] as String?),
        contactNo: map['contactNo'] as String? ?? '',
        email: map['email'] as String? ?? '',
        city: map['city'] as String? ?? '',
        state: map['state'] as String? ?? '',
        country: map['country'] as String? ?? 'India',
        socialMedia: map['socialMedia'] as String? ?? '',
        dealStatus: DealStatus.fromWire(map['dealStatus'] as String?),
        description: map['description'] as String? ?? '',
        comments: [
          for (final c in (map['comments'] as List<dynamic>? ?? const []))
            CustomerComment.fromMap(Map<String, dynamic>.from(c as Map)),
        ],
        audit: AuditFields.fromMap(map),
      );

  Customer copyWith({
    String? name,
    String? businessType,
    CompanySize? size,
    String? contactNo,
    String? email,
    String? city,
    String? state,
    String? country,
    String? socialMedia,
    DealStatus? dealStatus,
    String? description,
    List<CustomerComment>? comments,
    AuditFields? audit,
  }) =>
      Customer(
        id: id,
        businessId: businessId,
        name: name ?? this.name,
        businessType: businessType ?? this.businessType,
        size: size ?? this.size,
        contactNo: contactNo ?? this.contactNo,
        email: email ?? this.email,
        city: city ?? this.city,
        state: state ?? this.state,
        country: country ?? this.country,
        socialMedia: socialMedia ?? this.socialMedia,
        dealStatus: dealStatus ?? this.dealStatus,
        description: description ?? this.description,
        comments: comments ?? this.comments,
        audit: audit ?? this.audit,
      );
}
