import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import 'app_card.dart';
import 'state_views.dart';

/// Describes one column of an [AppDataTable].
class AppColumn<T> {
  const AppColumn({
    required this.label,
    required this.cell,
    this.numeric = false,
    this.sortValue,
    this.width,
  });

  final String label;
  final Widget Function(T row) cell;
  final bool numeric;

  /// Optional comparable value used for sorting; when null the column is not
  /// sortable.
  final Comparable Function(T row)? sortValue;

  /// Optional fixed column width.
  final double? width;
}

/// A polished, self-contained table with built-in search, column sorting and
/// pagination. Feed it [rows] and a set of [columns].
class AppDataTable<T> extends StatefulWidget {
  const AppDataTable({
    super.key,
    required this.rows,
    required this.columns,
    this.searchText = '',
    this.searchableText,
    this.rowsPerPage = 10,
    this.emptyTitle = 'Nothing here yet',
    this.emptyMessage,
    this.emptyAction,
    this.onRowTap,
    this.initialSortColumn,
    this.initialSortAscending = true,
  });

  final List<T> rows;
  final List<AppColumn<T>> columns;

  /// External search query (from a filter bar) matched against [searchableText].
  final String searchText;

  /// Returns the concatenated searchable text for a row.
  final String Function(T row)? searchableText;

  final int rowsPerPage;
  final String emptyTitle;
  final String? emptyMessage;
  final Widget? emptyAction;
  final void Function(T row)? onRowTap;
  final int? initialSortColumn;
  final bool initialSortAscending;

  @override
  State<AppDataTable<T>> createState() => _AppDataTableState<T>();
}

class _AppDataTableState<T> extends State<AppDataTable<T>> {
  int _page = 0;
  int? _sortColumn;
  late bool _ascending;

  @override
  void initState() {
    super.initState();
    _sortColumn = widget.initialSortColumn;
    _ascending = widget.initialSortAscending;
  }

  @override
  void didUpdateWidget(covariant AppDataTable<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reset to the first page when the underlying data or search changes.
    if (oldWidget.searchText != widget.searchText ||
        oldWidget.rows.length != widget.rows.length) {
      _page = 0;
    }
  }

  List<T> get _filtered {
    final query = widget.searchText.trim().toLowerCase();
    if (query.isEmpty || widget.searchableText == null) {
      return List<T>.from(widget.rows);
    }
    return widget.rows
        .where((r) => widget.searchableText!(r).toLowerCase().contains(query))
        .toList();
  }

  List<T> get _sorted {
    final list = _filtered;
    final col = _sortColumn;
    if (col == null) return list;
    final sortValue = widget.columns[col].sortValue;
    if (sortValue == null) return list;
    list.sort((a, b) {
      final cmp = sortValue(a).compareTo(sortValue(b));
      return _ascending ? cmp : -cmp;
    });
    return list;
  }

  void _onSort(int column) {
    if (widget.columns[column].sortValue == null) return;
    setState(() {
      if (_sortColumn == column) {
        _ascending = !_ascending;
      } else {
        _sortColumn = column;
        _ascending = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final sorted = _sorted;
    if (sorted.isEmpty) {
      return AppCard(
        child: EmptyView(
          title: widget.emptyTitle,
          message: widget.emptyMessage,
          action: widget.emptyAction,
        ),
      );
    }

    final pageCount = (sorted.length / widget.rowsPerPage).ceil();
    final page = _page.clamp(0, pageCount - 1);
    final start = page * widget.rowsPerPage;
    final end = (start + widget.rowsPerPage).clamp(0, sorted.length);
    final pageRows = sorted.sublist(start, end);

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Stretch the table to fill the card interior so the header
          // background and column alignment span the full width, while still
          // allowing horizontal scrolling when the natural width overflows the
          // available space (narrow screens / many columns). Using the actual
          // available width from LayoutBuilder — rather than guessing from the
          // window width minus a fixed sidebar — keeps the table aligned inside
          // any container (including nested cards on the product detail page).
          LayoutBuilder(
            builder: (context, constraints) {
              final available = constraints.maxWidth;
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                      minWidth: available.isFinite ? available : 0),
                  child: DataTable(
                    sortColumnIndex: _sortColumn,
                    sortAscending: _ascending,
                    showCheckboxColumn: false,
                    columns: [
                      for (final col in widget.columns)
                        DataColumn(
                          label: col.width != null
                              ? SizedBox(
                                  width: col.width, child: Text(col.label))
                              : Text(col.label),
                          numeric: col.numeric,
                          onSort: col.sortValue != null
                              ? (i, _) => _onSort(i)
                              : null,
                        ),
                    ],
                    rows: [
                      for (final row in pageRows)
                        DataRow(
                          onSelectChanged: widget.onRowTap != null
                              ? (_) => widget.onRowTap!(row)
                              : null,
                          cells: [
                            for (final col in widget.columns)
                              DataCell(col.cell(row)),
                          ],
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
          if (pageCount > 1)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: _Pagination(
                page: page,
                pageCount: pageCount,
                totalRows: sorted.length,
                onPrev: page > 0 ? () => setState(() => _page = page - 1) : null,
                onNext: page < pageCount - 1
                    ? () => setState(() => _page = page + 1)
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}

class _Pagination extends StatelessWidget {
  const _Pagination({
    required this.page,
    required this.pageCount,
    required this.totalRows,
    this.onPrev,
    this.onNext,
  });

  final int page;
  final int pageCount;
  final int totalRows;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text('$totalRows records · Page ${page + 1} of $pageCount',
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 12.5)),
        const SizedBox(width: AppSpacing.md),
        IconButton(
          onPressed: onPrev,
          icon: const Icon(Icons.chevron_left),
          tooltip: 'Previous',
          visualDensity: VisualDensity.compact,
        ),
        IconButton(
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right),
          tooltip: 'Next',
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}
