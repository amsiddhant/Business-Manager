import '../core/enums.dart';
import '../core/utils/money.dart';
import 'audit_fields.dart';

/// A product order / sale.
///
/// Financial fields are stored so that historical orders retain the buying and
/// selling prices in force at the time of the order (rather than tracking the
/// current product price). Revenue and cost are derived via getters that never
/// use floating point on stored money.
class Order {
  const Order({
    required this.id,
    required this.businessId,
    required this.productId,
    required this.productName,
    this.orderDate,
    this.quantity = 1,
    this.sellingCost = Money.zero,
    this.discount = Money.zero,
    this.shippingRevenue = Money.zero,
    this.otherRevenue = Money.zero,
    this.buyingCost = Money.zero,
    this.marketingAllocation = Money.zero,
    this.status = OrderStatus.pending,
    this.customerReference = '',
    this.notes = '',
    this.audit = const AuditFields(),
  });

  final String id;
  final String businessId;
  final String productId;
  final String productName;
  final DateTime? orderDate;
  final int quantity;

  /// Selling price per unit at time of order.
  final Money sellingCost;
  final Money discount;
  final Money shippingRevenue;
  final Money otherRevenue;

  /// Buying/purchase cost per unit at time of order.
  final Money buyingCost;

  /// Optional marketing cost directly allocated to this order.
  final Money marketingAllocation;

  final OrderStatus status;
  final String customerReference;
  final String notes;
  final AuditFields audit;

  /// Product revenue = selling cost × quantity.
  Money get productRevenue => sellingCost * quantity;

  /// Total revenue = product revenue + shipping + other − discount.
  Money get totalRevenue =>
      productRevenue + shippingRevenue + otherRevenue - discount;

  /// Product cost = buying price × quantity.
  Money get productCost => buyingCost * quantity;

  /// Gross profit for this order (before marketing / operating expenses).
  Money get grossProfit => totalRevenue - productCost;

  /// Whether this order's revenue is recognised (cancelled/returned excluded).
  bool get isRecognised => status.contributesToRevenue;

  /// Revenue that actually counts towards reporting.
  Money get recognisedRevenue => isRecognised ? totalRevenue : Money.zero;
  Money get recognisedProductCost => isRecognised ? productCost : Money.zero;

  Map<String, dynamic> toMap() => {
        'id': id,
        'businessId': businessId,
        'productId': productId,
        'productName': productName,
        if (orderDate != null) 'orderDate': orderDate!.toIso8601String(),
        'quantity': quantity,
        'sellingCostMinor': sellingCost.minor,
        'discountMinor': discount.minor,
        'shippingRevenueMinor': shippingRevenue.minor,
        'otherRevenueMinor': otherRevenue.minor,
        'buyingCostMinor': buyingCost.minor,
        'marketingAllocationMinor': marketingAllocation.minor,
        'status': status.wire,
        'customerReference': customerReference,
        'notes': notes,
        ...audit.toMap(),
      };

  factory Order.fromMap(Map<String, dynamic> map) => Order(
        id: map['id'] as String? ?? '',
        businessId: map['businessId'] as String? ?? '',
        productId: map['productId'] as String? ?? '',
        productName: map['productName'] as String? ?? '',
        orderDate: parseDate(map['orderDate']),
        quantity: (map['quantity'] as num?)?.toInt() ?? 1,
        sellingCost: Money((map['sellingCostMinor'] as num?)?.toInt() ?? 0),
        discount: Money((map['discountMinor'] as num?)?.toInt() ?? 0),
        shippingRevenue:
            Money((map['shippingRevenueMinor'] as num?)?.toInt() ?? 0),
        otherRevenue: Money((map['otherRevenueMinor'] as num?)?.toInt() ?? 0),
        buyingCost: Money((map['buyingCostMinor'] as num?)?.toInt() ?? 0),
        marketingAllocation:
            Money((map['marketingAllocationMinor'] as num?)?.toInt() ?? 0),
        status: OrderStatus.fromWire(map['status'] as String?),
        customerReference: map['customerReference'] as String? ?? '',
        notes: map['notes'] as String? ?? '',
        audit: AuditFields.fromMap(map),
      );

  Order copyWith({
    String? productId,
    String? productName,
    DateTime? orderDate,
    int? quantity,
    Money? sellingCost,
    Money? discount,
    Money? shippingRevenue,
    Money? otherRevenue,
    Money? buyingCost,
    Money? marketingAllocation,
    OrderStatus? status,
    String? customerReference,
    String? notes,
    AuditFields? audit,
  }) =>
      Order(
        id: id,
        businessId: businessId,
        productId: productId ?? this.productId,
        productName: productName ?? this.productName,
        orderDate: orderDate ?? this.orderDate,
        quantity: quantity ?? this.quantity,
        sellingCost: sellingCost ?? this.sellingCost,
        discount: discount ?? this.discount,
        shippingRevenue: shippingRevenue ?? this.shippingRevenue,
        otherRevenue: otherRevenue ?? this.otherRevenue,
        buyingCost: buyingCost ?? this.buyingCost,
        marketingAllocation: marketingAllocation ?? this.marketingAllocation,
        status: status ?? this.status,
        customerReference: customerReference ?? this.customerReference,
        notes: notes ?? this.notes,
        audit: audit ?? this.audit,
      );
}
