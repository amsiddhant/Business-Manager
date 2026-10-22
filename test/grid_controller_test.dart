import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salesforce_business_manager/core/theme/app_density.dart';
import 'package:salesforce_business_manager/widgets/data/grid_column.dart';
import 'package:salesforce_business_manager/widgets/data/grid_controller.dart';

class _Row {
  const _Row(this.name, this.status, this.amount, this.date);
  final String name;
  final String status;
  final int amount;
  final DateTime date;
}

final _rows = [
  _Row('Alpha', 'Pending', 300, DateTime(2026, 4, 2)),
  _Row('Bravo', 'Shipped', 100, DateTime(2026, 4, 20)),
  _Row('Charlie', 'Pending', 200, DateTime(2026, 5, 1)),
  _Row('Delta', 'Cancelled', 100, DateTime(2026, 3, 30)),
  _Row('Echo apple', 'Shipped', 50, DateTime(2026, 4, 10)),
];

final _columns = <GridColumn<_Row>>[
  GridColumn(
    id: 'name',
    label: 'Name',
    cell: (r) => Text(r.name),
    sortValue: (r) => r.name,
    exportValue: (r) => r.name,
    pinned: true,
  ),
  GridColumn(
    id: 'status',
    label: 'Status',
    cell: (r) => Text(r.status),
    sortValue: (r) => r.status,
    exportValue: (r) => r.status,
    filter: GridFilter.choice((r) => r.status),
  ),
  GridColumn(
    id: 'amount',
    label: 'Amount',
    numeric: true,
    cell: (r) => Text('${r.amount}'),
    sortValue: (r) => r.amount,
    exportValue: (r) => '${r.amount}',
    filter: GridFilter.numberRange((r) => r.amount),
  ),
  GridColumn(
    id: 'date',
    label: 'Date',
    cell: (r) => Text('${r.date}'),
    sortValue: (r) => r.date,
    filter: GridFilter.dateRange((r) => r.date),
    visibleByDefault: false,
  ),
];

List<String> _names(GridResult<_Row> r) => [for (final x in r.all) x.name];

void main() {
  test('search needs every word, in any column', () {
    final c = GridController();
    c.setSearch('pend');
    expect(_names(c.apply(_rows, _columns)), ['Alpha', 'Charlie']);
    c.setSearch('apple  shipped');
    expect(_names(c.apply(_rows, _columns)), ['Echo apple']);
    // The page's own search box adds its words too.
    c.setSearch('');
    expect(_names(c.apply(_rows, _columns, externalSearch: 'bravo')), ['Bravo']);
  });

  test('choice, number and date filters combine', () {
    final c = GridController();
    c.setFilter('status', const ChoiceValue({'Pending', 'Shipped'}));
    expect(c.apply(_rows, _columns).total, 4);
    c.setFilter('amount', const NumberRangeValue(min: 100, max: 250));
    expect(_names(c.apply(_rows, _columns)), ['Bravo', 'Charlie']);
    c.setFilter(
        'date', DateRangeValue(DateTime(2026, 4, 1), DateTime(2026, 4, 30)));
    // The range takes in its whole last day.
    expect(_names(c.apply(_rows, _columns)), ['Bravo']);
    c.clearFilters();
    expect(c.apply(_rows, _columns).total, 5);
    expect(c.hasFilters, isFalse);
  });

  test('quick filters count the filtered rows, and narrow them', () {
    final c = GridController();
    final quick = [
      GridQuickFilter<_Row>(
          id: 'pending', label: 'Pending', test: (r) => r.status == 'Pending'),
      GridQuickFilter<_Row>(
          id: 'big', label: 'Big', test: (r) => r.amount >= 200),
    ];
    var r = c.apply(_rows, _columns, quickFilters: quick);
    expect(r.quickCounts, {'pending': 2, 'big': 2});
    expect(r.baseTotal, 5);
    c.setQuick('big');
    r = c.apply(_rows, _columns, quickFilters: quick);
    expect(_names(r), ['Alpha', 'Charlie']);
    expect(r.baseTotal, 5);
  });

  test('sorting: asc, desc, back to default; shift adds a key', () {
    final c = GridController(sorts: const [GridSort('name')]);
    c.sortBy('amount');
    expect(_names(c.apply(_rows, _columns)).first, 'Echo apple');
    c.sortBy('amount');
    expect(_names(c.apply(_rows, _columns)).first, 'Alpha');
    c.sortBy('amount');
    expect(c.sorts, const [GridSort('name')]);

    c.setSorts(const [GridSort('amount')]);
    c.sortBy('name', additive: true);
    expect(c.sortOf('name'), (1, true));
    // Equal amounts (Bravo, Delta at 100) fall back to the name.
    expect(_names(c.apply(_rows, _columns)),
        ['Echo apple', 'Bravo', 'Delta', 'Charlie', 'Alpha']);
    c.sortBy('name', additive: true);
    expect(c.sortOf('name'), (1, false));
    expect(_names(c.apply(_rows, _columns)).sublist(1, 3), ['Delta', 'Bravo']);
    c.sortBy('name', additive: true);
    expect(c.sortOf('name'), isNull);
  });

  test('paging clamps and resets when the search changes', () {
    final c = GridController(pageSize: 2);
    var r = c.apply(_rows, _columns);
    expect(r.pageCount, 3);
    c.setPage(2);
    r = c.apply(_rows, _columns);
    expect(r.pageRows.length, 1);
    expect(r.start, 4);
    c.setSearch('a');
    expect(c.page, 0);
    c.setPageSize(0);
    r = c.apply(_rows, _columns);
    expect(r.pageCount, 1);
    expect(r.pageRows.length, r.total);
  });

  test('columns: hidden, reordered, pinned stays first and visible', () {
    final c = GridController();
    expect([for (final x in c.visibleColumns(_columns)) x.id],
        ['name', 'status', 'amount']);
    c.setVisible('date', true);
    c.setVisible('status', false);
    c.setVisible('name', false); // pinned: ignored
    c.setOrder(['amount', 'date', 'name']);
    expect([for (final x in c.visibleColumns(_columns)) x.id],
        ['name', 'amount', 'date']);
    expect(c.hasColumnChanges, isTrue);
    c.resetColumns();
    expect(c.hasColumnChanges, isFalse);
  });

  test('selection: toggle, shift-range, prune', () {
    final c = GridController();
    final keys = [for (final r in _rows) r.name];
    c.toggle('Bravo');
    c.selectRange(keys, 'Delta');
    expect(c.selected, {'Bravo', 'Charlie', 'Delta'});
    c.toggle('Charlie');
    expect(c.selectedCount, 2);
    expect(c.pruneSelection({'Bravo', 'Alpha'}), isTrue);
    expect(c.selected, {'Bravo'});
    c.clearSelection();
    expect(c.selectedCount, 0);
  });

  test('view state round-trips through JSON', () {
    final c = GridController();
    c.setSearch('x');
    c.setFilter('status', const ChoiceValue({'Pending'}));
    c.setFilter('amount', const NumberRangeValue(min: 5));
    c.setFilter('date', DateRangeValue(DateTime(2026, 1, 1), DateTime(2026, 2, 1)));
    c.setQuick('big');
    c.setSorts(const [GridSort('amount', ascending: false)]);
    c.setPageSize(50);
    c.setDensity(AppDensity.compact);
    c.setVisible('date', true);
    c.setOrder(['amount', 'status']);

    final json = c.snapshot().toJson();
    final back = GridController()..restore(GridViewState.fromJson(json));
    expect(back.snapshot().toJson(), json);
    expect(back.filterFor('date'),
        DateRangeValue(DateTime(2026, 1, 1), DateTime(2026, 2, 1)));

    // A layout snapshot leaves the search and filters out.
    final layout = c.snapshot(layoutOnly: true);
    expect(layout.search, '');
    expect(layout.filters, isEmpty);
    expect(layout.pageSize, 50);
  });

  test('bad saved JSON falls back to defaults', () {
    final s = GridViewState.fromJson({
      'search': 3,
      'filters': {'a': {'t': 'nope'}, 'b': 'x'},
      'sorts': [{'c': 1}],
      'pageSize': 7,
      'density': 'huge',
      'visibility': {'a': 'yes'},
      'order': [1, 'a'],
    });
    expect(s.search, '');
    expect(s.filters, isEmpty);
    expect(s.sorts, isEmpty);
    expect(s.pageSize, isNull);
    expect(s.density, isNull);
    expect(s.visibility, isEmpty);
    expect(s.order, ['a']);
  });

  test('apply is memoised until the rows or settings change', () {
    final c = GridController();
    final rows = List.of(_rows);
    final a = c.apply(rows, _columns);
    expect(identical(c.apply(rows, _columns), a), isTrue);
    rows[0] = _Row('Zulu', 'Pending', 1, DateTime(2026));
    expect(identical(c.apply(rows, _columns), a), isFalse);
    final b = c.apply(rows, _columns);
    c.setSearch('zulu');
    expect(identical(c.apply(rows, _columns), b), isFalse);
  });
}
