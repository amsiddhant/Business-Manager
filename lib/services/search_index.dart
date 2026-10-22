import 'package:flutter/material.dart';

import '../core/routing/app_routes.dart';
import '../state/data_controller.dart';

/// One record found by [SearchIndex.search].
class SearchHit {
  const SearchHit({
    required this.type,
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.route,
    this.score = 0,
  });

  /// "Product", "Order", "Customer"…
  final String type;
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;

  /// The record's detail page.
  final String route;

  /// Higher is a better match.
  final int score;

  SearchHit withScore(int score) => SearchHit(
        type: type,
        id: id,
        title: title,
        subtitle: subtitle,
        icon: icon,
        route: route,
        score: score,
      );
}

class _Entry {
  _Entry(this.hit, this.order, List<String> primary, List<String> secondary)
      : primary = [for (final s in primary) s.toLowerCase()],
        secondary = [for (final s in secondary) s.toLowerCase()];

  final SearchHit hit;

  /// Type order, for ties: products, orders, campaigns, customers, dealers,
  /// expenses, businesses (as global search always listed them).
  final int order;
  final List<String> primary;
  final List<String> secondary;
}

/// Searchable records across products, orders, campaigns, customers, dealers,
/// expenses and businesses (spec §48). Only what the user can access is in
/// [DataController], so only that is searched.
///
/// Built once per data version; ranks exact > prefix > word prefix >
/// substring, names before secondary fields (SKU, email, phone…).
class SearchIndex {
  SearchIndex._(this._entries);

  final List<_Entry> _entries;

  static DataController? _data;
  static int _version = -1;
  static SearchIndex? _cached;

  /// The index for [data]'s current contents (reused until it changes).
  static SearchIndex of(DataController data) {
    if (identical(_data, data) && _version == data.version) return _cached!;
    _data = data;
    _version = data.version;
    return _cached = SearchIndex._(_build(data));
  }

  static const _exact = 100, _prefix = 80, _word = 60, _substring = 40;

  /// How well [query] (lower-case, trimmed) matches [text] (lower-case):
  /// 0 for no match.
  static int score(String query, String text) {
    if (query.isEmpty || text.isEmpty) return 0;
    if (text == query) return _exact;
    if (text.startsWith(query)) return _prefix;
    final i = text.indexOf(query);
    if (i < 0) return 0;
    // A later word starting with the query ("acme ltd" for "ltd").
    final before = text.codeUnitAt(i - 1);
    final boundary = !_isWordChar(before);
    return boundary ? _word : _substring;
  }

  static bool _isWordChar(int c) =>
      (c >= 0x30 && c <= 0x39) || // 0-9
      (c >= 0x41 && c <= 0x5A) || // A-Z
      (c >= 0x61 && c <= 0x7A); // a-z

  /// Records matching [query], best first, at most [limit].
  List<SearchHit> search(String query, {int limit = 40}) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final scored = <(int, _Entry)>[];
    for (final e in _entries) {
      var best = 0;
      for (final f in e.primary) {
        final s = score(q, f);
        if (s > best) best = s;
      }
      for (final f in e.secondary) {
        final s = score(q, f) - 5;
        if (s > best) best = s;
      }
      if (best > 0) scored.add((best, e));
    }
    scored.sort((a, b) {
      final byScore = b.$1.compareTo(a.$1);
      return byScore != 0 ? byScore : a.$2.order.compareTo(b.$2.order);
    });
    return [for (final (s, e) in scored.take(limit)) e.hit.withScore(s)];
  }

  /// The record whose detail page is [route], if it still exists.
  SearchHit? byRoute(String route) {
    for (final e in _entries) {
      if (e.hit.route == route) return e.hit;
    }
    return null;
  }

  static List<_Entry> _build(DataController data) {
    String biz(String id) => data.businessById(id)?.name ?? id;
    final entries = <_Entry>[];
    // List.sort is not stable, so ties fall back to this insertion order.
    var n = 0;
    void add(SearchHit hit, int type, List<String> primary,
        [List<String> secondary = const []]) {
      entries.add(_Entry(hit, type * 1000000 + n++, primary, secondary));
    }

    for (final p in data.products) {
      add(
        SearchHit(
          type: 'Product',
          id: p.id,
          title: p.name,
          subtitle: '${p.id} · ${biz(p.businessId)}',
          icon: Icons.inventory_2_outlined,
          route: Routes.productDetailPath(p.id),
        ),
        0,
        [p.name, p.id],
        [p.sku],
      );
    }
    for (final o in data.orders) {
      add(
        SearchHit(
          type: 'Order',
          id: o.id,
          title: '${o.id} · ${o.productName}',
          subtitle: biz(o.businessId),
          icon: Icons.receipt_long_outlined,
          route: Routes.orderDetailPath(o.id),
        ),
        1,
        [o.id, o.productName],
        [o.customerReference],
      );
    }
    for (final c in data.campaigns) {
      add(
        SearchHit(
          type: 'Campaign',
          id: c.id,
          title: c.name,
          subtitle: '${c.platform.label} · ${biz(c.businessId)}',
          icon: Icons.campaign_outlined,
          route: Routes.campaignDetailPath(c.id),
        ),
        2,
        [c.name, c.id],
      );
    }
    for (final c in data.customers) {
      add(
        SearchHit(
          type: 'Customer',
          id: c.id,
          title: c.name,
          subtitle:
              '${c.id} · ${c.businessIds.isNotEmpty ? biz(c.businessIds.first) : '—'}',
          icon: Icons.person_outline,
          route: Routes.customerDetailPath(c.id),
        ),
        3,
        [c.name, c.id],
        [c.email, c.contactNo],
      );
    }
    for (final d in data.dealers) {
      add(
        SearchHit(
          type: 'Dealer',
          id: d.id,
          title: d.name,
          subtitle: biz(d.businessId),
          icon: Icons.handshake_outlined,
          route: Routes.dealerDetailPath(d.id),
        ),
        4,
        [d.name, d.id],
      );
    }
    for (final e in data.expenses) {
      add(
        SearchHit(
          type: 'Expense',
          id: e.id,
          title: e.name,
          subtitle: '${e.category.label} · ${biz(e.businessId)}',
          icon: Icons.account_balance_wallet_outlined,
          route: Routes.expenseDetailPath(e.id),
        ),
        5,
        [e.name, e.id],
      );
    }
    for (final b in data.businesses) {
      add(
        SearchHit(
          type: 'Business',
          id: b.id,
          title: b.name,
          subtitle: b.id,
          icon: Icons.business_outlined,
          route: Routes.businessDetailPath(b.id),
        ),
        6,
        [b.name, b.id],
      );
    }
    return entries;
  }
}
