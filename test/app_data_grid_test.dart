import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:salesforce_business_manager/state/user_prefs.dart';
import 'package:salesforce_business_manager/widgets/data/app_data_grid.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Row {
  const _Row(this.id, this.name, this.status, this.amount);
  final int id;
  final String name;
  final String status;
  final int amount;
}

final _rows = [
  for (var i = 0; i < 30; i++)
    _Row(i, 'Item ${i.toString().padLeft(2, '0')}',
        i.isEven ? 'Pending' : 'Shipped', (i * 37) % 100),
];

List<GridColumn<_Row>> _columns() => [
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
        cell: (r) => Text('₹${r.amount}'),
        sortValue: (r) => r.amount,
        exportValue: (r) => '${r.amount}',
        footer: (rows) => '₹${rows.fold<int>(0, (s, r) => s + r.amount)}',
      ),
    ];

Future<UserPrefs> _pump(WidgetTester tester, Widget child,
    {double width = 1200, UserPrefs? prefs}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 2400);
  addTearDown(tester.view.reset);
  final userPrefs = prefs ??
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        return UserPrefs(await SharedPreferences.getInstance())..bindUser('u1');
      });
  await tester.pumpWidget(ChangeNotifierProvider<UserPrefs>.value(
    value: userPrefs!,
    child: MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  ));
  await tester.pump();
  return userPrefs;
}

void main() {
  testWidgets('sorts by header, pages, and totals the matching rows',
      (tester) async {
    await _pump(
        tester,
        AppDataGrid<_Row>(
          rows: _rows,
          columns: _columns(),
          rowKey: (r) => r.id,
          pageSize: 10,
        ));
    expect(find.text('Item 00'), findsOneWidget);
    expect(find.text('Item 10'), findsNothing);
    expect(find.text('1–10 of 30'), findsOneWidget);
    // Footer total covers all 30 rows, not just the page.
    final total = _rows.fold<int>(0, (s, r) => s + r.amount);
    expect(find.text('₹$total'), findsOneWidget);

    await tester.tap(find.text('NAME'));
    await tester.pump();
    await tester.tap(find.text('NAME'));
    await tester.pump();
    expect(find.text('Item 29'), findsOneWidget);
    expect(find.text('Item 00'), findsNothing);

    await tester.tap(find.byTooltip('Next page'));
    await tester.pump();
    expect(find.text('11–20 of 30'), findsOneWidget);
    expect(find.text('Item 19'), findsOneWidget);
  });

  testWidgets('search and a choice filter narrow the rows', (tester) async {
    await _pump(
        tester,
        AppDataGrid<_Row>(
          rows: _rows,
          columns: _columns(),
          rowKey: (r) => r.id,
          pageSize: 50,
        ));
    await tester.enterText(find.byType(TextField).first, 'item 1');
    await tester.pump(const Duration(milliseconds: 300));
    // Item 01, 10–19.
    expect(find.textContaining('Item 1'), findsNWidgets(10));
    expect(find.text('Item 01'), findsOneWidget);

    await tester.tap(find.text('Filter'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, 'Status'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Shipped'));
    await tester.pump();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(find.text('Status: Shipped'), findsOneWidget);
    // Shipped are the odd ids: 01, 11, 13, 15, 17, 19.
    expect(find.textContaining('Item 1'), findsNWidgets(5));
    expect(find.text('Item 10'), findsNothing);

    await tester.tap(find.text('Clear all'));
    await tester.pump();
    expect(find.text('Status: Shipped'), findsNothing);
  });

  testWidgets('no matches offers to clear the filters', (tester) async {
    await _pump(
        tester,
        AppDataGrid<_Row>(
            rows: _rows, columns: _columns(), rowKey: (r) => r.id));
    await tester.enterText(find.byType(TextField).first, 'zzz');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('No matches'), findsOneWidget);
    await tester.tap(find.text('Clear filters'));
    await tester.pump();
    expect(find.text('Item 00'), findsOneWidget);
  });

  testWidgets('ticking rows shows the bulk bar and runs actions on them',
      (tester) async {
    List<_Row>? ran;
    await _pump(
        tester,
        AppDataGrid<_Row>(
          rows: _rows,
          columns: _columns(),
          rowKey: (r) => r.id,
          pageSize: 10,
          bulkActions: [
            GridBulkAction(
              label: 'Archive',
              icon: Icons.archive_outlined,
              allowed: (r) => r.id != 1,
              onRun: (context, rows) async => ran = rows,
            ),
          ],
        ));
    final boxes = find.byType(Checkbox);
    // Header + 10 rows.
    expect(boxes, findsNWidgets(11));
    await tester.tap(boxes.at(1));
    await tester.tap(boxes.at(2));
    await tester.pump();
    expect(find.text('2 selected'), findsOneWidget);
    expect(find.text('Select all 30'), findsOneWidget);

    await tester.tap(find.text('Archive'));
    await tester.pump();
    // Row 1 isn't allowed: it's skipped, and the bar says so.
    expect([for (final r in ran!) r.id], [0]);
    expect(find.textContaining('Skipped 1 row'), findsOneWidget);
    expect(find.text('2 selected'), findsNothing);

    // The header box ticks the whole page.
    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    expect(find.text('10 selected'), findsOneWidget);
    await tester.tap(find.text('Select all 30'));
    await tester.pump();
    expect(find.text('30 selected'), findsOneWidget);
  });

  testWidgets('hiding a column is remembered for the user', (tester) async {
    final prefs = await _pump(
        tester,
        AppDataGrid<_Row>(
          gridId: 'test',
          rows: _rows,
          columns: _columns(),
          rowKey: (r) => r.id,
        ));
    expect(find.text('STATUS'), findsOneWidget);
    await tester.tap(find.text('Columns'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Status').last);
    // Tapping the tile's checkbox.
    await tester.tap(find.descendant(
        of: find.widgetWithText(ListTile, 'Status').last,
        matching: find.byType(Checkbox)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('STATUS'), findsNothing);
    await tester.pump(const Duration(milliseconds: 500));

    // A fresh grid with the same id starts with the column hidden.
    await tester.pumpWidget(const SizedBox());
    await _pump(
        tester,
        AppDataGrid<_Row>(
          gridId: 'test',
          rows: _rows,
          columns: _columns(),
          rowKey: (r) => r.id,
        ),
        prefs: prefs);
    expect(find.text('STATUS'), findsNothing);
    expect(find.text('NAME'), findsOneWidget);
  });

  testWidgets('a phone shows cards, with the status as a badge',
      (tester) async {
    await _pump(
        tester,
        AppDataGrid<_Row>(
          rows: _rows,
          columns: _columns(),
          rowKey: (r) => r.id,
          pageSize: 10,
        ),
        width: 400);
    expect(find.text('NAME'), findsNothing); // no table header
    expect(find.text('Item 00'), findsOneWidget);
    expect(find.text('AMOUNT'), findsNWidgets(10)); // a metric per card
    expect(find.byTooltip('View options'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the sliver variant lays out in a scroll view', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.reset);
    final prefs = await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      return UserPrefs(await SharedPreferences.getInstance())..bindUser('u1');
    });
    await tester.pumpWidget(ChangeNotifierProvider<UserPrefs>.value(
      value: prefs!,
      child: MaterialApp(
        home: Scaffold(
          body: CustomScrollView(slivers: [
            SliverAppDataGrid<_Row>(
              rows: _rows,
              columns: _columns(),
              rowKey: (r) => r.id,
              pageSize: 0,
            ),
          ]),
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('NAME'), findsOneWidget);
    expect(find.text('Item 00'), findsOneWidget);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -2000));
    await tester.pump();
    // The header stays pinned while the last rows scroll in.
    expect(find.text('NAME'), findsOneWidget);
    expect(find.text('Item 29'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('export takes the filtered rows and the shown columns', () {
    final c = GridController();
    final cols = _columns();
    c.setFilter('status', const ChoiceValue({'Pending'}));
    c.setVisible('status', false);
    final r = c.apply(_rows, cols);
    final csv = gridCsv(c.visibleColumns(cols), r.all);
    expect(csv.first, ['Name', 'Amount']);
    expect(csv.length, 16);
    expect(csv[1], ['Item 00', '0']);
  });

  // Saved views + filters + export + an action used to overflow 760-890 px.
  for (final width in [680.0, 760.0, 820.0, 890.0, 1000.0, 1280.0]) {
    testWidgets('a full toolbar fits at $width px', (tester) async {
      await _pump(
        tester,
        AppDataGrid<_Row>(
          rows: _rows,
          columns: _columns(),
          gridId: 'toolbar-fit',
          title: 'Rows',
          exportName: 'rows',
          toolbarActions: [
            FilledButton(onPressed: () {}, child: const Text('Add')),
          ],
        ),
        width: width,
      );
      expect(tester.takeException(), isNull);
      // Narrow toolbars (the card's padding included) keep the labels as
      // tooltips.
      if (width <= 1000) {
        expect(find.text('Columns'), findsNothing);
        expect(find.byTooltip('Columns'), findsOneWidget);
      } else {
        expect(find.text('Columns'), findsOneWidget);
      }
    });
  }
}
