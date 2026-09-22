import '../core/enums.dart';
import '../core/utils/date_utils.dart';
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
    this.lifecycle = BusinessLifecycle.active,
    this.foundedBy = '',
    this.ownedBy = '',
    this.startDate,
    this.endDate,
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

  /// Operational lifecycle — trading vs. wound down. Independent of [status],
  /// which governs archive/visibility.
  final BusinessLifecycle lifecycle;

  /// Who founded the business (free-form name).
  final String foundedBy;

  /// Who currently owns the business (free-form name).
  final String ownedBy;

  /// When the business commenced trading. Anchors the tenure calculation.
  final DateTime? startDate;

  /// When the business ceased trading. Only meaningful when [lifecycle] is
  /// closed; caps the tenure calculation.
  final DateTime? endDate;

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

  /// True when the business has been wound down.
  bool get isClosed => lifecycle.isClosed;

  /// The end of the tenure window: the closure date for a closed business,
  /// otherwise "now". Falls back to [asOf] when a closed business has no
  /// recorded [endDate].
  DateTime _tenureEnd(DateTime asOf) =>
      isClosed ? (endDate ?? asOf) : asOf;

  /// Calendar-accurate operating span from [startDate] to the tenure end
  /// (closure date if closed, else [asOf]). Returns null when no start date is
  /// recorded, so callers can show a "set a start date" affordance.
  ///
  /// [asOf] is injected (rather than reading the clock here) so the value is
  /// pure and testable; UI passes `DateTime.now()`.
  TimeRemaining? tenure(DateTime asOf) {
    final start = startDate;
    if (start == null) return null;
    return TimeRemaining.between(start, _tenureEnd(asOf));
  }

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
        'lifecycle': lifecycle.wire,
        'foundedBy': foundedBy,
        'ownedBy': ownedBy,
        if (startDate != null) 'startDate': startDate!.toIso8601String(),
        if (endDate != null) 'endDate': endDate!.toIso8601String(),
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
        lifecycle: BusinessLifecycle.fromWire(map['lifecycle'] as String?),
        foundedBy: map['foundedBy'] as String? ?? '',
        ownedBy: map['ownedBy'] as String? ?? '',
        startDate: parseDate(map['startDate']),
        endDate: parseDate(map['endDate']),
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
    BusinessLifecycle? lifecycle,
    String? foundedBy,
    String? ownedBy,
    DateTime? startDate,
    DateTime? endDate,
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
        lifecycle: lifecycle ?? this.lifecycle,
        foundedBy: foundedBy ?? this.foundedBy,
        ownedBy: ownedBy ?? this.ownedBy,
        startDate: startDate ?? this.startDate,
        endDate: endDate ?? this.endDate,
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
