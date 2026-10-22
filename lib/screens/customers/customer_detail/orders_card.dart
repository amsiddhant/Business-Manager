import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/enums.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/utils/date_utils.dart';
import '../../../models/business.dart';
import '../../../models/order.dart';
import '../../../widgets/common/currency_display.dart';
import '../../../widgets/common/status_badge.dart';
import '../../../widgets/data/app_data_grid.dart';

/// Lists the orders placed by this customer, newest-first, with a row tap
/// through to each order's detail view.
///
/// A customer may be tagged to several businesses, so each row resolves its own
/// business currency rather than assuming one; a Business column is shown only
/// when the customer spans more than one business. The [orders] passed in are
/// already access-scoped (see `DataController.ordersForCustomer`).
class OrdersCard extends StatelessWidget {
  const OrdersCard({super.key, required this.orders, required this.businesses});

  final List<Order> orders;
  final List<Business> businesses;

  static final _epoch = DateTime.fromMillisecondsSinceEpoch(0);
  static DateTime _dateOf(Order o) =>
      o.orderDate ?? o.audit.createdAt ?? _epoch;

  CurrencyCode _currencyOf(Order o) {
    for (final b in businesses) {
      if (b.id == o.businessId) return b.currency;
    }
    return CurrencyCode.inr;
  }

  String _businessName(String id) {
    for (final b in businesses) {
      if (b.id == id) return b.name;
    }
    return id;
  }

  @override
  Widget build(BuildContext context) {
    final multiBusiness = businesses.length > 1;
    final sorted = [...orders]
      ..sort((a, b) => _dateOf(b).compareTo(_dateOf(a)));
    return AppDataGrid<Order>(
      gridId: 'customer.orders',
      title: 'Orders',
      subtitle: '${orders.length} '
          '${orders.length == 1 ? 'order' : 'orders'} placed',
      rows: sorted,
      rowKey: (o) => o.id,
      pageSize: 10,
      exportName: 'customer-orders',
      searchHint: 'Search orders by ID, product or status…',
      searchText: (o) => '${o.id} ${o.productName} '
          '${o.status.label} ${AppDate.short(_dateOf(o))} '
          '${multiBusiness ? _businessName(o.businessId) : ''}',
      onRowTap: (o) => context.go(Routes.orderDetailPath(o.id)),
      emptyTitle: 'No orders',
      emptyIcon: Icons.receipt_long_outlined,
      emptyMessage: 'Orders placed by this customer will appear here.',
      columns: [
        GridColumn<Order>(
          id: 'id',
          label: 'Order ID',
          pinned: true,
          cardRole: CardRole.subtitle,
          minWidth: 110,
          cell: (o) =>
              Text(o.id, style: const TextStyle(fontWeight: FontWeight.w600)),
          sortValue: (o) => o.id,
          exportValue: (o) => o.id,
        ),
        GridColumn<Order>(
          id: 'product',
          label: 'Product',
          flex: 2,
          cardRole: CardRole.title,
          cell: (o) => Text(o.productName.isEmpty ? '—' : o.productName,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          sortValue: (o) => o.productName.toLowerCase(),
          exportValue: (o) => o.productName,
        ),
        if (multiBusiness)
          GridColumn<Order>(
            id: 'business',
            label: 'Business',
            cardRole: CardRole.meta,
            cell: (o) => Text(_businessName(o.businessId),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            sortValue: (o) => _businessName(o.businessId).toLowerCase(),
            exportValue: (o) => _businessName(o.businessId),
          ),
        GridColumn<Order>(
          id: 'date',
          label: 'Date',
          cardRole: CardRole.meta,
          minWidth: 110,
          cell: (o) => Text(AppDate.short(_dateOf(o))),
          sortValue: (o) => _dateOf(o).millisecondsSinceEpoch,
          exportValue: (o) => AppDate.format(_dateOf(o)),
        ),
        GridColumn<Order>(
          id: 'qty',
          label: 'Qty',
          numeric: true,
          minWidth: 64,
          cardRole: CardRole.meta,
          cell: (o) => Text('${o.quantity}'),
          sortValue: (o) => o.quantity,
          exportValue: (o) => '${o.quantity}',
        ),
        GridColumn<Order>(
          id: 'revenue',
          label: 'Revenue',
          numeric: true,
          cardRole: CardRole.metric,
          cell: (o) =>
              CurrencyText(o.recognisedRevenue, currency: _currencyOf(o)),
          sortValue: (o) => o.recognisedRevenue.minor,
          exportValue: (o) => o.recognisedRevenue.major.toStringAsFixed(2),
        ),
        GridColumn<Order>(
          id: 'profit',
          label: 'Profit',
          numeric: true,
          cardRole: CardRole.metric,
          cell: (o) => CurrencyText(o.recognisedGrossProfit,
              currency: _currencyOf(o)),
          sortValue: (o) => o.recognisedGrossProfit.minor,
          exportValue: (o) => o.recognisedGrossProfit.major.toStringAsFixed(2),
        ),
        GridColumn<Order>(
          id: 'status',
          label: 'Status',
          cardRole: CardRole.badge,
          minWidth: 120,
          cell: (o) => StatusBadge.order(o.status),
          sortValue: (o) => o.status.label,
          exportValue: (o) => o.status.label,
        ),
      ],
    );
  }
}
