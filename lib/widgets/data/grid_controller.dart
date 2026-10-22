import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../core/theme/app_density.dart';
import 'grid_column.dart';

/// One sort key: a column and its direction.
@immutable
class GridSort {
  const GridSort(this.columnId, {this.ascending = true});

  final String columnId;
  final bool ascending;

  Map<String, Object> toJson() => {'c': columnId, 'a': ascending};

  static GridSort? fromJson(Object? json) {
    if (json is! Map) return null;
    final c = json['c'];
    if (c is! String || c.isEmpty) return null;
    return GridSort(c, ascending: json['a'] != false);
  }

  @override
  bool operator ==(Object other) =>
      other is GridSort &&
      other.columnId == columnId &&
      other.ascending == ascending;

  @override
  int get hashCode => Object.hash(columnId, ascending);
}

/// What a column's filter is set to.
sealed class GridFilterValue {
  const GridFilterValue();

  Map<String, Object?> toJson();

  static GridFilterValue? fromJson(Object? json) {
    if (json is! Map) return null;
    switch (json['t']) {
      case 'choice':
        final v = json['v'];
        if (v is! List) return null;
        final values = {for (final e in v) if (e is String) e};
        return values.isEmpty ? null : ChoiceValue(values);
      case 'date':
        final s = DateTime.tryParse('${json['s']}');
        final e = DateTime.tryParse('${json['e']}');
        if (s == null || e == null) return null;
        return DateRangeValue(s, e);
      case 'number':
        final min = json['min'], max = json['max'];
        final value = NumberRangeValue(
            min: min is num ? min : null, max: max is num ? max : null);
        return value.min == null && value.max == null ? null : value;
    }
    return null;
  }
}

/// Rows whose value is one of [values].
class ChoiceValue extends GridFilterValue {
  const ChoiceValue(this.values);
  final Set<String> values;

  @override
  Map<String, Object?> toJson() => {'t': 'choice', 'v': values.toList()};

  @override
  bool operator ==(Object other) =>
      other is ChoiceValue && setEquals(other.values, values);

  @override
  int get hashCode => Object.hashAllUnordered(values);
}

/// Rows dated from [start] to [end], both days included.
class DateRangeValue extends GridFilterValue {
  const DateRangeValue(this.start, this.end);
  final DateTime start;
  final DateTime end;

  bool contains(DateTime d) {
    final from = DateTime(start.year, start.month, start.day);
    final to = DateTime(end.year, end.month, end.day + 1);
    return !d.isBefore(from) && d.isBefore(to);
  }

  @override
  Map<String, Object?> toJson() => {
        't': 'date',
        's': start.toIso8601String(),
        'e': end.toIso8601String(),
      };

  @override
  bool operator ==(Object other) =>
      other is DateRangeValue && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

/// Rows whose figure is at least [min] and at most [max] (either may be open).
class NumberRangeValue extends GridFilterValue {
  const NumberRangeValue({this.min, this.max});
  final num? min;
  final num? max;

  bool contains(num v) => (min == null || v >= min!) && (max == null || v <= max!);

  @override
  Map<String, Object?> toJson() => {'t': 'number', 'min': min, 'max': max};

  @override
  bool operator ==(Object other) =>
      other is NumberRangeValue && other.min == min && other.max == max;

  @override
  int get hashCode => Object.hash(min, max);
}

/// Everything about how a grid is set up, for saved views and for
/// remembering a grid's layout between visits.
@immutable
class GridViewState {
  const GridViewState({
    this.search = '',
    this.filters = const {},
    this.quick,
    this.sorts = const [],
    this.pageSize,
    this.density,
    this.visibility = const {},
    this.order = const [],
  });

  final String search;
  final Map<String, GridFilterValue> filters;
  final String? quick;
  final List<GridSort> sorts;
  final int? pageSize;
  final AppDensity? density;
  final Map<String, bool> visibility;
  final List<String> order;

  Map<String, Object?> toJson() => {
        if (search.isNotEmpty) 'search': search,
        if (filters.isNotEmpty)
          'filters': {
            for (final e in filters.entries) e.key: e.value.toJson(),
          },
        'quick': ?quick,
        'sorts': [for (final s in sorts) s.toJson()],
        'pageSize': ?pageSize,
        'density': ?density?.name,
        if (visibility.isNotEmpty) 'visibility': visibility,
        if (order.isNotEmpty) 'order': order,
      };

  static GridViewState fromJson(Object? json) {
    if (json is! Map) return const GridViewState();
    final filters = <String, GridFilterValue>{};
    final f = json['filters'];
    if (f is Map) {
      for (final e in f.entries) {
        if (e.key is! String) continue;
        final v = GridFilterValue.fromJson(e.value);
        if (v != null) filters[e.key as String] = v;
      }
    }
    final s = json['sorts'];
    final v = json['visibility'];
    final o = json['order'];
    final size = json['pageSize'];
    final density = json['density'];
    return GridViewState(
      search: json['search'] is String ? json['search'] as String : '',
      filters: filters,
      quick: json['quick'] is String ? json['quick'] as String : null,
      sorts: [
        if (s is List)
          for (final e in s) ?GridSort.fromJson(e),
      ],
      pageSize: size is int && GridController.pageSizes.contains(size)
          ? size
          : null,
      density: density is String
          ? AppDensity.values.where((d) => d.name == density).firstOrNull
          : null,
      visibility: {
        if (v is Map)
          for (final e in v.entries)
            if (e.key is String && e.value is bool)
              e.key as String: e.value as bool,
      },
      order: [
        if (o is List)
          for (final e in o)
            if (e is String) e,
      ],
    );
  }
}

/// The rows a grid shows, after search, filters, sorting and paging.
class GridResult<T> {
  const GridResult({
    required this.all,
    required this.pageRows,
    required this.page,
    required this.pageCount,
    required this.start,
    required this.unfilteredTotal,
    required this.baseTotal,
    required this.quickCounts,
  });

  /// Every matching row, sorted.
  final List<T> all;

  /// The rows on [page].
  final List<T> pageRows;
  final int page;
  final int pageCount;

  /// Index in [all] of the first row on the page.
  final int start;

  /// How many rows there are before anything is filtered out.
  final int unfilteredTotal;

  /// How many rows match the search and column filters, before the quick
  /// filter (the "All" chip's count).
  final int baseTotal;

  /// How many rows each quick filter would show.
  final Map<String, int> quickCounts;

  int get total => all.length;
  bool get isEmpty => all.isEmpty;
}

/// A grid's search, filters, sorting, paging, columns and selection.
///
/// Holds no rows itself: [apply] works the current settings out over the
/// rows it's given, and remembers the answer until the rows or the settings
/// change.
class GridController extends ChangeNotifier {
  GridController({List<GridSort> sorts = const [], int pageSize = 25})
      : _sorts = List.of(sorts),
        _defaultSorts = List.of(sorts),
        _pageSize = pageSize;

  /// The page sizes on offer; 0 is "All".
  static const pageSizes = [10, 25, 50, 100, 0];

  String _search = '';
  final Map<String, GridFilterValue> _filters = {};
  String? _quick;
  List<GridSort> _sorts;
  final List<GridSort> _defaultSorts;
  int _page = 0;
  int _pageSize;
  AppDensity? _density;
  final Map<String, bool> _visibility = {};
  List<String> _order = const [];
  final Set<Object> _selected = {};
  Object? _anchor;

  int _queryVersion = 0;
  int _layoutVersion = 0;

  /// Changes whenever a setting that's worth remembering does (sorting, page
  /// size, density, columns).
  int get layoutVersion => _layoutVersion;

  void _changed({bool query = false, bool layout = false, bool resetPage = false}) {
    if (resetPage) _page = 0;
    if (query || resetPage) _queryVersion++;
    if (layout) _layoutVersion++;
    notifyListeners();
  }

  // --------------------------------------------------------------- search --

  String get search => _search;

  void setSearch(String value) {
    if (value == _search) return;
    _search = value;
    _changed(resetPage: true);
  }

  // -------------------------------------------------------------- filters --

  Map<String, GridFilterValue> get filters => Map.unmodifiable(_filters);
  GridFilterValue? filterFor(String columnId) => _filters[columnId];

  void setFilter(String columnId, GridFilterValue? value) {
    if (value == null || (value is ChoiceValue && value.values.isEmpty)) {
      if (_filters.remove(columnId) == null) return;
    } else {
      if (_filters[columnId] == value) return;
      _filters[columnId] = value;
    }
    _changed(resetPage: true);
  }

  String? get quick => _quick;

  void setQuick(String? id) {
    if (id == _quick) return;
    _quick = id;
    _changed(resetPage: true);
  }

  bool get hasFilters =>
      _search.isNotEmpty || _filters.isNotEmpty || _quick != null;

  /// Clears the search, the column filters and the quick filter.
  void clearFilters() {
    if (!hasFilters) return;
    _search = '';
    _filters.clear();
    _quick = null;
    _changed(resetPage: true);
  }

  // -------------------------------------------------------------- sorting --

  List<GridSort> get sorts => List.unmodifiable(_sorts);

  /// The column's place in the sort order (0 first) and direction, if it's
  /// sorted.
  (int, bool)? sortOf(String columnId) {
    for (var i = 0; i < _sorts.length; i++) {
      if (_sorts[i].columnId == columnId) return (i, _sorts[i].ascending);
    }
    return null;
  }

  /// A header click: ascending, then descending, then back to the default.
  /// With [additive] (Shift+click) the column is added as a tiebreaker
  /// instead of replacing the sort.
  void sortBy(String columnId, {bool additive = false}) {
    final current = sortOf(columnId);
    List<GridSort> next;
    if (!additive) {
      if (current == null || _sorts.length > 1) {
        next = [GridSort(columnId)];
      } else if (current.$2) {
        next = [GridSort(columnId, ascending: false)];
      } else {
        // A third click goes back to the default order (or round again when
        // this already is the default).
        next = listEquals(_sorts, _defaultSorts)
            ? [GridSort(columnId)]
            : List.of(_defaultSorts);
      }
    } else {
      next = List.of(_sorts);
      if (current == null) {
        next.add(GridSort(columnId));
      } else if (current.$2) {
        next[current.$1] = GridSort(columnId, ascending: false);
      } else {
        next.removeAt(current.$1);
      }
    }
    _sorts = next;
    _changed(query: true, layout: true);
  }

  void setSorts(List<GridSort> sorts) {
    if (listEquals(sorts, _sorts)) return;
    _sorts = List.of(sorts);
    _changed(query: true, layout: true);
  }

  // --------------------------------------------------------------- paging --

  int get page => _page;
  int get pageSize => _pageSize;

  void setPage(int page) {
    if (page == _page || page < 0) return;
    _page = page;
    _changed(query: true);
  }

  void setPageSize(int size) {
    if (size == _pageSize || !pageSizes.contains(size)) return;
    _pageSize = size;
    _changed(layout: true, resetPage: true);
  }

  // -------------------------------------------------------------- density --

  /// The grid's own density, or null to follow the app's.
  AppDensity? get density => _density;

  void setDensity(AppDensity? density) {
    if (density == _density) return;
    _density = density;
    _changed(layout: true);
  }

  // -------------------------------------------------------------- columns --

  bool isVisible<T>(GridColumn<T> c) =>
      c.pinned || (_visibility[c.id] ?? c.visibleByDefault);

  void setVisible(String columnId, bool visible) {
    if (_visibility[columnId] == visible) return;
    _visibility[columnId] = visible;
    _changed(layout: true);
  }

  List<String> get order => List.unmodifiable(_order);

  void setOrder(List<String> ids) {
    if (listEquals(ids, _order)) return;
    _order = List.unmodifiable(ids);
    _changed(layout: true);
  }

  bool get hasColumnChanges => _visibility.isNotEmpty || _order.isNotEmpty;

  void resetColumns() {
    if (!hasColumnChanges) return;
    _visibility.clear();
    _order = const [];
    _changed(layout: true);
  }

  /// Every column in the user's order; pinned ones first, and columns the
  /// saved order doesn't know (added since) after the rest.
  List<GridColumn<T>> orderedColumns<T>(List<GridColumn<T>> columns) {
    final pinned = [for (final c in columns) if (c.pinned) c];
    final rest = [for (final c in columns) if (!c.pinned) c];
    if (_order.isNotEmpty) {
      final rank = {for (var i = 0; i < _order.length; i++) _order[i]: i};
      final known = [for (final c in rest) if (rank.containsKey(c.id)) c]
        ..sort((a, b) => rank[a.id]!.compareTo(rank[b.id]!));
      final unknown = [for (final c in rest) if (!rank.containsKey(c.id)) c];
      return [...pinned, ...known, ...unknown];
    }
    return [...pinned, ...rest];
  }

  List<GridColumn<T>> visibleColumns<T>(List<GridColumn<T>> columns) =>
      [for (final c in orderedColumns(columns)) if (isVisible(c)) c];

  // ------------------------------------------------------------ selection --

  Set<Object> get selected => Set.unmodifiable(_selected);
  int get selectedCount => _selected.length;
  bool isSelected(Object key) => _selected.contains(key);

  void toggle(Object key) {
    if (!_selected.remove(key)) _selected.add(key);
    _anchor = key;
    _changed();
  }

  /// Shift+click: selects everything from the last toggled row to [key] in
  /// [ordered] (the rows as shown).
  void selectRange(List<Object> ordered, Object key) {
    final from = _anchor == null ? -1 : ordered.indexOf(_anchor!);
    final to = ordered.indexOf(key);
    if (from < 0 || to < 0) {
      toggle(key);
      return;
    }
    _selected.addAll(ordered.sublist(math.min(from, to), math.max(from, to) + 1));
    _anchor = key;
    _changed();
  }

  void setSelected(Iterable<Object> keys, bool selected) {
    selected ? _selected.addAll(keys) : _selected.removeAll(keys);
    _changed();
  }

  void clearSelection() {
    if (_selected.isEmpty) return;
    _selected.clear();
    _anchor = null;
    _changed();
  }

  /// Drops selected keys that are no longer among the rows (deleted, or out
  /// of scope). Returns whether anything was dropped.
  bool pruneSelection(Set<Object> present) {
    final before = _selected.length;
    _selected.retainWhere(present.contains);
    return _selected.length != before;
  }

  // ---------------------------------------------------------------- views --

  /// The settings, for a saved view or for remembering the layout.
  GridViewState snapshot({bool layoutOnly = false}) => GridViewState(
        search: layoutOnly ? '' : _search,
        filters: layoutOnly ? const {} : Map.of(_filters),
        quick: layoutOnly ? null : _quick,
        sorts: List.of(_sorts),
        pageSize: _pageSize,
        density: _density,
        visibility: Map.of(_visibility),
        order: List.of(_order),
      );

  /// Puts settings back. With [layoutOnly] the search and filters are left
  /// alone.
  void restore(GridViewState state, {bool layoutOnly = false}) {
    if (!layoutOnly) {
      _search = state.search;
      _filters
        ..clear()
        ..addAll(state.filters);
      _quick = state.quick;
    }
    if (state.sorts.isNotEmpty) _sorts = List.of(state.sorts);
    if (state.pageSize != null) _pageSize = state.pageSize!;
    _density = state.density;
    _visibility
      ..clear()
      ..addAll(state.visibility);
    _order = List.unmodifiable(state.order);
    _changed(layout: true, resetPage: true);
  }

  // ---------------------------------------------------------------- apply --

  Object? _memoKey;
  Object? _memo;
  List<Object?>? _memoRows;

  /// Works out what to show: [rows] after the quick filter, the search (every
  /// word of [externalSearch] and the grid's own search must appear in
  /// [searchText]), the column filters, the sort, and the page.
  ///
  /// Without [searchText] a row's searchable text is its columns' export
  /// values.
  GridResult<T> apply<T>(
    List<T> rows,
    List<GridColumn<T>> columns, {
    String Function(T row)? searchText,
    String externalSearch = '',
    List<GridQuickFilter<T>> quickFilters = const [],
  }) {
    final key = (_queryVersion, externalSearch, columns.length, quickFilters.length);
    if (key == _memoKey && _memo is GridResult<T> && _sameRows(rows)) {
      return _memo as GridResult<T>;
    }

    final words = '$externalSearch $_search'
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    final exportable = [for (final c in columns) if (c.exportValue != null) c];
    final text = searchText ??
        (exportable.isEmpty
            ? null
            : (T r) => [for (final c in exportable) c.exportValue!(r)].join(' '));

    Iterable<T> it = rows;
    if (words.isNotEmpty && text != null) {
      it = it.where((r) {
        final s = text(r).toLowerCase();
        return words.every(s.contains);
      });
    }
    for (final entry in _filters.entries) {
      final filter = columns.where((c) => c.id == entry.key).firstOrNull?.filter;
      if (filter == null) continue;
      final value = entry.value;
      it = it.where((r) => _matches(filter, value, r));
    }
    final base = it.toList();

    final quickCounts = {
      for (final q in quickFilters) q.id: base.where(q.test).length,
    };
    final quick = quickFilters.where((q) => q.id == _quick).firstOrNull;
    var list = quick == null ? base : base.where(quick.test).toList();

    final keys = <(Comparable Function(T), bool)>[
      for (final s in _sorts)
        if (columns.where((c) => c.id == s.columnId).firstOrNull?.sortValue
            case final value?)
          (value, s.ascending),
    ];
    if (keys.isNotEmpty && list.length > 1) {
      final values = [
        for (final k in keys) [for (final r in list) k.$1(r)],
      ];
      final index = List.generate(list.length, (i) => i)
        ..sort((a, b) {
          for (var k = 0; k < keys.length; k++) {
            final c = _compare(values[k][a], values[k][b]);
            if (c != 0) return keys[k].$2 ? c : -c;
          }
          return a - b; // stable
        });
      final sorted = list;
      list = [for (final i in index) sorted[i]];
    }

    final total = list.length;
    final size = _pageSize <= 0 ? math.max(total, 1) : _pageSize;
    final pageCount = math.max(1, (total / size).ceil());
    final page = _page.clamp(0, pageCount - 1);
    final start = page * size;
    final end = math.min(start + size, total);

    final result = GridResult<T>(
      all: list,
      pageRows: start >= total ? <T>[] : list.sublist(start, end),
      page: page,
      pageCount: pageCount,
      start: start,
      unfilteredTotal: rows.length,
      baseTotal: base.length,
      quickCounts: quickCounts,
    );
    _memoKey = key;
    _memo = result;
    _memoRows = List.of(rows);
    return result;
  }

  /// Lists can be changed in place, so compare the rows themselves (by
  /// identity: an edited record is a new object).
  bool _sameRows(List<Object?> rows) {
    final last = _memoRows;
    if (last == null || last.length != rows.length) return false;
    for (var i = 0; i < rows.length; i++) {
      if (!identical(last[i], rows[i])) return false;
    }
    return true;
  }

  static bool _matches<T>(GridFilter<T> filter, GridFilterValue value, T row) {
    switch ((filter, value)) {
      case (ChoiceFilter<T> f, ChoiceValue v):
        return v.values.contains(f.value(row));
      case (DateRangeFilter<T> f, DateRangeValue v):
        final d = f.value(row);
        return d != null && v.contains(d);
      case (NumberRangeFilter<T> f, NumberRangeValue v):
        final n = f.value(row);
        return n != null && v.contains(n);
      default:
        return true;
    }
  }

  static int _compare(Comparable a, Comparable b) {
    try {
      return a.compareTo(b);
    } catch (_) {
      return '$a'.compareTo('$b');
    }
  }
}
