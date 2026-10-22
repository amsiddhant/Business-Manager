import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_x.dart';
import '../../core/utils/csv_export.dart';
import '../../core/utils/date_utils.dart';
import '../../models/app_settings.dart';
import '../../state/org_settings.dart';
import '../../state/user_prefs.dart';
import '../common/confirm_dialog.dart';
import '../common/state_views.dart';
import 'grid_bulk_bar.dart';
import 'grid_card_list.dart';
import 'grid_column.dart';
import 'grid_controller.dart';
import 'grid_toolbar.dart';
import 'grid_view_store.dart';

export 'grid_bulk_bar.dart' show BulkOutcome, runGridBulk;
export 'grid_column.dart';
export 'grid_controller.dart'
    show
        ChoiceValue,
        DateRangeValue,
        GridController,
        GridSort,
        NumberRangeValue;

/// The app's table: search, filters, multi-column sorting, paging, column
/// chooser, density, saved views, selection with bulk actions, CSV export,
/// column totals and keyboard navigation. Below [cardBreakpoint] wide it
/// shows the rows as cards.
///
/// Use [AppDataGrid] inside a page or card; on list pages use
/// [SliverAppDataGrid] so rows build lazily and the header stays pinned.
class AppDataGrid<T> extends StatefulWidget {
  const AppDataGrid({
    super.key,
    required this.rows,
    required this.columns,
    this.rowKey,
    this.gridId,
    this.controller,
    this.searchText,
    this.externalSearch = '',
    this.searchHint = 'Search…',
    this.showToolbar = true,
    this.showSearch = true,
    this.title,
    this.subtitle,
    this.toolbarActions = const [],
    this.quickFilters = const [],
    this.onRowTap,
    this.rowActions,
    this.bulkActions = const [],
    this.selectable,
    this.exportName,
    this.onExportAll,
    this.exportAllLabel = 'Export all fields (CSV)',
    this.emptyTitle = 'Nothing here yet',
    this.emptyMessage,
    this.emptyIcon = Icons.inbox_outlined,
    this.emptyAction,
    this.initialSort = const [],
    this.pageSize,
    this.framed = true,
    this.cardBreakpoint = AppSpacing.mobileMax,
  });

  final List<T> rows;
  final List<GridColumn<T>> columns;

  /// Identifies a row for selection (e.g. its id). Defaults to the row.
  final Object Function(T row)? rowKey;

  /// Remembers this grid's layout and saved views per user when set.
  final String? gridId;

  /// Pass one to drive the grid from outside; otherwise it makes its own.
  final GridController? controller;

  /// A row's searchable text. Defaults to its columns' export values.
  final String Function(T row)? searchText;

  /// A search typed somewhere else (a page's own search box).
  final String externalSearch;
  final String searchHint;
  final bool showToolbar;
  final bool showSearch;
  final String? title;
  final String? subtitle;

  /// Extra buttons in the toolbar (Import…).
  final List<Widget> toolbarActions;
  final List<GridQuickFilter<T>> quickFilters;
  final void Function(T row)? onRowTap;

  /// The labelled actions in each row's ⋮ menu.
  final List<GridRowAction<T>> Function(T row)? rowActions;
  final List<GridBulkAction<T>> bulkActions;

  /// Shows tick boxes. Defaults to on when there are [bulkActions].
  final bool? selectable;

  /// Turns on "Export this view" (and "Export selected"); the file is named
  /// after it.
  final String? exportName;

  /// An export of every field in the importer's format.
  final VoidCallback? onExportAll;
  final String exportAllLabel;

  final String emptyTitle;
  final String? emptyMessage;
  final IconData emptyIcon;
  final Widget? emptyAction;
  final List<GridSort> initialSort;

  /// Rows per page; null follows the organisation's default.
  final int? pageSize;

  /// Draws the grid's own card. Turn off inside a card that already has one.
  final bool framed;

  /// Narrower than this, rows become cards.
  final double cardBreakpoint;

  /// Whether this is the sliver variant.
  bool get sliver => false;

  @override
  State<AppDataGrid<T>> createState() => _AppDataGridState<T>();
}

/// [AppDataGrid] for a [CustomScrollView] (e.g. `AppPage.slivers`): the rows
/// build as they scroll into view and the header stays pinned under the top
/// bar. When the columns don't fit, or on a phone, it falls back to the box
/// layout.
class SliverAppDataGrid<T> extends AppDataGrid<T> {
  const SliverAppDataGrid({
    super.key,
    required super.rows,
    required super.columns,
    super.rowKey,
    super.gridId,
    super.controller,
    super.searchText,
    super.externalSearch,
    super.searchHint,
    super.showToolbar,
    super.showSearch,
    super.title,
    super.subtitle,
    super.toolbarActions,
    super.quickFilters,
    super.onRowTap,
    super.rowActions,
    super.bulkActions,
    super.selectable,
    super.exportName,
    super.onExportAll,
    super.exportAllLabel,
    super.emptyTitle,
    super.emptyMessage,
    super.emptyIcon,
    super.emptyAction,
    super.initialSort,
    super.pageSize,
    super.framed,
    super.cardBreakpoint,
  });

  @override
  bool get sliver => true;
}

/// The header row's height.
const double _headerHeight = 44;

/// Space at each end of a row.
const double _edge = AppSpacing.sm;
const double _selectWidth = 44;
const double _menuWidth = 48;

/// The CSV for [rows]: a header of the [columns] that have export values,
/// then one line per row.
List<List<String>> gridCsv<T>(List<GridColumn<T>> columns, List<T> rows) {
  final cols = [for (final c in columns) if (c.exportValue != null) c];
  return [
    [for (final c in cols) c.label],
    for (final r in rows) [for (final c in cols) c.exportValue!(r)],
  ];
}

class _ColumnLayout<T> {
  const _ColumnLayout(this.columns, this.widths, this.width, this.overflow);

  final List<GridColumn<T>> columns;
  final List<double> widths;

  /// The table's full width.
  final double width;

  /// The columns don't fit: the table scrolls sideways.
  final bool overflow;
}

class _AppDataGridState<T> extends State<AppDataGrid<T>> {
  GridController? _own;
  GridViewStore? _store;
  bool _restored = false;
  int _savedLayout = -1;
  Timer? _saveTimer;
  final _hScroll = ScrollController();
  final List<FocusNode> _rowNodes = [];

  GridController get _c => widget.controller ?? _own!;

  // Set in build from the organisation's settings.
  bool _bulkOn = true;
  bool _zebra = false;
  bool _sticky = true;
  AppDensity? _orgDensity;
  bool _savedViewsOn = true;
  bool _exportOn = true;

  /// Tick boxes and bulk actions are off for everyone when the organisation
  /// turns bulk actions off.
  bool get _selectable =>
      _bulkOn && (widget.selectable ?? widget.bulkActions.isNotEmpty);

  /// Rows per page before the user picks their own.
  int get _startPageSize =>
      widget.pageSize ?? context.readOrgSettings().defaults.pageSize;

  Object _key(T row) => widget.rowKey?.call(row) ?? row as Object;

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) {
      _own = GridController(
          sorts: widget.initialSort, pageSize: _startPageSize);
    }
    _c.addListener(_onChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_restored) return;
    _restored = true;
    final id = widget.gridId;
    UserPrefs? prefs;
    if (id != null) {
      try {
        prefs = context.read<UserPrefs>();
      } on ProviderNotFoundException {
        prefs = null;
      }
    }
    final store = prefs == null ? null : _store = GridViewStore(prefs, id!);
    final layout = store?.loadLayout();
    _c.removeListener(_onChanged);
    if (layout != null) _c.restore(layout, layoutOnly: true);
    // The organisation's defaults fill in whatever the user hasn't chosen.
    if (layout?.pageSize == null && widget.controller == null) {
      _c.applyPageSize(_startPageSize);
    }
    final orgColumns =
        id == null ? null : context.readOrgSettings().tables.columnsFor(id);
    if (orgColumns != null &&
        (layout == null ||
            (layout.visibility.isEmpty && layout.order.isEmpty))) {
      _c.applyColumns(widget.columns, orgColumns);
    }
    _c.addListener(_onChanged);
    _savedLayout = _c.layoutVersion;
  }

  @override
  void didUpdateWidget(covariant AppDataGrid<T> old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      (old.controller ?? _own)?.removeListener(_onChanged);
      if (widget.controller == null) {
        _own ??= GridController(
            sorts: widget.initialSort, pageSize: _startPageSize);
      }
      _c.addListener(_onChanged);
    }
    if (!identical(old.rows, widget.rows) && _c.selectedCount > 0) {
      _c.pruneSelection({for (final r in widget.rows) _key(r)});
    }
    if (old.externalSearch != widget.externalSearch) _c.setPage(0);
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    if (_store != null && _c.layoutVersion != _savedLayout) {
      _store!.saveLayout(_c.snapshot(layoutOnly: true));
    }
    _c.removeListener(_onChanged);
    _own?.dispose();
    _hScroll.dispose();
    for (final n in _rowNodes) {
      n.dispose();
    }
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    setState(() {});
    final store = _store;
    if (store == null || _c.layoutVersion == _savedLayout) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () {
      _savedLayout = _c.layoutVersion;
      store.saveLayout(_c.snapshot(layoutOnly: true));
    });
  }

  FocusNode _nodeFor(int i) {
    while (_rowNodes.length <= i) {
      _rowNodes.add(FocusNode(debugLabel: 'grid row ${_rowNodes.length}'));
    }
    return _rowNodes[i];
  }

  void _focusRow(int i, int count) {
    if (i < 0 || i >= count) return;
    final node = _nodeFor(i);
    node.requestFocus();
    final ctx = node.context;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx,
          duration: context.motion.fast,
          alignmentPolicy: i == 0
              ? ScrollPositionAlignmentPolicy.keepVisibleAtStart
              : ScrollPositionAlignmentPolicy.keepVisibleAtEnd);
    }
  }

  // --------------------------------------------------------------- export --

  void _export(List<T> rows, {required bool selected}) {
    final csv = gridCsv(_c.visibleColumns(widget.columns), rows);
    final name = widget.exportName ?? 'export';
    CsvExport.download(
      filename: '$name${selected ? '-selected' : ''}-'
          '${AppDate.iso(DateTime.now())}.csv',
      header: csv.first,
      rows: csv.skip(1).toList(),
    );
    showSuccessSnack(context,
        'Exported ${rows.length} row${rows.length == 1 ? '' : 's'}');
  }

  Future<void> _runBulk(GridBulkAction<T> action, List<T> selected) async {
    final run = action.onRun;
    if (run == null) return;
    final allowed = action.allowed;
    final rows = allowed == null ? selected : selected.where(allowed).toList();
    final skipped = selected.length - rows.length;
    if (rows.isEmpty) {
      showErrorSnack(
          context, "You can't ${action.label.toLowerCase()} the selected rows.");
      return;
    }
    await run(context, rows);
    if (!mounted) return;
    _c.clearSelection();
    if (skipped > 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Skipped $skipped row${skipped == 1 ? '' : 's'} '
              "you can't change.")));
    }
  }

  // --------------------------------------------------------------- layout --

  _ColumnLayout<T> _layout(double available) {
    final cols = _c.visibleColumns(widget.columns);
    final fixed = (_selectable ? _selectWidth : 0) +
        (widget.rowActions != null ? _menuWidth : 0) +
        _edge * 2;
    final mins = [for (final c in cols) c.effectiveMinWidth];
    final minTotal = mins.fold<double>(fixed, (s, w) => s + w);
    final room = available.isFinite ? available : minTotal;
    // A pixel short of the room, so rounding never overflows the row.
    final spare = math.max(0.0, room - minTotal - 1);
    final flex = cols
        .where((c) => c.width == null)
        .fold<int>(0, (s, c) => s + math.max(c.flex, 0));
    final widths = [
      for (var i = 0; i < cols.length; i++)
        cols[i].width ??
            mins[i] + (flex == 0 ? 0 : spare * math.max(cols[i].flex, 0) / flex),
    ];
    return _ColumnLayout(
        cols, widths, math.max(room, minTotal), minTotal > room + 0.5);
  }

  // ---------------------------------------------------------------- build --

  @override
  Widget build(BuildContext context) {
    final org = context.orgSettings((s) => s);
    _bulkOn = org.features.isOn(AppFeature.bulkActions);
    _savedViewsOn = org.features.isOn(AppFeature.savedViews);
    _exportOn = org.features.isOn(AppFeature.csvExport);
    _zebra = org.tables.zebra;
    _sticky = org.tables.stickyHeader;
    _orgDensity = org.tables.density;
    final result = _c.apply<T>(
      widget.rows,
      widget.columns,
      searchText: widget.searchText,
      externalSearch: widget.externalSearch,
      quickFilters: widget.quickFilters,
    );
    if (widget.sliver) {
      return SliverLayoutBuilder(
        builder: (context, constraints) =>
            _buildSliver(context, result, constraints.crossAxisExtent),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) =>
          _buildBox(context, result, constraints.maxWidth),
    );
  }

  Widget _buildBox(BuildContext context, GridResult<T> r, double width) {
    final compact = width < widget.cardBreakpoint;
    final top = _top(context, r, compact: compact);
    final Widget body;
    if (r.isEmpty) {
      body = _empty(context, r);
    } else if (compact) {
      body = Padding(
        padding: EdgeInsets.only(top: top == null ? 0 : AppSpacing.xs),
        child: GridCardList<T>(
          rows: r.pageRows,
          columns: _c.visibleColumns(widget.columns),
          isSelected: _selectable ? (row) => _c.isSelected(_key(row)) : null,
          onToggle: _selectable ? (row) => _c.toggle(_key(row)) : null,
          onTap: widget.onRowTap,
          rowActions: widget.rowActions,
        ),
      );
    } else {
      final layout = _layout(width);
      Widget table = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(context, r, layout, roundTop: top == null),
          for (var i = 0; i < r.pageRows.length; i++) _row(context, r, layout, i),
          ?_totals(context, r, layout),
        ],
      );
      if (layout.overflow) {
        table = Scrollbar(
          controller: _hScroll,
          child: SingleChildScrollView(
            controller: _hScroll,
            scrollDirection: Axis.horizontal,
            child: SizedBox(width: layout.width, child: table),
          ),
        );
      }
      body = table;
    }
    final pager = _pager(context, r, compact: compact);
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [?top, body, ?pager],
    );
    if (compact || !widget.framed) return content;
    final radius = BorderRadius.circular(AppSpacing.radiusLg);
    return DecoratedBox(
      decoration: _surface(context),
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: _outline(context),
        child: ClipRRect(borderRadius: radius, child: content),
      ),
    );
  }

  // The card is drawn in two layers: the surface behind the rows, the
  // outline over them (so a header or hover colour never hides it).
  BoxDecoration _surface(BuildContext context) {
    final t = context.tokens;
    return BoxDecoration(
      color: t.card,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      boxShadow: t.cardShadow,
    );
  }

  BoxDecoration _outline(BuildContext context) => BoxDecoration(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: context.tokens.border),
      );

  Widget _buildSliver(BuildContext context, GridResult<T> r, double width) {
    final compact = width < widget.cardBreakpoint;
    final layout = _layout(width);
    if (compact || r.isEmpty || layout.overflow || !widget.framed) {
      return SliverToBoxAdapter(child: _buildBox(context, r, width));
    }
    final top = _top(context, r, compact: false);
    final pager = _pager(context, r, compact: false);
    final totals = _totals(context, r, layout);
    return DecoratedSliver(
      decoration: _surface(context),
      sliver: DecoratedSliver(
        position: DecorationPosition.foreground,
        decoration: _outline(context),
        sliver: SliverMainAxisGroup(
          slivers: [
            if (top != null) SliverToBoxAdapter(child: top),
            SliverPersistentHeader(
              pinned: _sticky,
              delegate: _PinnedHeader(
                (overlaps) => _header(context, r, layout,
                    roundTop: top == null && !overlaps, raised: overlaps),
              ),
            ),
            SliverList.builder(
              itemCount: r.pageRows.length,
              itemBuilder: (context, i) => _row(context, r, layout, i),
            ),
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ?totals,
                  pager ?? const SizedBox(height: AppSpacing.sm),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------- sections --

  Widget? _top(BuildContext context, GridResult<T> r, {required bool compact}) {
    final t = context.tokens;
    final motion = context.motion;
    final selecting = _selectable && _c.selectedCount > 0;
    final children = <Widget>[];

    if (widget.title != null) {
      children.add(Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.title!,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: t.textPrimary)),
                if (widget.subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(widget.subtitle!,
                      style:
                          TextStyle(fontSize: 12.5, color: t.textSecondary)),
                ],
              ],
            ),
          ),
          if (!widget.showToolbar) ...widget.toolbarActions,
        ],
      ));
    }

    Widget? bar;
    if (selecting) {
      final selected = [
        for (final row in r.all)
          if (_c.isSelected(_key(row))) row,
      ];
      bar = GridBulkBar<T>(
        key: const ValueKey('bulk'),
        selected: selected,
        matching: r.total,
        onSelectAll: () => _c.setSelected([for (final row in r.all) _key(row)], true),
        onClear: _c.clearSelection,
        onExport: widget.exportName == null || !_exportOn
            ? null
            : () => _export(selected, selected: true),
        actions: widget.bulkActions,
        onAction: (a) => _runBulk(a, selected),
      );
    } else if (widget.showToolbar) {
      bar = GridToolbar<T>(
        key: const ValueKey('toolbar'),
        controller: _c,
        columns: widget.columns,
        rows: widget.rows,
        store: _savedViewsOn ? _store : null,
        gridId: widget.gridId,
        compact: compact,
        showSearch: widget.showSearch,
        searchHint: widget.searchHint,
        onExportView: widget.exportName == null || !_exportOn
            ? null
            : () => _export(r.all, selected: false),
        onExportAll: _exportOn ? widget.onExportAll : null,
        exportAllLabel: widget.exportAllLabel,
        actions: widget.toolbarActions,
      );
    }
    if (bar != null) {
      children.add(AnimatedSwitcher(
        duration: motion.fast,
        child: bar,
      ));
    }

    if (_c.filters.isNotEmpty) {
      children.add(GridFilterChips<T>(
          controller: _c, columns: widget.columns, rows: widget.rows));
    }

    if (widget.quickFilters.isNotEmpty && r.unfilteredTotal > 0) {
      children.add(_QuickFilters<T>(
        filters: widget.quickFilters,
        selected: _c.quick,
        allCount: r.baseTotal,
        counts: r.quickCounts,
        onSelected: _c.setQuick,
      ));
    }

    if (children.isEmpty) return null;
    return Padding(
      padding: compact
          ? const EdgeInsets.only(bottom: AppSpacing.sm)
          : const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.md),
            children[i],
          ],
        ],
      ),
    );
  }

  Widget _header(BuildContext context, GridResult<T> r, _ColumnLayout<T> l,
      {bool roundTop = false, bool raised = false}) {
    final t = context.tokens;
    final keys = [for (final row in r.pageRows) _key(row)];
    final ticked = keys.where(_c.isSelected).length;
    final sorts = _c.sorts;
    final header = Container(
      height: _headerHeight,
      padding: const EdgeInsets.symmetric(horizontal: _edge),
      decoration: BoxDecoration(
        color: t.surfaceAlt,
        border: Border(
          top: roundTop ? BorderSide.none : BorderSide(color: t.border),
          bottom: BorderSide(color: t.border),
        ),
        boxShadow: raised ? t.cardShadow : null,
      ),
      child: Row(
        children: [
          if (_selectable)
            SizedBox(
              width: _selectWidth,
              child: Center(
                child: Checkbox(
                  tristate: true,
                  value: ticked == 0
                      ? false
                      : ticked == keys.length
                          ? true
                          : null,
                  semanticLabel: 'Select all on this page',
                  onChanged: keys.isEmpty
                      ? null
                      : (_) => _c.setSelected(keys, ticked != keys.length),
                ),
              ),
            ),
          for (var i = 0; i < l.columns.length; i++)
            SizedBox(
              width: l.widths[i],
              child: _HeaderCell<T>(
                column: l.columns[i],
                sort: _c.sortOf(l.columns[i].id),
                showPriority: sorts.length > 1,
                onSort: (additive) =>
                    _c.sortBy(l.columns[i].id, additive: additive),
              ),
            ),
          if (widget.rowActions != null) const SizedBox(width: _menuWidth),
        ],
      ),
    );
    if (!roundTop) return header;
    return ClipRRect(
      borderRadius:
          const BorderRadius.vertical(top: Radius.circular(AppSpacing.radiusLg)),
      child: header,
    );
  }

  Widget _row(BuildContext context, GridResult<T> r, _ColumnLayout<T> l, int i) {
    final t = context.tokens;
    final density = _c.density ?? _orgDensity ?? context.density;
    final row = r.pageRows[i];
    final key = _key(row);
    final selected = _selectable && _c.isSelected(key);
    final actions = widget.rowActions?.call(row);
    final count = r.pageRows.length;

    void toggle() {
      if (HardwareKeyboard.instance.isShiftPressed) {
        _c.selectRange([for (final x in r.pageRows) _key(x)], key);
      } else {
        _c.toggle(key);
      }
    }

    return _GridRow(
      focusNode: _nodeFor(i),
      selected: selected,
      striped: _zebra && i.isOdd,
      minHeight: density.rowHeight,
      onTap: widget.onRowTap == null ? null : () => widget.onRowTap!(row),
      onToggle: _selectable ? toggle : null,
      onMove: (d) => _focusRow(i + d, count),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: _edge),
        child: Row(
          children: [
            if (_selectable)
              SizedBox(
                width: _selectWidth,
                child: Center(
                  child: Checkbox(
                    value: selected,
                    semanticLabel: 'Select row',
                    onChanged: (_) => toggle(),
                  ),
                ),
              ),
            for (var c = 0; c < l.columns.length; c++)
              SizedBox(
                width: l.widths[c],
                child: Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: density == AppDensity.compact ? 4 : 8),
                  child: Align(
                    alignment: l.columns[c].numeric
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: DefaultTextStyle.merge(
                      style: TextStyle(
                        fontSize: 13.5,
                        color: t.textPrimary,
                        fontFeatures: l.columns[c].numeric
                            ? const [FontFeature.tabularFigures()]
                            : null,
                      ),
                      child: l.columns[c].cell(row),
                    ),
                  ),
                ),
              ),
            if (widget.rowActions != null)
              SizedBox(
                width: _menuWidth,
                child: actions == null || actions.isEmpty
                    ? null
                    : GridRowMenu<T>(row: row, actions: actions),
              ),
          ],
        ),
      ),
    );
  }

  Widget? _totals(BuildContext context, GridResult<T> r, _ColumnLayout<T> l) {
    if (!l.columns.any((c) => c.footer != null)) return null;
    final t = context.tokens;
    final style = TextStyle(
      fontSize: 13.5,
      fontWeight: FontWeight.w700,
      color: t.textPrimary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: _edge),
      decoration: BoxDecoration(
        color: t.surfaceAlt,
        border: Border(bottom: BorderSide(color: t.border)),
      ),
      child: Row(
        children: [
          if (_selectable) const SizedBox(width: _selectWidth),
          for (var c = 0; c < l.columns.length; c++)
            SizedBox(
              width: l.widths[c],
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                child: Text(
                  l.columns[c].footer?.call(r.all) ??
                      (c == 0 ? 'Total · ${r.total}' : ''),
                  textAlign:
                      l.columns[c].numeric ? TextAlign.right : TextAlign.left,
                  style: style,
                ),
              ),
            ),
          if (widget.rowActions != null) const SizedBox(width: _menuWidth),
        ],
      ),
    );
  }

  Widget? _pager(BuildContext context, GridResult<T> r, {required bool compact}) {
    if (r.total <= GridController.pageSizes.first && r.pageCount <= 1) {
      return null;
    }
    final t = context.tokens;
    final from = r.total == 0 ? 0 : r.start + 1;
    final to = r.start + r.pageRows.length;
    final style = TextStyle(
      fontSize: 12.5,
      color: t.textSecondary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final range = Text(
      '$from–$to of ${r.total}'
      '${r.total != r.unfilteredTotal ? ' · ${r.unfilteredTotal} in all' : ''}',
      style: style,
      overflow: TextOverflow.ellipsis,
    );
    final prev = IconButton(
      tooltip: 'Previous page',
      visualDensity: VisualDensity.compact,
      icon: const Icon(Icons.chevron_left),
      onPressed: r.page > 0 ? () => _c.setPage(r.page - 1) : null,
    );
    final next = IconButton(
      tooltip: 'Next page',
      visualDensity: VisualDensity.compact,
      icon: const Icon(Icons.chevron_right),
      onPressed: r.page < r.pageCount - 1 ? () => _c.setPage(r.page + 1) : null,
    );

    if (compact) {
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.sm),
        child: Row(
          children: [
            Expanded(child: range),
            prev,
            Text('${r.page + 1} / ${r.pageCount}', style: style),
            next,
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      child: Row(
        children: [
          Text('Rows per page', style: style),
          const SizedBox(width: AppSpacing.sm),
          DropdownButton<int>(
            value: _c.pageSize,
            isDense: true,
            underline: const SizedBox.shrink(),
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            style: style.copyWith(color: t.textPrimary),
            items: [
              for (final s in _pageSizes(_c.pageSize))
                DropdownMenuItem(value: s, child: Text(s == 0 ? 'All' : '$s')),
            ],
            onChanged: (s) {
              if (s != null) _c.setPageSize(s);
            },
          ),
          const SizedBox(width: AppSpacing.lg),
          Flexible(child: range),
          const Spacer(),
          prev,
          for (final p in _pageNumbers(r.page, r.pageCount))
            p == null
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text('…', style: style),
                  )
                : _PageButton(
                    page: p,
                    current: p == r.page,
                    onPressed: () => _c.setPage(p),
                  ),
          next,
        ],
      ),
    );
  }

  /// The usual page sizes, plus [current] if a grid starts on another one.
  static List<int> _pageSizes(int current) {
    final sizes = GridController.pageSizes;
    if (sizes.contains(current)) return sizes;
    return [
      ...sizes.where((s) => s > 0 && s < current),
      current,
      ...sizes.where((s) => s == 0 || s > current),
    ];
  }

  /// The page numbers to show, with null for a gap: 1 … 4 5 6 … 20.
  static List<int?> _pageNumbers(int page, int count) {
    if (count <= 7) return [for (var i = 0; i < count; i++) i];
    final keep = {0, count - 1, page - 1, page, page + 1}
        .where((p) => p >= 0 && p < count)
        .toList()
      ..sort();
    final out = <int?>[];
    for (final p in keep) {
      if (out.isNotEmpty && out.last != null && p - out.last! > 1) out.add(null);
      out.add(p);
    }
    return out;
  }

  Widget _empty(BuildContext context, GridResult<T> r) {
    if (r.unfilteredTotal == 0) {
      return EmptyView(
        title: widget.emptyTitle,
        message: widget.emptyMessage,
        icon: widget.emptyIcon,
        action: widget.emptyAction,
      );
    }
    final outside = widget.externalSearch.trim();
    return EmptyView(
      icon: Icons.search_off,
      title: 'No matches',
      message: _c.hasFilters
          ? 'Nothing matches the current search and filters.'
          : 'Nothing matches "$outside". Try a different search.',
      action: _c.hasFilters
          ? OutlinedButton.icon(
              onPressed: _c.clearFilters,
              icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
              label: const Text('Clear filters'),
            )
          : null,
    );
  }
}

class _PinnedHeader extends SliverPersistentHeaderDelegate {
  _PinnedHeader(this.builder);

  final Widget Function(bool overlapsContent) builder;

  @override
  double get minExtent => _headerHeight;

  @override
  double get maxExtent => _headerHeight;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) =>
      builder(overlapsContent);

  @override
  bool shouldRebuild(covariant _PinnedHeader oldDelegate) => true;
}

class _HeaderCell<T> extends StatelessWidget {
  const _HeaderCell({
    required this.column,
    required this.sort,
    required this.showPriority,
    required this.onSort,
  });

  final GridColumn<T> column;
  final (int, bool)? sort;
  final bool showPriority;
  final void Function(bool additive) onSort;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final active = sort != null;
    final style = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.6,
      color: active ? t.textPrimary : t.textSecondary,
    );
    final label = Text(
      column.label.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: column.numeric ? TextAlign.right : TextAlign.left,
      style: style,
    );
    final children = <Widget>[
      Flexible(child: label),
      if (column.tooltip != null) ...[
        const SizedBox(width: 4),
        Icon(Icons.info_outline, size: 13, color: t.textTertiary),
      ],
      if (column.sortable) ...[
        const SizedBox(width: 2),
        if (sort case (final index, final asc))
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(asc ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 14, color: t.primary),
              if (showPriority)
                Text('${index + 1}',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: t.primary)),
            ],
          )
        else
          Icon(Icons.unfold_more,
              size: 14, color: t.textTertiary.withValues(alpha: 0.6)),
      ],
    ];

    Widget cell = Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Row(
        mainAxisAlignment:
            column.numeric ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: children,
      ),
    );
    if (column.sortable) {
      final order = switch (sort) {
        (_, true) => ', sorted ascending',
        (_, false) => ', sorted descending',
        null => '',
      };
      cell = Semantics(
        button: true,
        label: 'Sort by ${column.label}$order',
        excludeSemantics: true,
        child: InkWell(
          onTap: () => onSort(HardwareKeyboard.instance.isShiftPressed),
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          child: SizedBox(height: _headerHeight - 8, child: cell),
        ),
      );
    }
    final tip = column.tooltip ??
        (column.sortable ? 'Shift+click to sort by more than one column' : null);
    if (tip != null) {
      cell = Tooltip(
          message: tip,
          waitDuration: const Duration(milliseconds: 700),
          child: cell);
    }
    return cell;
  }
}

class _GridRow extends StatefulWidget {
  const _GridRow({
    required this.focusNode,
    required this.selected,
    required this.striped,
    required this.minHeight,
    required this.onTap,
    required this.onToggle,
    required this.onMove,
    required this.child,
  });

  final FocusNode focusNode;
  final bool selected;

  /// Shaded for the organisation's alternating rows.
  final bool striped;
  final double minHeight;
  final VoidCallback? onTap;
  final VoidCallback? onToggle;
  final void Function(int delta) onMove;
  final Widget child;

  @override
  State<_GridRow> createState() => _GridRowState();
}

class _GridRowState extends State<_GridRow> {
  bool _hover = false;
  bool _focused = false;

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    // Keys pressed on a button inside the row belong to that button.
    if (!node.hasPrimaryFocus || e is KeyUpEvent) return KeyEventResult.ignored;
    final key = e.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      widget.onMove(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      widget.onMove(-1);
      return KeyEventResult.handled;
    }
    if (e is KeyRepeatEvent) return KeyEventResult.ignored;
    if ((key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter) &&
        widget.onTap != null) {
      widget.onTap!();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.space && widget.onToggle != null) {
      widget.onToggle!();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ring = _focused &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    final color = widget.selected
        ? t.primarySurface
        : _hover
            ? t.hover
            : widget.striped
                ? t.surfaceAlt
                : null;
    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: _onKey,
      onFocusChange: (f) => setState(() => _focused = f),
      child: MouseRegion(
        cursor: widget.onTap != null
            ? SystemMouseCursors.click
            : MouseCursor.defer,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            constraints: BoxConstraints(minHeight: widget.minHeight),
            decoration: BoxDecoration(
              color: color,
              border: Border(bottom: BorderSide(color: t.border)),
            ),
            foregroundDecoration: ring
                ? BoxDecoration(
                    border: Border.all(color: t.focusRing, width: 2),
                  )
                : null,
            child: Align(
              alignment: Alignment.centerLeft,
              widthFactor: 1,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickFilters<T> extends StatelessWidget {
  const _QuickFilters({
    required this.filters,
    required this.selected,
    required this.allCount,
    required this.counts,
    required this.onSelected,
  });

  final List<GridQuickFilter<T>> filters;
  final String? selected;
  final int allCount;
  final Map<String, int> counts;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    Widget chip(String? id, String label, int count, IconData? icon) {
      final on = selected == id;
      return Padding(
        padding: const EdgeInsets.only(right: AppSpacing.sm),
        child: _QuickChip(
          label: label,
          count: count,
          icon: icon,
          selected: on,
          onTap: () => onSelected(on ? null : id),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          chip(null, 'All', allCount, null),
          for (final f in filters) chip(f.id, f.label, counts[f.id] ?? 0, f.icon),
        ],
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  const _QuickChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final fg = selected ? t.textOnPrimary : t.textPrimary;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? t.primary : t.surfaceAlt,
        shape: StadiumBorder(
            side: BorderSide(color: selected ? t.primary : t.border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: fg),
                  const SizedBox(width: 6),
                ],
                Text(label,
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600, color: fg)),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: selected
                        ? t.textOnPrimary.withValues(alpha: 0.2)
                        : t.card,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text('$count',
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: fg,
                          fontFeatures: const [FontFeature.tabularFigures()])),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PageButton extends StatelessWidget {
  const _PageButton({
    required this.page,
    required this.current,
    required this.onPressed,
  });

  final int page;
  final bool current;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: SizedBox(
        width: 32,
        height: 32,
        child: TextButton(
          onPressed: current ? null : onPressed,
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size(32, 32),
            backgroundColor: current ? t.primarySurface : null,
            disabledForegroundColor: t.primary,
            foregroundColor: t.textSecondary,
            textStyle: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                fontFeatures: [FontFeature.tabularFigures()]),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm)),
          ),
          child: Text('${page + 1}',
              semanticsLabel: current
                  ? 'Page ${page + 1}, current page'
                  : 'Page ${page + 1}'),
        ),
      ),
    );
  }
}
