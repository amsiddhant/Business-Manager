import 'package:flutter_test/flutter_test.dart';
import 'package:salesforce_business_manager/core/enums.dart';
import 'package:salesforce_business_manager/data/demo_seed.dart';
import 'package:salesforce_business_manager/data/repository.dart';
import 'package:salesforce_business_manager/models/app_user.dart';
import 'package:salesforce_business_manager/services/search_index.dart';
import 'package:salesforce_business_manager/state/data_controller.dart';

import 'support/memory_backend.dart';

/// The command palette replaced the old search page. It must find everything
/// the old page found: a case-insensitive "contains" over these fields.
Map<String, List<(String, List<String>)>> _oldFields(DataController d) => {
      'Product': [for (final p in d.products) (p.id, [p.name, p.id, p.sku])],
      'Order': [
        for (final o in d.orders)
          (o.id, [o.id, o.productName, o.customerReference])
      ],
      'Campaign': [for (final c in d.campaigns) (c.id, [c.name, c.id])],
      'Customer': [
        for (final c in d.customers)
          (c.id, [c.name, c.id, c.email, c.contactNo])
      ],
      'Dealer': [for (final x in d.dealers) (x.id, [x.name, x.id])],
      'Expense': [for (final x in d.expenses) (x.id, [x.name, x.id])],
      'Business': [for (final x in d.businesses) (x.id, [x.name, x.id])],
    };

Set<(String, String)> _oldSearch(
    Map<String, List<(String, List<String>)>> fields, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return {};
  return {
    for (final MapEntry(key: type, value: rows) in fields.entries)
      for (final (id, values) in rows)
        if (values.any((v) => v.toLowerCase().contains(q))) (type, id),
  };
}

void main() {
  late DataController data;

  setUpAll(() async {
    final backend = MemoryBackend();
    final store = DemoSeed(DateTime(2026, 10, 22)).buildStore();
    for (final MapEntry(key: collection, value: docs) in store.entries) {
      for (final MapEntry(key: id, value: doc) in docs.entries) {
        backend.put(collection, id, doc);
      }
    }
    // The demo seed has no customers.
    final bizId = store['businesses']!.keys.first;
    for (final (id, name, email, phone) in [
      ('CUST-00001', 'Acme Traders', 'buyer@acme.example', '+91 98450 12345'),
      ('CUST-00002', 'Blue Lotus Spa', 'hello@bluelotus.example', '080-4111'),
      ('CUST-00003', 'Kiran Rao', '', ''),
    ]) {
      backend.put('customers', id, {
        'id': id,
        'name': name,
        'email': email,
        'contactNo': phone,
        'businessIds': [bizId],
      });
    }
    const owner = AppUser(
      uid: 'owner',
      loginId: 'owner',
      name: 'Owner',
      email: DemoSeed.ownerEmail,
      role: UserRole.owner,
    );
    data = DataController(Repository(backend: backend, currentUser: owner));
    await data.load();
  });

  test('the demo data covers every searchable type', () {
    final fields = _oldFields(data);
    for (final MapEntry(key: type, value: rows) in fields.entries) {
      expect(rows, isNotEmpty, reason: type);
    }
  });

  test('the palette finds everything the old search found', () {
    final fields = _oldFields(data);
    final index = SearchIndex.of(data);

    // Whole values, prefixes, middles and suffixes of every searchable field,
    // plus a few short, broad queries.
    final queries = <String>{'a', 'e', '0', '1', '-', ' '};
    for (final rows in fields.values) {
      for (final (_, values) in rows) {
        for (final raw in values) {
          final v = raw.trim();
          if (v.isEmpty) continue;
          queries.add(v);
          queries.add(v.toUpperCase());
          if (v.length > 3) {
            queries.add(v.substring(0, 3));
            queries.add(v.substring(v.length - 3));
            queries.add(v.substring(v.length ~/ 3, v.length ~/ 3 + 3));
          }
        }
      }
    }

    var checked = 0;
    for (final q in queries) {
      final expected = _oldSearch(fields, q);
      if (expected.isEmpty) continue;
      final found = {
        for (final h in index.search(q, limit: 1 << 20)) (h.type, h.id)
      };
      final missing = expected.difference(found);
      expect(missing, isEmpty, reason: 'query "$q" lost $missing');
      checked++;
    }
    expect(checked, greaterThan(100));
  });

  test('hits open the record they describe', () {
    final index = SearchIndex.of(data);
    final o = data.orders.first;
    final hit = index.search(o.id).first;
    expect(hit.type, 'Order');
    expect(hit.id, o.id);
    expect(hit.route, '/orders/${o.id}');
    expect(index.byRoute(hit.route)?.id, o.id);
  });

  test('exact matches rank above substring matches', () {
    expect(SearchIndex.score('acme', 'acme'),
        greaterThan(SearchIndex.score('acme', 'acme ltd')));
    expect(SearchIndex.score('acme', 'acme ltd'),
        greaterThan(SearchIndex.score('ltd', 'acme ltd')));
    expect(SearchIndex.score('ltd', 'acme ltd'),
        greaterThan(SearchIndex.score('cme', 'acme ltd')));
    expect(SearchIndex.score('zzz', 'acme ltd'), 0);
  });
}
