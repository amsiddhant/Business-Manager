import '../core/enums.dart';
import '../core/utils/money.dart';
import 'audit_fields.dart';
import 'entity_comment.dart';

/// A product belonging to a business.
class Product {
  const Product({
    required this.id,
    required this.businessId,
    required this.name,
    this.description = '',
    this.buyingPrice = Money.zero,
    this.sellingPrice = Money.zero,
    this.url = '',
    this.sku = '',
    this.category = '',
    this.status = EntityStatus.active,
    this.comments = const [],
    this.audit = const AuditFields(),
  });

  final String id;
  final String businessId;
  final String name;
  final String description;

  /// Default cost to buy one unit.
  final Money buyingPrice;

  /// Default selling price per unit.
  final Money sellingPrice;

  final String url;
  final String sku;
  final String category;
  final EntityStatus status;

  /// Discussion thread embedded on the product document.
  final List<EntityComment> comments;

  final AuditFields audit;

  bool get isActive => status == EntityStatus.active;

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
        'businessId': businessId,
        'name': name,
        'description': description,
        'buyingPriceMinor': buyingPrice.minor,
        'sellingPriceMinor': sellingPrice.minor,
        'url': url,
        'sku': sku,
        'category': category,
        'status': status.wire,
        'comments': comments.map((c) => c.toMap()).toList(),
        ...audit.toMap(),
      };

  factory Product.fromMap(Map<String, dynamic> map) => Product(
        id: map['id'] as String? ?? '',
        businessId: map['businessId'] as String? ?? '',
        name: map['name'] as String? ?? '',
        description: map['description'] as String? ?? '',
        buyingPrice: Money((map['buyingPriceMinor'] as num?)?.toInt() ?? 0),
        sellingPrice: Money((map['sellingPriceMinor'] as num?)?.toInt() ?? 0),
        url: map['url'] as String? ?? '',
        sku: map['sku'] as String? ?? '',
        category: map['category'] as String? ?? '',
        status: EntityStatus.fromWire(map['status'] as String?),
        comments: EntityComment.listFrom(map['comments']),
        audit: AuditFields.fromMap(map),
      );

  Product copyWith({
    String? id,
    String? name,
    String? description,
    Money? buyingPrice,
    Money? sellingPrice,
    String? url,
    String? sku,
    String? category,
    EntityStatus? status,
    List<EntityComment>? comments,
    AuditFields? audit,
  }) =>
      Product(
        id: id ?? this.id,
        businessId: businessId,
        name: name ?? this.name,
        description: description ?? this.description,
        buyingPrice: buyingPrice ?? this.buyingPrice,
        sellingPrice: sellingPrice ?? this.sellingPrice,
        url: url ?? this.url,
        sku: sku ?? this.sku,
        category: category ?? this.category,
        status: status ?? this.status,
        comments: comments ?? this.comments,
        audit: audit ?? this.audit,
      );
}
