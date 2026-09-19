import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_utils.dart';
import '../../state/filter_controller.dart';

/// Global reporting-period selector. Opens a menu to choose FY / calendar year /
/// quarter / month / custom range (spec §43).
class PeriodSelector extends StatelessWidget {
  const PeriodSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final filter = context.watch<FilterController>();

    return InkWell(
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      onTap: () => _openMenu(context, filter),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: 9),
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.calendar_month_outlined,
                size: 18, color: AppColors.textSecondary),
            const SizedBox(width: AppSpacing.sm),
            Text(filter.periodLabel,
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w500)),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_drop_down, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  Future<void> _openMenu(
      BuildContext context, FilterController filter) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _PeriodDialog(filter: filter),
    );
  }
}

class _PeriodDialog extends StatefulWidget {
  const _PeriodDialog({required this.filter});
  final FilterController filter;

  @override
  State<_PeriodDialog> createState() => _PeriodDialogState();
}

class _PeriodDialogState extends State<_PeriodDialog> {
  late PeriodType _type = widget.filter.periodType;

  @override
  Widget build(BuildContext context) {
    final filter = widget.filter;
    final currentFy = FinancialYear.forDate(DateTime.now());
    final fyOptions = [
      currentFy.next,
      currentFy,
      currentFy.previous,
      currentFy.previous.previous,
    ];
    final now = DateTime.now();

    return AlertDialog(
      title: const Text('Select period'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                for (final t in PeriodType.values)
                  ChoiceChip(
                    label: Text(t.label),
                    selected: _type == t,
                    onSelected: (_) => setState(() => _type = t),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.lg),
            _body(context, filter, fyOptions, currentFy, now),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _body(BuildContext context, FilterController filter,
      List<FinancialYear> fyOptions, FinancialYear currentFy, DateTime now) {
    switch (_type) {
      case PeriodType.financialYear:
        final selectedFy = filter.periodType == PeriodType.financialYear
            ? filter.financialYear.startYear
            : currentFy.startYear;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final fy in fyOptions)
              _SelectTile(
                label: fy.label,
                selected: fy.startYear == selectedFy,
                onTap: () {
                  filter.setFinancialYear(fy);
                  Navigator.of(context).pop();
                },
              ),
          ],
        );
      case PeriodType.calendarYear:
        final years = [now.year + 1, now.year, now.year - 1, now.year - 2];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final y in years)
              _SelectTile(
                label: 'CY $y',
                selected: filter.periodType == PeriodType.calendarYear &&
                    y == filter.calendarYear,
                onTap: () {
                  filter.setCalendarYear(y);
                  Navigator.of(context).pop();
                },
              ),
          ],
        );
      case PeriodType.quarter:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Within ${filter.financialYear.label}',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12.5)),
            const SizedBox(height: AppSpacing.sm),
            for (final q in FinancialQuarter.values)
              _SelectTile(
                label: q.label,
                selected: filter.periodType == PeriodType.quarter &&
                    q == filter.quarter,
                onTap: () {
                  filter.setQuarter(q);
                  Navigator.of(context).pop();
                },
              ),
          ],
        );
      case PeriodType.month:
        return _MonthPicker(
          initial: DateTime(filter.monthYear, filter.month),
          onPicked: (d) {
            filter.setMonth(d.month, d.year);
            Navigator.of(context).pop();
          },
        );
      case PeriodType.custom:
        return Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.date_range, size: 18),
            label: const Text('Pick date range'),
            onPressed: () async {
              final picked = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2015),
                lastDate: DateTime(2100),
                initialDateRange: DateTimeRange(
                    start: filter.range.start, end: filter.range.end),
              );
              if (picked != null && context.mounted) {
                filter.setCustomRange(DateRange(picked.start, picked.end));
                Navigator.of(context).pop();
              }
            },
          ),
        );
    }
  }
}

class _MonthPicker extends StatelessWidget {
  const _MonthPicker({required this.initial, required this.onPicked});
  final DateTime initial;
  final ValueChanged<DateTime> onPicked;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final months = List.generate(
        18, (i) => DateTime(now.year, now.month - i));
    return SizedBox(
      height: 220,
      child: ListView(
        children: [
          for (final m in months)
            _SelectTile(
              label: AppDate.monthYear(m),
              selected: m.year == initial.year && m.month == initial.month,
              onTap: () => onPicked(m),
            ),
        ],
      ),
    );
  }
}

/// A selectable list tile with a leading radio-style indicator, replacing the
/// deprecated RadioListTile.
class _SelectTile extends StatelessWidget {
  const _SelectTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 20,
              color: selected ? AppColors.primary : AppColors.textTertiary,
            ),
            const SizedBox(width: AppSpacing.md),
            Text(label,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.w400)),
          ],
        ),
      ),
    );
  }
}
