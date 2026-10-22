import 'package:flutter/material.dart';

import '../../../core/theme/theme_x.dart';
import '../../../models/app_settings.dart';
import '../settings_draft.dart';
import '../settings_widgets.dart';

/// How tables look, and which have default columns.
class TablesSection extends StatelessWidget {
  const TablesSection({super.key, required this.draft});

  final SettingsDraft draft;

  /// `orders.list` → "Orders · list".
  static String _gridName(String id) {
    final parts = id.split('.');
    final first = parts.first;
    final head = first.isEmpty ? id : first[0].toUpperCase() + first.substring(1);
    return parts.length == 1 ? head : '$head · ${parts.skip(1).join(' · ')}';
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tables = draft.settings.tables;
    void set(TableSettings Function(TableSettings t) change) =>
        draft.update((s) => s.copyWith(tables: change(s.tables)));

    final grids = tables.defaultColumns.keys.toList()..sort();

    return SettingsPanel(
      title: 'Tables',
      subtitle: 'How lists and grids look for everyone',
      onReset: () =>
          draft.resetSection((s, d) => s.copyWith(tables: d.tables)),
      children: [
        SettingsCard(
          title: 'Look',
          children: [
            ChoiceRow<AppDensity?>(
              label: 'Row density',
              value: tables.density,
              options: [null, ...AppDensity.values],
              labelOf: (d) => d?.label ?? 'Follow the theme',
              onChanged: (d) => set((x) => x.copyWith(density: () => d)),
            ),
            const SizedBox(height: 8),
            SettingSwitch(
              title: 'Zebra stripes',
              subtitle: 'Shade every other row.',
              value: tables.zebra,
              onChanged: (v) => set((x) => x.copyWith(zebra: v)),
            ),
            SettingSwitch(
              title: 'Sticky header',
              subtitle: 'Keep column names in view while scrolling.',
              value: tables.stickyHeader,
              onChanged: (v) => set((x) => x.copyWith(stickyHeader: v)),
            ),
          ],
        ),
        SettingsCard(
          title: 'Default columns',
          subtitle: 'Tables with columns saved for everyone. People can still '
              'change their own.',
          children: [
            if (grids.isEmpty)
              Text(
                'No table has default columns yet. Open a table’s column '
                'chooser and save its columns as the default for everyone.',
                style: TextStyle(fontSize: 13, color: t.textSecondary),
              )
            else
              for (final id in grids)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_gridName(id),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w500)),
                            Text('${tables.defaultColumns[id]!.length} columns',
                                style: TextStyle(
                                    fontSize: 12, color: t.textSecondary)),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () => set((x) => x.copyWith(
                            defaultColumns: {...x.defaultColumns}..remove(id))),
                        child: Text('Reset ${_gridName(id)}'),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ],
    );
  }
}
