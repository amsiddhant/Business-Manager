import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_x.dart';
import '../../core/utils/date_utils.dart';
import 'grid_column.dart';
import 'grid_controller.dart';
import 'grid_view_store.dart';

/// The bar above a grid: search, filters, saved views, columns, density and
/// export. On a phone ([compact]) everything but the search folds into one
/// "View options" button.
class GridToolbar<T> extends StatefulWidget {
  const GridToolbar({
    super.key,
    required this.controller,
    required this.columns,
    required this.rows,
    this.store,
    this.compact = false,
    this.showSearch = true,
    this.searchHint = 'Search…',
    this.onExportView,
    this.onExportAll,
    this.exportAllLabel = 'Export all fields (CSV)',
    this.actions = const [],
  });

  final GridController controller;
  final List<GridColumn<T>> columns;

  /// All rows, for the filter choices.
  final List<T> rows;
  final GridViewStore? store;
  final bool compact;
  final bool showSearch;
  final String searchHint;

  /// Downloads what the grid shows (null hides the option).
  final VoidCallback? onExportView;

  /// Downloads every field, in the format the importer reads.
  final VoidCallback? onExportAll;
  final String exportAllLabel;

  /// Extra buttons at the end (e.g. Import).
  final List<Widget> actions;

  @override
  State<GridToolbar<T>> createState() => _GridToolbarState<T>();
}

class _GridToolbarState<T> extends State<GridToolbar<T>> {
  late final TextEditingController _search =
      TextEditingController(text: widget.controller.search);
  Timer? _debounce;

  GridController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.addListener(_syncSearch);
  }

  @override
  void didUpdateWidget(covariant GridToolbar<T> old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_syncSearch);
      widget.controller.addListener(_syncSearch);
      _syncSearch();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _c.removeListener(_syncSearch);
    _search.dispose();
    super.dispose();
  }

  /// A saved view or "Clear filters" changed the search under the field.
  void _syncSearch() {
    if (_debounce?.isActive ?? false) return;
    if (_search.text != _c.search) _search.text = _c.search;
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () => _c.setSearch(v));
    setState(() {});
  }

  List<GridColumn<T>> get _filterable =>
      [for (final c in widget.columns) if (c.filter != null) c];

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final search = widget.showSearch
        ? TextField(
            controller: _search,
            onChanged: _onSearch,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              isDense: true,
              hintText: widget.searchHint,
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        _debounce?.cancel();
                        _search.clear();
                        _c.setSearch('');
                        setState(() {});
                      },
                    ),
              fillColor: t.background,
            ),
          )
        : null;

    if (widget.compact) {
      return Row(
        children: [
          if (search != null) Expanded(child: search) else const Spacer(),
          const SizedBox(width: AppSpacing.sm),
          IconButton.outlined(
            tooltip: 'View options',
            onPressed: () => _showOptionsSheet(context),
            icon: Badge(
              isLabelVisible: _c.filters.isNotEmpty,
              label: Text('${_c.filters.length}'),
              child: const Icon(Icons.tune, size: 20),
            ),
          ),
          ...widget.actions,
        ],
      );
    }

    return LayoutBuilder(builder: (context, c) {
      // Below this the labelled buttons don't fit beside the search, so
      // they show their icon only (the label becomes the tooltip).
      final iconOnly = c.maxWidth < 1000;
      final buttons = <Widget>[
        if (_filterable.isNotEmpty) _filterButton(context, iconOnly),
        if (widget.store != null) _viewsButton(context, iconOnly),
        _columnsButton(context, iconOnly),
        _densityButton(context),
        if (widget.onExportView != null || widget.onExportAll != null)
          _exportButton(context),
        ...widget.actions,
      ];
      return Row(
        children: [
          // The search takes the room the buttons leave, up to 360 px.
          if (search != null)
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: search),
              ),
            )
          else
            const Spacer(),
          for (final b in buttons) ...[
            const SizedBox(width: AppSpacing.sm),
            b,
          ],
        ],
      );
    });
  }

  // ------------------------------------------------------------- filters --

  Widget _filterButton(BuildContext context, bool iconOnly) {
    final active = _c.filters.length;
    return MenuAnchor(
      menuChildren: [
        for (final col in _filterable)
          MenuItemButton(
            leadingIcon: Icon(_filterIcon(col.filter!), size: 18),
            trailingIcon: _c.filterFor(col.id) != null
                ? Icon(Icons.check, size: 16, color: context.tokens.primary)
                : null,
            onPressed: () => editGridFilter(context, _c, col, widget.rows),
            child: Text(col.label),
          ),
      ],
      builder: (context, menu, _) => _ToolbarButton(
        iconOnly: iconOnly,
        badge: active,
        icon: Icons.filter_list,
        label: active == 0 ? 'Filter' : 'Filter · $active',
        highlighted: active > 0,
        onPressed: () => menu.isOpen ? menu.close() : menu.open(),
      ),
    );
  }

  static IconData _filterIcon(GridFilter f) => switch (f) {
        ChoiceFilter() => Icons.checklist,
        DateRangeFilter() => Icons.date_range,
        NumberRangeFilter() => Icons.straighten,
      };

  // --------------------------------------------------------------- views --

  Widget _viewsButton(BuildContext context, bool iconOnly) {
    final store = widget.store!;
    final views = store.views;
    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.bookmark_add_outlined, size: 18),
          onPressed: () => _saveView(context, store),
          child: const Text('Save current view…'),
        ),
        if (views.isNotEmpty) const Divider(height: 8),
        for (final v in views)
          MenuItemButton(
            leadingIcon: const Icon(Icons.bookmark_outline, size: 18),
            trailingIcon: IconButton(
              tooltip: 'Delete view "${v.name}"',
              visualDensity: VisualDensity.compact,
              iconSize: 16,
              icon: const Icon(Icons.close),
              onPressed: () async {
                await store.deleteView(v.name);
                if (mounted) setState(() {});
              },
            ),
            onPressed: () => _c.restore(v.state),
            child: Text(v.name),
          ),
        const Divider(height: 8),
        MenuItemButton(
          leadingIcon: const Icon(Icons.restart_alt, size: 18),
          onPressed: () {
            _c.clearFilters();
            _c.resetColumns();
            _c.setDensity(null);
          },
          child: const Text('Reset to default'),
        ),
      ],
      builder: (context, menu, _) => _ToolbarButton(
        iconOnly: iconOnly,
        icon: Icons.bookmarks_outlined,
        label: 'Views',
        onPressed: () => menu.isOpen ? menu.close() : menu.open(),
      ),
    );
  }

  Future<void> _saveView(BuildContext context, GridViewStore store) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _SaveViewDialog(),
    );
    if (name == null || name.trim().isEmpty) return;
    await store.saveView(name, _c.snapshot());
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved view "${name.trim()}"')));
      setState(() {});
    }
  }

  // ------------------------------------------------------------- columns --

  Widget _columnsButton(BuildContext context, bool iconOnly) =>
      _ToolbarButton(
        iconOnly: iconOnly,
        icon: Icons.view_column_outlined,
        label: 'Columns',
        highlighted: _c.hasColumnChanges,
        onPressed: () => showGridColumns(context, _c, widget.columns),
      );

  Widget _densityButton(BuildContext context) => MenuAnchor(
        menuChildren: [
          for (final d in AppDensity.values)
            MenuItemButton(
              leadingIcon: Icon(
                (_c.density ?? context.density) == d
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 18,
              ),
              onPressed: () => _c.setDensity(d),
              child: Text(d.label),
            ),
          if (_c.density != null) ...[
            const Divider(height: 8),
            MenuItemButton(
              leadingIcon: const Icon(Icons.sync_alt, size: 18),
              onPressed: () => _c.setDensity(null),
              child: const Text('Use app setting'),
            ),
          ],
        ],
        builder: (context, menu, _) => _ToolbarIconButton(
          icon: Icons.density_medium,
          tooltip: 'Row density',
          onPressed: () => menu.isOpen ? menu.close() : menu.open(),
        ),
      );

  Widget _exportButton(BuildContext context) => MenuAnchor(
        menuChildren: [
          if (widget.onExportView != null)
            MenuItemButton(
              leadingIcon: const Icon(Icons.table_view_outlined, size: 18),
              onPressed: widget.onExportView,
              child: const Text('Export this view (CSV)'),
            ),
          if (widget.onExportAll != null)
            MenuItemButton(
              leadingIcon: const Icon(Icons.file_download_outlined, size: 18),
              onPressed: widget.onExportAll,
              child: Text(widget.exportAllLabel),
            ),
        ],
        builder: (context, menu, _) => _ToolbarIconButton(
          icon: Icons.ios_share,
          tooltip: 'Export',
          onPressed: () => menu.isOpen ? menu.close() : menu.open(),
        ),
      );

  // ---------------------------------------------------------- phone sheet --

  Future<void> _showOptionsSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: ListenableBuilder(
          listenable: _c,
          builder: (sheet, _) => ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: AppSpacing.lg),
            children: [
              _sheetTitle(sheet, 'Sort by'),
              for (final col in widget.columns)
                if (col.sortable)
                  ListTile(
                    dense: true,
                    title: Text(col.label),
                    trailing: switch (_c.sortOf(col.id)) {
                      (_, true) => const Icon(Icons.arrow_upward, size: 18),
                      (_, false) => const Icon(Icons.arrow_downward, size: 18),
                      null => null,
                    },
                    onTap: () => _c.sortBy(col.id),
                  ),
              if (_filterable.isNotEmpty) ...[
                _sheetTitle(sheet, 'Filter'),
                for (final col in _filterable)
                  ListTile(
                    dense: true,
                    leading: Icon(_filterIcon(col.filter!), size: 20),
                    title: Text(col.label),
                    subtitle: _c.filterFor(col.id) == null
                        ? null
                        : Text(describeGridFilter(_c.filterFor(col.id)!)),
                    trailing: _c.filterFor(col.id) == null
                        ? null
                        : IconButton(
                            tooltip: 'Clear',
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => _c.setFilter(col.id, null),
                          ),
                    onTap: () => editGridFilter(sheet, _c, col, widget.rows),
                  ),
              ],
              if (widget.store != null && widget.store!.views.isNotEmpty) ...[
                _sheetTitle(sheet, 'Saved views'),
                for (final v in widget.store!.views)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.bookmark_outline, size: 20),
                    title: Text(v.name),
                    onTap: () {
                      _c.restore(v.state);
                      Navigator.pop(sheet);
                    },
                  ),
              ],
              if (widget.onExportView != null || widget.onExportAll != null) ...[
                _sheetTitle(sheet, 'Export'),
                if (widget.onExportView != null)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.table_view_outlined, size: 20),
                    title: const Text('Export this view (CSV)'),
                    onTap: () {
                      Navigator.pop(sheet);
                      widget.onExportView!();
                    },
                  ),
                if (widget.onExportAll != null)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.file_download_outlined, size: 20),
                    title: Text(widget.exportAllLabel),
                    onTap: () {
                      Navigator.pop(sheet);
                      widget.onExportAll!();
                    },
                  ),
              ],
              if (_c.hasFilters)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
                  child: OutlinedButton.icon(
                    onPressed: _c.clearFilters,
                    icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                    label: const Text('Clear all filters'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetTitle(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xs),
        child: Text(text.toUpperCase(),
            style: TextStyle(
                fontSize: 11,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w700,
                color: context.tokens.textTertiary)),
      );
}

/// The chips under the toolbar, one per active filter: tap to change, ✕ to
/// remove.
class GridFilterChips<T> extends StatelessWidget {
  const GridFilterChips({
    super.key,
    required this.controller,
    required this.columns,
    required this.rows,
  });

  final GridController controller;
  final List<GridColumn<T>> columns;
  final List<T> rows;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final active = [
      for (final col in columns)
        if (controller.filterFor(col.id) case final value?) (col, value),
    ];
    if (active.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final (col, value) in active)
          InputChip(
            label: Text('${col.label}: ${describeGridFilter(value)}'),
            labelStyle: TextStyle(fontSize: 12.5, color: t.primary),
            backgroundColor: t.primarySurface,
            side: BorderSide(color: t.primary.withValues(alpha: 0.3)),
            deleteIconColor: t.primary,
            deleteButtonTooltipMessage: 'Remove ${col.label} filter',
            onPressed: () => editGridFilter(context, controller, col, rows),
            onDeleted: () => controller.setFilter(col.id, null),
          ),
        TextButton(
          onPressed: controller.clearFilters,
          child: const Text('Clear all'),
        ),
      ],
    );
  }
}

/// "Pending, Shipped", "1 Apr 2026 – 30 Apr 2026", "≥ 1,000".
String describeGridFilter(GridFilterValue value) => switch (value) {
      ChoiceValue(:final values) => values.length <= 2
          ? values.join(', ')
          : '${values.take(2).join(', ')} +${values.length - 2}',
      DateRangeValue(:final start, :final end) =>
        '${AppDate.short(start)} – ${AppDate.short(end)}',
      NumberRangeValue(:final min, :final max) => min != null && max != null
          ? '${_n(min)} – ${_n(max)}'
          : min != null
              ? '≥ ${_n(min)}'
              : '≤ ${_n(max!)}',
    };

String _n(num v) => v == v.roundToDouble() ? '${v.round()}' : '$v';

/// Opens the editor for [column]'s filter and applies the answer.
Future<void> editGridFilter<T>(BuildContext context, GridController controller,
    GridColumn<T> column, List<T> rows) async {
  final filter = column.filter;
  final current = controller.filterFor(column.id);
  switch (filter) {
    case ChoiceFilter<T>():
      final counts = <String, int>{};
      for (final r in rows) {
        final v = filter.value(r);
        if (v.isEmpty) continue;
        counts[v] = (counts[v] ?? 0) + 1;
      }
      final options = filter.options ?? (counts.keys.toList()..sort());
      final picked = await showDialog<Set<String>>(
        context: context,
        builder: (_) => _ChoiceFilterDialog(
          title: column.label,
          options: options,
          counts: counts,
          selected: current is ChoiceValue ? current.values : const {},
        ),
      );
      if (picked == null) return;
      controller.setFilter(
          column.id, picked.isEmpty ? null : ChoiceValue(picked));
    case DateRangeFilter<T>():
      final now = DateTime.now();
      final range = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2015),
        lastDate: DateTime(now.year + 5, 12, 31),
        initialDateRange: current is DateRangeValue
            ? DateTimeRange(start: current.start, end: current.end)
            : null,
        helpText: column.label,
      );
      if (range == null) return;
      controller.setFilter(column.id, DateRangeValue(range.start, range.end));
    case NumberRangeFilter<T>():
      final value = await showDialog<NumberRangeValue>(
        context: context,
        builder: (_) => _NumberRangeDialog(
          title: column.label,
          initial: current is NumberRangeValue ? current : null,
        ),
      );
      if (value == null) return;
      controller.setFilter(column.id,
          value.min == null && value.max == null ? null : value);
    case null:
      return;
  }
}

/// Show, hide and reorder columns.
Future<void> showGridColumns<T>(BuildContext context, GridController controller,
    List<GridColumn<T>> columns) {
  return showDialog<void>(
    context: context,
    builder: (_) => _ColumnsDialog<T>(controller: controller, columns: columns),
  );
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.highlighted = false,
    this.iconOnly = false,
    this.badge = 0,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool highlighted;

  /// Just the icon, with [label] as its tooltip (narrow toolbars).
  final bool iconOnly;

  /// A count on the icon when [iconOnly] (e.g. active filters).
  final int badge;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    if (iconOnly) {
      return IconButton.outlined(
        tooltip: label,
        onPressed: onPressed,
        icon: Badge(
          isLabelVisible: badge > 0,
          label: Text('$badge'),
          child: Icon(icon, size: 20),
        ),
        style: IconButton.styleFrom(
          foregroundColor: highlighted ? t.primary : t.textPrimary,
          backgroundColor: highlighted ? t.primarySurface : null,
          side: BorderSide(
              color:
                  highlighted ? t.primary.withValues(alpha: 0.4) : t.border),
        ),
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: highlighted ? t.primary : t.textPrimary,
        backgroundColor: highlighted ? t.primarySurface : null,
        side: BorderSide(
            color: highlighted ? t.primary.withValues(alpha: 0.4) : t.border),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class _ToolbarIconButton extends StatelessWidget {
  const _ToolbarIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton.outlined(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        style: IconButton.styleFrom(
          side: BorderSide(color: context.tokens.border),
          visualDensity: VisualDensity.compact,
        ),
      );
}

class _ChoiceFilterDialog extends StatefulWidget {
  const _ChoiceFilterDialog({
    required this.title,
    required this.options,
    required this.counts,
    required this.selected,
  });

  final String title;
  final List<String> options;
  final Map<String, int> counts;
  final Set<String> selected;

  @override
  State<_ChoiceFilterDialog> createState() => _ChoiceFilterDialogState();
}

class _ChoiceFilterDialogState extends State<_ChoiceFilterDialog> {
  late final Set<String> _picked = {...widget.selected};
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final q = _query.toLowerCase();
    final shown = [
      for (final o in widget.options)
        if (q.isEmpty || o.toLowerCase().contains(q)) o,
    ];
    return AlertDialog(
      title: Text('Filter by ${widget.title.toLowerCase()}'),
      contentPadding: const EdgeInsets.fromLTRB(0, AppSpacing.md, 0, 0),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.options.length > 8)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                child: TextField(
                  autofocus: true,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Find…',
                    prefixIcon: Icon(Icons.search, size: 18),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                children: [
                  if (shown.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      child: Text('No values to pick from.',
                          style: TextStyle(color: t.textTertiary)),
                    ),
                  for (final o in shown)
                    CheckboxListTile(
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                      value: _picked.contains(o),
                      title: Text(o),
                      secondary: Text('${widget.counts[o] ?? 0}',
                          style: TextStyle(
                              fontSize: 12.5,
                              color: t.textTertiary,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ])),
                      onChanged: (v) => setState(
                          () => v == true ? _picked.add(o) : _picked.remove(o)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _picked.isEmpty
              ? null
              : () => setState(_picked.clear),
          child: const Text('Clear'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _picked),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

class _NumberRangeDialog extends StatefulWidget {
  const _NumberRangeDialog({required this.title, this.initial});

  final String title;
  final NumberRangeValue? initial;

  @override
  State<_NumberRangeDialog> createState() => _NumberRangeDialogState();
}

class _NumberRangeDialogState extends State<_NumberRangeDialog> {
  late final _min = TextEditingController(
      text: widget.initial?.min == null ? '' : _n(widget.initial!.min!));
  late final _max = TextEditingController(
      text: widget.initial?.max == null ? '' : _n(widget.initial!.max!));

  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  num? _parse(String s) =>
      num.tryParse(s.replaceAll(RegExp(r'[^0-9.\-]'), ''));

  @override
  Widget build(BuildContext context) {
    final min = _parse(_min.text), max = _parse(_max.text);
    final invalid = min != null && max != null && min > max;
    InputDecoration deco(String label) => InputDecoration(
          labelText: label,
          isDense: true,
        );
    return AlertDialog(
      title: Text('Filter by ${widget.title.toLowerCase()}'),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _min,
                    autofocus: true,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: deco('At least'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: TextField(
                    controller: _max,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: deco('At most'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            if (invalid) ...[
              const SizedBox(height: AppSpacing.sm),
              Text('"At least" is more than "At most".',
                  style: TextStyle(fontSize: 12.5, color: context.tokens.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: invalid
              ? null
              : () => Navigator.pop(
                  context, NumberRangeValue(min: min, max: max)),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

class _SaveViewDialog extends StatefulWidget {
  const _SaveViewDialog();

  @override
  State<_SaveViewDialog> createState() => _SaveViewDialogState();
}

class _SaveViewDialogState extends State<_SaveViewDialog> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    void save() {
      if (_name.text.trim().isNotEmpty) Navigator.pop(context, _name.text);
    }

    return AlertDialog(
      title: const Text('Save view'),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'Keeps the search, filters, sorting and columns, so you can '
                'come back to them in one click. Saved in this browser only.',
                style: TextStyle(
                    fontSize: 13, color: context.tokens.textSecondary)),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _name,
              autofocus: true,
              maxLength: 40,
              decoration: const InputDecoration(
                  labelText: 'Name', hintText: 'e.g. Pending this month'),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => save(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _name.text.trim().isEmpty ? null : save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _ColumnsDialog<T> extends StatefulWidget {
  const _ColumnsDialog({required this.controller, required this.columns});

  final GridController controller;
  final List<GridColumn<T>> columns;

  @override
  State<_ColumnsDialog<T>> createState() => _ColumnsDialogState<T>();
}

class _ColumnsDialogState<T> extends State<_ColumnsDialog<T>> {
  GridController get _c => widget.controller;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ordered = _c.orderedColumns(widget.columns);
    final pinned = [for (final c in ordered) if (c.pinned) c];
    final movable = [for (final c in ordered) if (!c.pinned && c.label.isNotEmpty) c];
    final unlabelled = [for (final c in ordered) if (!c.pinned && c.label.isEmpty) c];

    Widget tile(GridColumn<T> col, {int? index}) => ListTile(
          key: ValueKey(col.id),
          dense: true,
          contentPadding: const EdgeInsets.only(left: AppSpacing.sm, right: 40),
          leading: Checkbox(
            value: _c.isVisible(col),
            onChanged: col.pinned
                ? null
                : (v) => setState(() => _c.setVisible(col.id, v ?? true)),
          ),
          title: Text(col.label),
          subtitle: col.pinned
              ? Text('Always shown',
                  style: TextStyle(fontSize: 11.5, color: t.textTertiary))
              : null,
        );

    return AlertDialog(
      title: const Text('Columns'),
      contentPadding: const EdgeInsets.fromLTRB(0, AppSpacing.md, 0, 0),
      content: SizedBox(
        width: 360,
        height: (ordered.length * 48.0 + 40).clamp(160.0, 460.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              child: Text('Tick to show. Drag ⠿ to reorder.',
                  style: TextStyle(fontSize: 12.5, color: t.textSecondary)),
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final c in pinned) tile(c),
            Expanded(
              child: ReorderableListView(
                buildDefaultDragHandles: true,
                onReorder: (from, to) {
                  setState(() {
                    final ids = [for (final c in movable) c.id];
                    if (to > from) to -= 1;
                    ids.insert(to, ids.removeAt(from));
                    _c.setOrder([...ids, for (final c in unlabelled) c.id]);
                  });
                },
                children: [
                  for (var i = 0; i < movable.length; i++)
                    tile(movable[i], index: i),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _c.hasColumnChanges
              ? () => setState(_c.resetColumns)
              : null,
          child: const Text('Reset'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
