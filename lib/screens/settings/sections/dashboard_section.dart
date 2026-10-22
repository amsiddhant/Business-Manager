import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_x.dart';
import '../../../models/app_settings.dart';
import '../../dashboard/widgets/dashboard_registry.dart';
import '../settings_draft.dart';
import '../settings_widgets.dart';

/// Which dashboard sections show, in what order, and the four headline
/// figures.
class DashboardSection extends StatefulWidget {
  const DashboardSection({super.key, required this.draft});

  final SettingsDraft draft;

  @override
  State<DashboardSection> createState() => _DashboardSectionState();
}

class _DashboardSectionState extends State<DashboardSection> {
  static final _builtIn = [for (final s in DashboardSectionId.values) s.name];
  static final _defaultHeroes = [
    for (final k in kDashboardKpis.take(kHeroKpiCount)) k.name,
  ];

  /// The headline figures as they are being picked. The draft only changes
  /// once there are exactly [kHeroKpiCount] of them.
  late List<String> _picks;

  SettingsDraft get _draft => widget.draft;
  DashboardSettings get _dash => _draft.settings.dashboard;

  @override
  void initState() {
    super.initState();
    _picks = [..._effectiveHeroes];
  }

  List<String> get _effectiveHeroes =>
      _dash.heroKpis.isEmpty ? _defaultHeroes : _dash.heroKpis;

  void _set(DashboardSettings Function(DashboardSettings d) change) =>
      _draft.update((s) => s.copyWith(dashboard: change(s.dashboard)));

  void _reorder(List<String> order, int from, int to) {
    final next = [...order];
    next.insert(to, next.removeAt(from));
    _set((d) => d.copyWith(order: next));
  }

  void _togglePick(String name) {
    setState(() {
      if (_picks.contains(name)) {
        _picks = [..._picks]..remove(name);
      } else if (_picks.length < kHeroKpiCount) {
        _picks = [..._picks, name];
      }
    });
    if (_picks.length != kHeroKpiCount) return;
    // Picking the built-in four, in the built-in order, is "use default".
    final isDefault = listEquals(_picks, _defaultHeroes);
    _set((d) => d.copyWith(heroKpis: isDefault ? [] : [..._picks]));
  }

  void _useDefaultHeroes() {
    setState(() => _picks = [..._defaultHeroes]);
    _set((d) => d.copyWith(heroKpis: []));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final order = _dash.arrange(_builtIn);
    final byName = {for (final s in DashboardSectionId.values) s.name: s};
    final full = _picks.length == kHeroKpiCount;

    return SettingsPanel(
      title: 'Dashboard',
      subtitle: 'What the dashboard shows, and in what order',
      onReset: () =>
          _draft.resetSection((s, d) => s.copyWith(dashboard: d.dashboard)),
      children: [
        SettingsCard(
          title: 'Sections',
          subtitle: 'Drag to reorder, or use the arrows. Switch a section off '
              'to hide it.',
          children: [
            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              onReorder: (from, to) =>
                  _reorder(order, from, to > from ? to - 1 : to),
              children: [
                for (var i = 0; i < order.length; i++)
                  _SectionRow(
                    key: ValueKey(order[i]),
                    index: i,
                    label: byName[order[i]]!.label,
                    visible: _dash.isVisible(order[i]),
                    onVisible: (v) => _set((d) => d.copyWith(
                        hidden: v
                            ? ({...d.hidden}..remove(order[i]))
                            : {...d.hidden, order[i]})),
                    onUp: i == 0 ? null : () => _reorder(order, i, i - 1),
                    onDown: i == order.length - 1
                        ? null
                        : () => _reorder(order, i, i + 1),
                  ),
              ],
            ),
          ],
        ),
        SettingsCard(
          title: 'Headline figures',
          subtitle: 'Choose exactly $kHeroKpiCount. They appear in the order '
              'you pick them.',
          trailing: TextButton(
            onPressed: _useDefaultHeroes,
            child: const Text('Use default'),
          ),
          children: [
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final k in kDashboardKpis)
                  FilterChip(
                    label: Text(k.label),
                    selected: _picks.contains(k.name),
                    onSelected: _picks.contains(k.name) || !full
                        ? (_) => _togglePick(k.name)
                        : null,
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            if (full)
              Text(
                _picks
                    .map((n) => kDashboardKpis
                        .firstWhere((k) => k.name == n)
                        .label)
                    .join('  ›  '),
                style: TextStyle(fontSize: 13, color: t.textSecondary),
              )
            else
              SettingsNote(
                '${_picks.length} of $kHeroKpiCount selected. Pick '
                '${kHeroKpiCount - _picks.length} more to apply the change.',
                tone: SettingsNoteTone.warning,
              ),
          ],
        ),
      ],
    );
  }

}

class _SectionRow extends StatelessWidget {
  const _SectionRow({
    super.key,
    required this.index,
    required this.label,
    required this.visible,
    required this.onVisible,
    required this.onUp,
    required this.onDown,
  });

  final int index;
  final String label;
  final bool visible;
  final ValueChanged<bool> onVisible;
  final VoidCallback? onUp;
  final VoidCallback? onDown;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.only(left: AppSpacing.xs, right: AppSpacing.sm),
      decoration: BoxDecoration(
        color: t.surfaceAlt,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: t.border),
      ),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: index,
            child: Tooltip(
              message: 'Drag to reorder',
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Icon(Icons.drag_indicator, color: t.textTertiary),
              ),
            ),
          ),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: visible ? t.textPrimary : t.textTertiary)),
          ),
          IconButton(
            tooltip: 'Move $label up',
            onPressed: onUp,
            icon: const Icon(Icons.arrow_upward, size: 18),
          ),
          IconButton(
            tooltip: 'Move $label down',
            onPressed: onDown,
            icon: const Icon(Icons.arrow_downward, size: 18),
          ),
          Switch(value: visible, onChanged: onVisible),
        ],
      ),
    );
  }
}
