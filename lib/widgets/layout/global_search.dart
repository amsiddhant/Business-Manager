import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../state/data_controller.dart';

/// A single global-search result.
class _Result {
  const _Result({
    required this.type,
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.route,
  });
  final String type;
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final String route;
}

/// Global search across products, orders, campaigns, dealers, expenses and
/// businesses (spec §48). Results show the entity type and jump to the module.
class GlobalSearchDelegate extends SearchDelegate<void> {
  GlobalSearchDelegate(this.data, {this.businessName});

  final DataController data;
  final String? Function(String businessId)? businessName;

  @override
  String get searchFieldLabel => 'Search products, orders, campaigns…';

  @override
  List<Widget> buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => query = '',
          ),
      ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => close(context, null),
      );

  @override
  Widget buildResults(BuildContext context) => _buildList(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildList(context);

  String _bizLabel(String businessId) =>
      businessName?.call(businessId) ?? businessId;

  List<_Result> _search() {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final results = <_Result>[];

    bool m(String s) => s.toLowerCase().contains(q);

    for (final p in data.products) {
      if (m(p.name) || m(p.id) || m(p.sku)) {
        results.add(_Result(
          type: 'Product',
          id: p.id,
          title: p.name,
          subtitle: '${p.id} · ${_bizLabel(p.businessId)}',
          icon: Icons.inventory_2_outlined,
          route: Routes.productDetailPath(p.id),
        ));
      }
    }
    for (final o in data.orders) {
      if (m(o.id) || m(o.productName) || m(o.customerReference)) {
        results.add(_Result(
          type: 'Order',
          id: o.id,
          title: '${o.id} · ${o.productName}',
          subtitle: _bizLabel(o.businessId),
          icon: Icons.receipt_long_outlined,
          route: Routes.orders,
        ));
      }
    }
    for (final c in data.campaigns) {
      if (m(c.name) || m(c.id)) {
        results.add(_Result(
          type: 'Campaign',
          id: c.id,
          title: c.name,
          subtitle: '${c.platform.label} · ${_bizLabel(c.businessId)}',
          icon: Icons.campaign_outlined,
          route: Routes.campaigns,
        ));
      }
    }
    for (final d in data.dealers) {
      if (m(d.name) || m(d.id)) {
        results.add(_Result(
          type: 'Dealer',
          id: d.id,
          title: d.name,
          subtitle: _bizLabel(d.businessId),
          icon: Icons.handshake_outlined,
          route: Routes.dealers,
        ));
      }
    }
    for (final e in data.expenses) {
      if (m(e.name) || m(e.id)) {
        results.add(_Result(
          type: 'Expense',
          id: e.id,
          title: e.name,
          subtitle: '${e.category.label} · ${_bizLabel(e.businessId)}',
          icon: Icons.account_balance_wallet_outlined,
          route: Routes.expenses,
        ));
      }
    }
    for (final b in data.businesses) {
      if (m(b.name) || m(b.id)) {
        results.add(_Result(
          type: 'Business',
          id: b.id,
          title: b.name,
          subtitle: b.id,
          icon: Icons.business_outlined,
          route: Routes.businesses,
        ));
      }
    }
    return results.take(40).toList();
  }

  Widget _buildList(BuildContext context) {
    final results = _search();
    if (query.trim().isEmpty) {
      return const Center(
        child: Text('Start typing to search across your data.',
            style: TextStyle(color: AppColors.textSecondary)),
      );
    }
    if (results.isEmpty) {
      return Center(
        child: Text('No results for "$query".',
            style: const TextStyle(color: AppColors.textSecondary)),
      );
    }
    return ListView.separated(
      itemCount: results.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final r = results[i];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: AppColors.primaryLight,
            child: Icon(r.icon, color: AppColors.primary, size: 20),
          ),
          title: Text(r.title),
          subtitle: Text(r.subtitle),
          trailing: Chip(
            label: Text(r.type),
            visualDensity: VisualDensity.compact,
          ),
          onTap: () {
            close(context, null);
            context.go(r.route);
          },
        );
      },
    );
  }
}
