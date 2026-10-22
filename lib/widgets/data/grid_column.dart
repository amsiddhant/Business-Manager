import 'package:flutter/widgets.dart';

/// Where a column goes when the grid turns into cards on a phone.
enum CardRole {
  /// The card's heading (one per grid).
  title,

  /// A line under the heading.
  subtitle,

  /// Next to the heading — a status pill.
  badge,

  /// A labelled figure in the card's figures row.
  metric,

  /// A small "Label  value" line.
  meta,

  /// The row's own action buttons.
  actions,

  /// Not shown on cards.
  hidden,
}

/// How a column can be filtered from the toolbar.
sealed class GridFilter<T> {
  const GridFilter();

  /// Pick one or more of the column's values (status, category, platform…).
  /// [options] fixes the choices and their order; otherwise they come from
  /// the rows.
  const factory GridFilter.choice(String Function(T row) value,
      {List<String>? options}) = ChoiceFilter<T>;

  /// Rows whose date falls in a picked range.
  const factory GridFilter.dateRange(DateTime? Function(T row) value) =
      DateRangeFilter<T>;

  /// Rows whose figure is between a minimum and a maximum.
  const factory GridFilter.numberRange(num? Function(T row) value) =
      NumberRangeFilter<T>;
}

class ChoiceFilter<T> extends GridFilter<T> {
  const ChoiceFilter(this.value, {this.options});
  final String Function(T row) value;
  final List<String>? options;
}

class DateRangeFilter<T> extends GridFilter<T> {
  const DateRangeFilter(this.value);
  final DateTime? Function(T row) value;
}

class NumberRangeFilter<T> extends GridFilter<T> {
  const NumberRangeFilter(this.value);
  final num? Function(T row) value;
}

/// One column of an `AppDataGrid`.
class GridColumn<T> {
  const GridColumn({
    required this.id,
    required this.label,
    required this.cell,
    this.numeric = false,
    this.sortValue,
    this.width,
    this.minWidth,
    this.flex = 1,
    this.exportValue,
    this.filter,
    this.visibleByDefault = true,
    this.pinned = false,
    this.cardRole,
    this.footer,
    this.tooltip,
  });

  /// Stable id: saved views and column settings are keyed by it.
  final String id;
  final String label;
  final Widget Function(T row) cell;

  /// Right-aligned, with tabular figures.
  final bool numeric;

  /// Sorts the column when set; otherwise it isn't sortable.
  final Comparable Function(T row)? sortValue;

  /// A fixed width. Without one the column shares the spare width by [flex]
  /// and never gets narrower than [minWidth].
  final double? width;
  final double? minWidth;
  final int flex;

  /// The text written to CSV. Columns without one are left out of exports.
  final String Function(T row)? exportValue;
  final GridFilter<T>? filter;
  final bool visibleByDefault;

  /// Always shown, and always first: it can't be hidden or moved.
  final bool pinned;

  /// Where the value goes on a phone card. Null picks one from the column's
  /// position and type.
  final CardRole? cardRole;

  /// A total under the column for the rows that match (e.g. a revenue sum).
  final String Function(List<T> rows)? footer;

  /// Explains the column, on the header.
  final String? tooltip;

  bool get sortable => sortValue != null;

  /// The narrowest the column can be before the grid scrolls sideways.
  double get effectiveMinWidth =>
      width ?? minWidth ?? (label.length * 7.5 + 48).clamp(96.0, 220.0);
}

/// A labelled action in a row's menu.
class GridRowAction<T> {
  const GridRowAction({
    required this.label,
    required this.icon,
    required this.onSelected,
    this.destructive = false,
  });

  final String label;
  final IconData icon;
  final void Function(BuildContext context, T row) onSelected;
  final bool destructive;
}

/// An action on the selected rows (Delete, Export, Change status…).
class GridBulkAction<T> {
  const GridBulkAction({
    required this.label,
    required this.icon,
    this.onRun,
    this.allowed,
    this.destructive = false,
    this.children = const [],
  });

  final String label;
  final IconData icon;

  /// Runs on the selected rows the user may change (see [allowed]).
  final Future<void> Function(BuildContext context, List<T> rows)? onRun;

  /// Whether this row can be acted on (e.g. per-row permission). Rows that
  /// can't are skipped, and the bar says how many.
  final bool Function(T row)? allowed;
  final bool destructive;

  /// Shows a menu of these instead (e.g. one per status).
  final List<GridBulkAction<T>> children;
}

/// A one-tap filter above the grid ("Pending", "Refunded"…), with a count.
class GridQuickFilter<T> {
  const GridQuickFilter({
    required this.id,
    required this.label,
    required this.test,
    this.icon,
  });

  final String id;
  final String label;
  final bool Function(T row) test;
  final IconData? icon;
}
