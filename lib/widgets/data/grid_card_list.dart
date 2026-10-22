import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_x.dart';
import 'grid_column.dart';

/// Works out where each column goes on a phone card. Columns that say
/// ([GridColumn.cardRole]) keep their role; the rest are placed by position
/// and type: a "Status" column is the badge, the first other text column
/// the title, the next text column the subtitle, up to three figures the
/// metrics, a column without a label the actions, everything else a meta
/// line.
Map<String, CardRole> resolveCardRoles<T>(List<GridColumn<T>> columns) {
  final roles = <String, CardRole>{
    for (final c in columns) c.id: ?c.cardRole,
  };
  bool taken(CardRole r) => roles.values.contains(r);
  var metrics = roles.values.where((r) => r == CardRole.metric).length;
  for (final c in columns) {
    if (roles.containsKey(c.id)) continue;
    final label = c.label.trim().toLowerCase();
    final CardRole role;
    if (label.isEmpty) {
      role = CardRole.actions;
    } else if (label.contains('status') && !taken(CardRole.badge)) {
      role = CardRole.badge;
    } else if (!c.numeric && !taken(CardRole.title)) {
      role = CardRole.title;
    } else if (c.numeric && metrics < 3) {
      role = CardRole.metric;
      metrics++;
    } else if (!c.numeric && !taken(CardRole.subtitle)) {
      role = CardRole.subtitle;
    } else {
      role = CardRole.meta;
    }
    roles[c.id] = role;
  }
  return roles;
}

/// The grid's rows as cards, for phones.
class GridCardList<T> extends StatelessWidget {
  const GridCardList({
    super.key,
    required this.rows,
    required this.columns,
    this.isSelected,
    this.onToggle,
    this.onTap,
    this.rowActions,
  });

  final List<T> rows;
  final List<GridColumn<T>> columns;

  /// Null when the grid has no selection.
  final bool Function(T row)? isSelected;
  final void Function(T row)? onToggle;
  final void Function(T row)? onTap;
  final List<GridRowAction<T>> Function(T row)? rowActions;

  @override
  Widget build(BuildContext context) {
    final roles = resolveCardRoles(columns);
    List<GridColumn<T>> by(CardRole r) =>
        [for (final c in columns) if (roles[c.id] == r) c];
    final layout = _CardLayout<T>(
      title: by(CardRole.title).firstOrNull,
      subtitle: by(CardRole.subtitle).firstOrNull,
      badge: by(CardRole.badge).firstOrNull,
      metrics: by(CardRole.metric),
      meta: by(CardRole.meta),
      actions: by(CardRole.actions),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.sm),
          _GridCard<T>(
            row: rows[i],
            layout: layout,
            selected: isSelected?.call(rows[i]),
            onToggle: onToggle == null ? null : () => onToggle!(rows[i]),
            onTap: onTap == null ? null : () => onTap!(rows[i]),
            actions: rowActions?.call(rows[i]) ?? const [],
          ),
        ],
      ],
    );
  }
}

class _CardLayout<T> {
  const _CardLayout({
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.metrics,
    required this.meta,
    required this.actions,
  });

  final GridColumn<T>? title;
  final GridColumn<T>? subtitle;
  final GridColumn<T>? badge;
  final List<GridColumn<T>> metrics;
  final List<GridColumn<T>> meta;
  final List<GridColumn<T>> actions;
}

class _GridCard<T> extends StatelessWidget {
  const _GridCard({
    required this.row,
    required this.layout,
    required this.selected,
    required this.onToggle,
    required this.onTap,
    required this.actions,
  });

  final T row;
  final _CardLayout<T> layout;

  /// Null when the grid has no selection.
  final bool? selected;
  final VoidCallback? onToggle;
  final VoidCallback? onTap;
  final List<GridRowAction<T>> actions;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final l = layout;
    final isSelected = selected ?? false;
    final radius = BorderRadius.circular(AppSpacing.radius);
    final labelStyle = TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
        color: t.textTertiary);

    final heading = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (selected != null)
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: isSelected,
                onChanged: (_) => onToggle?.call(),
              ),
            ),
          ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (l.title != null)
                DefaultTextStyle.merge(
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: t.textPrimary),
                  child: l.title!.cell(row),
                ),
              if (l.subtitle != null) ...[
                const SizedBox(height: 2),
                DefaultTextStyle.merge(
                  style: TextStyle(fontSize: 13, color: t.textSecondary),
                  child: l.subtitle!.cell(row),
                ),
              ],
            ],
          ),
        ),
        if (l.badge != null) ...[
          const SizedBox(width: AppSpacing.sm),
          l.badge!.cell(row),
        ],
      ],
    );

    final metrics = l.metrics.isEmpty
        ? null
        : Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            decoration: BoxDecoration(
              color: t.surfaceAlt,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final c in l.metrics)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.label.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: labelStyle),
                        const SizedBox(height: 2),
                        DefaultTextStyle.merge(
                          style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: t.textPrimary,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ]),
                          child: c.cell(row),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );

    final actionButtons = [for (final c in l.actions) c.cell(row)];

    final body = Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          heading,
          if (metrics != null) ...[
            const SizedBox(height: AppSpacing.md),
            metrics,
          ],
          if (l.meta.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            for (final c in l.meta)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 104,
                      child: Text(c.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12.5, color: t.textTertiary)),
                    ),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: DefaultTextStyle.merge(
                          style: TextStyle(
                              fontSize: 13, color: t.textPrimary),
                          child: c.cell(row),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if (actionButtons.isNotEmpty || actions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ...actionButtons,
                if (actions.isNotEmpty) GridRowMenu<T>(row: row, actions: actions),
              ],
            ),
          ],
        ],
      ),
    );

    return Material(
      color: isSelected ? t.primarySurface : t.card,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(
            color: isSelected ? t.primary.withValues(alpha: 0.5) : t.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onToggle,
        child: body,
      ),
    );
  }
}

/// The ⋮ menu of a row's labelled actions.
class GridRowMenu<T> extends StatelessWidget {
  const GridRowMenu({super.key, required this.row, required this.actions});

  final T row;
  final List<GridRowAction<T>> actions;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return PopupMenuButton<int>(
      tooltip: 'More actions',
      icon: Icon(Icons.more_vert, size: 20, color: t.textSecondary),
      position: PopupMenuPosition.under,
      onSelected: (i) => actions[i].onSelected(context, row),
      itemBuilder: (_) => [
        for (var i = 0; i < actions.length; i++)
          PopupMenuItem<int>(
            value: i,
            height: 40,
            child: Row(
              children: [
                Icon(actions[i].icon,
                    size: 18,
                    color: actions[i].destructive ? t.error : t.textSecondary),
                const SizedBox(width: AppSpacing.md),
                Text(actions[i].label,
                    style: TextStyle(
                        color: actions[i].destructive ? t.error : null)),
              ],
            ),
          ),
      ],
    );
  }
}
