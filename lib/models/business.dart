import '../core/enums.dart';
import 'audit_fields.dart';
import 'entity_comment.dart';

/// Preset business types offered in the (searchable) Business Type field. The
/// field itself stores a free-form string, so these are suggestions rather than
/// a closed enum — legacy/imported values outside this list are preserved.
const List<String> kBusinessTypes = [
  'SaaS',
  'E-commerce',
  'Retail',
  'Wholesale',
  'Manufacturing',
  'Services',
  'Agency',
  'Consulting',
  'Education',
  'Healthcare',
  'Real Estate',
  'Hospitality',
  'Logistics',
  'Media',
  'Non-profit',
  'Other',
];

/// A business/organisation. Top-level owner of products, campaigns, orders,
/// expenses and dealers.
class Business {
  const Business({
    required this.id,
    required this.name,
    this.description = '',
    this.type = '',
    this.website = '',
    this.currency = CurrencyCode.inr,
    this.country = 'India',
    this.size = CompanySize.small,
    this.status = EntityStatus.active,
    this.facebookUrl = '',
    this.instagramUrl = '',
    this.xUrl = '',
    this.pinterestUrl = '',
    this.linkedinUrl = '',
    this.redditUrl = '',
    this.otherSocialUrl = '',
    this.comments = const [],
    this.audit = const AuditFields(),
  });

  final String id;
  final String name;
  final String description;
  final String type;
  final String website;
  final CurrencyCode currency;
  final String country;
  final CompanySize size;
  final EntityStatus status;

  // Social media presence.
  final String facebookUrl;
  final String instagramUrl;
  final String xUrl;
  final String pinterestUrl;
  final String linkedinUrl;
  final String redditUrl;
  final String otherSocialUrl;

  /// Discussion thread embedded on the business document.
  final List<EntityComment> comments;

  final AuditFields audit;

  bool get isActive => status == EntityStatus.active;

  /// Social links as (label, url) pairs, in a stable display order, skipping
  /// the ones that are blank.
  List<(String, String)> get socialLinks => [
        ('Facebook', facebookUrl),
        ('Instagram', instagramUrl),
        ('X', xUrl),
        ('Pinterest', pinterestUrl),
        ('LinkedIn', linkedinUrl),
        ('Reddit', redditUrl),
        ('Other', otherSocialUrl),
      ].where((e) => e.$2.trim().isNotEmpty).toList();

  /// Newest signal of activity: latest comment, else the updated/created audit
  /// timestamp. Powers detail views' "Last Activity" card.
  DateTime? get lastActivityAt {
    DateTime? newest;
    for (final c in comments) {
      final d = c.createdAt;
      if (d != null && (newest == null || d.isAfter(newest))) newest = d;
    }
    return newest ?? audit.updatedAt ?? audit.createdAt;
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'description': description,
        'type': type,
        'website': website,
        'currency': currency.wire,
        'country': country,
        'size': size.wire,
        'status': status.wire,
        'facebookUrl': facebookUrl,
        'instagramUrl': instagramUrl,
        'xUrl': xUrl,
        'pinterestUrl': pinterestUrl,
        'linkedinUrl': linkedinUrl,
        'redditUrl': redditUrl,
        'otherSocialUrl': otherSocialUrl,
        'comments': comments.map((c) => c.toMap()).toList(),
        ...audit.toMap(),
      };

  factory Business.fromMap(Map<String, dynamic> map) => Business(
        id: map['id'] as String? ?? '',
        name: map['name'] as String? ?? '',
        description: map['description'] as String? ?? '',
        type: map['type'] as String? ?? '',
        website: map['website'] as String? ?? '',
        currency: CurrencyCode.fromWire(map['currency'] as String?),
        country: map['country'] as String? ?? '',
        size: CompanySize.fromWire(map['size'] as String?),
        status: EntityStatus.fromWire(map['status'] as String?),
        facebookUrl: map['facebookUrl'] as String? ?? '',
        instagramUrl: map['instagramUrl'] as String? ?? '',
        xUrl: map['xUrl'] as String? ?? '',
        pinterestUrl: map['pinterestUrl'] as String? ?? '',
        linkedinUrl: map['linkedinUrl'] as String? ?? '',
        redditUrl: map['redditUrl'] as String? ?? '',
        otherSocialUrl: map['otherSocialUrl'] as String? ?? '',
        comments: EntityComment.listFrom(map['comments']),
        audit: AuditFields.fromMap(map),
      );

  Business copyWith({
    String? id,
    String? name,
    String? description,
    String? type,
    String? website,
    CurrencyCode? currency,
    String? country,
    CompanySize? size,
    EntityStatus? status,
    String? facebookUrl,
    String? instagramUrl,
    String? xUrl,
    String? pinterestUrl,
    String? linkedinUrl,
    String? redditUrl,
    String? otherSocialUrl,
    List<EntityComment>? comments,
    AuditFields? audit,
  }) =>
      Business(
        id: id ?? this.id,
        name: name ?? this.name,
        description: description ?? this.description,
        type: type ?? this.type,
        website: website ?? this.website,
        currency: currency ?? this.currency,
        country: country ?? this.country,
        size: size ?? this.size,
        status: status ?? this.status,
        facebookUrl: facebookUrl ?? this.facebookUrl,
        instagramUrl: instagramUrl ?? this.instagramUrl,
        xUrl: xUrl ?? this.xUrl,
        pinterestUrl: pinterestUrl ?? this.pinterestUrl,
        linkedinUrl: linkedinUrl ?? this.linkedinUrl,
        redditUrl: redditUrl ?? this.redditUrl,
        otherSocialUrl: otherSocialUrl ?? this.otherSocialUrl,
        comments: comments ?? this.comments,
        audit: audit ?? this.audit,
      );
}
