import '../core/enums.dart';
import '../core/utils/money.dart';
import 'audit_fields.dart';

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
  final AuditFields audit;

  bool get isActive => status == EntityStatus.active;

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
        audit: AuditFields.fromMap(map),
      );

  Product copyWith({
    String? name,
    String? description,
    Money? buyingPrice,
    Money? sellingPrice,
    String? url,
    String? sku,
    String? category,
    EntityStatus? status,
    AuditFields? audit,
  }) =>
      Product(
        id: id,
        businessId: businessId,
        name: name ?? this.name,
        description: description ?? this.description,
        buyingPrice: buyingPrice ?? this.buyingPrice,
        sellingPrice: sellingPrice ?? this.sellingPrice,
        url: url ?? this.url,
        sku: sku ?? this.sku,
        category: category ?? this.category,
        status: status ?? this.status,
        audit: audit ?? this.audit,
      );
}
