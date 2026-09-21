import '../core/enums.dart';
import '../core/utils/money.dart';
import 'audit_fields.dart';
import 'entity_comment.dart';

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
    this.refundAmount = Money.zero,
    this.refundDate,
    this.customerReference = '',
    this.notes = '',
    this.comments = const [],
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

  /// Amount refunded to the customer for a returned/refunded order. Supports
  /// both partial (< [totalRevenue]) and full (== [totalRevenue]) refunds. Zero
  /// for orders that were never returned.
  final Money refundAmount;

  /// When the refund was issued (null when not refunded).
  final DateTime? refundDate;

  final String customerReference;
  final String notes;

  /// Discussion thread embedded on the order document.
  final List<EntityComment> comments;

  final AuditFields audit;

  /// Product revenue = selling cost × quantity.
  Money get productRevenue => sellingCost * quantity;

  /// Total (gross, pre-refund) revenue = product revenue + shipping + other −
  /// discount. This is the amount originally billed for the order.
  Money get totalRevenue =>
      productRevenue + shippingRevenue + otherRevenue - discount;

  /// Product cost = buying price × quantity (gross, pre-refund).
  Money get productCost => buyingCost * quantity;

  /// Gross profit for this order (before marketing / operating expenses),
  /// based on gross figures. See [recognisedGrossProfit] for the net-of-refund
  /// figure used in profit calculations.
  Money get grossProfit => totalRevenue - productCost;

  /// Whether this order contributes to recognised revenue. Cancelled orders are
  /// fully excluded; returned/refunded orders still contribute their retained
  /// (non-refunded) portion, so they remain recognised.
  bool get isRecognised => status.contributesToRevenue;

  /// True when this order has been returned (and therefore carries a refund).
  bool get isRefunded => status == OrderStatus.returned;

  /// The refund actually applied to this order.
  ///
  /// Only returned orders refund anything. A returned order with no explicit
  /// [refundAmount] recorded (e.g. legacy data, or a plain "mark returned")
  /// is treated as a **full** refund — matching the historical behaviour where
  /// returned orders were excluded entirely. An explicit positive amount is a
  /// partial (or full) refund, clamped to never exceed total revenue.
  Money get effectiveRefund {
    if (status != OrderStatus.returned) return Money.zero;
    final full = totalRevenue;
    if (refundAmount <= Money.zero) return full;
    return refundAmount > full ? full : refundAmount;
  }

  /// The refunded fraction of the order's revenue in the range [0, 1]. Used to
  /// proportionally reverse product cost (returned units are assumed
  /// restocked). Guards against zero/negative total revenue.
  double get refundRatio {
    if (!isRefunded) return 0;
    if (totalRevenue.minor <= 0) return 1; // fully refunded by definition
    final ratio = effectiveRefund.minor / totalRevenue.minor;
    return ratio > 1 ? 1 : ratio;
  }

  /// Revenue that actually counts towards reporting: gross revenue less any
  /// refund. Cancelled orders recognise nothing.
  Money get recognisedRevenue =>
      isRecognised ? totalRevenue - effectiveRefund : Money.zero;

  /// Product cost that actually counts towards reporting. Returned units are
  /// assumed restocked, so cost is reversed in proportion to the refunded
  /// fraction of revenue. Cancelled orders recognise nothing.
  Money get recognisedProductCost => isRecognised
      ? productCost - (productCost * refundRatio)
      : Money.zero;

  /// Net-of-refund gross profit used by the profit engine.
  Money get recognisedGrossProfit =>
      recognisedRevenue - recognisedProductCost;

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
        'refundAmountMinor': refundAmount.minor,
        if (refundDate != null) 'refundDate': refundDate!.toIso8601String(),
        'customerReference': customerReference,
        'notes': notes,
        'comments': comments.map((c) => c.toMap()).toList(),
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
        refundAmount: Money((map['refundAmountMinor'] as num?)?.toInt() ?? 0),
        refundDate: parseDate(map['refundDate']),
        customerReference: map['customerReference'] as String? ?? '',
        notes: map['notes'] as String? ?? '',
        comments: EntityComment.listFrom(map['comments']),
        audit: AuditFields.fromMap(map),
      );

  Order copyWith({
    String? id,
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
    Money? refundAmount,
    DateTime? refundDate,
    String? customerReference,
    String? notes,
    List<EntityComment>? comments,
    AuditFields? audit,
  }) =>
      Order(
        id: id ?? this.id,
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
        refundAmount: refundAmount ?? this.refundAmount,
        refundDate: refundDate ?? this.refundDate,
        customerReference: customerReference ?? this.customerReference,
        notes: notes ?? this.notes,
        comments: comments ?? this.comments,
        audit: audit ?? this.audit,
      );
}
