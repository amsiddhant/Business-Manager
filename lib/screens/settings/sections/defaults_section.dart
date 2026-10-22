import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/enums.dart';
import '../../../core/utils/date_utils.dart';
import '../../../models/app_settings.dart';
import '../../../widgets/forms/form_fields.dart';
import '../settings_draft.dart';
import '../settings_widgets.dart';

/// What new businesses, dashboards and tables start with.
class DefaultsSection extends StatelessWidget {
  const DefaultsSection({super.key, required this.draft});

  final SettingsDraft draft;

  static const _months = {
    1: 'January',
    4: 'April',
    7: 'July',
    10: 'October',
  };

  @override
  Widget build(BuildContext context) {
    final d = draft.settings.defaults;
    final sync = draft.settings.sync;
    final now = DateTime.now();
    void set(DefaultSettings Function(DefaultSettings d) change) =>
        draft.update((s) => s.copyWith(defaults: change(s.defaults)));

    String sample(String pattern) {
      try {
        return DateFormat(pattern).format(now);
      } catch (_) {
        return pattern;
      }
    }

    return SettingsPanel(
      title: 'Defaults',
      subtitle: 'What people start with before they choose their own',
      onReset: () => draft.resetSection((s, df) =>
          s.copyWith(defaults: df.defaults, sync: df.sync)),
      children: [
        SettingsCard(
          title: 'Formats',
          children: [
            SettingsGrid(children: [
              AppDropdown<CurrencyCode>(
                label: 'Currency for new businesses',
                value: d.currency,
                items: CurrencyCode.values,
                itemLabel: (c) => '${c.symbol}  ${c.label} (${c.wire})',
                onChanged: (v) => set((x) => x.copyWith(currency: v)),
              ),
              AppDropdown<String>(
                label: 'Date format',
                value: d.dateFormat,
                items: DefaultSettings.dateFormats,
                itemLabel: (f) => '${sample(f)}   ($f)',
                onChanged: (v) => set((x) => x.copyWith(dateFormat: v)),
              ),
              AppDropdown<NumberGrouping>(
                label: 'Number grouping',
                value: d.numberGrouping,
                items: NumberGrouping.values,
                itemLabel: (g) => '${g.label}: ${g.example}',
                onChanged: (v) => set((x) => x.copyWith(numberGrouping: v)),
              ),
            ]),
          ],
        ),
        SettingsCard(
          title: 'Reports and dashboard',
          children: [
            SettingsGrid(children: [
              AppDropdown<PeriodType>(
                label: 'Default period',
                helper: 'For people who haven’t picked one yet.',
                value: d.period,
                items: DefaultSettings.periods,
                itemLabel: (p) => p.label,
                onChanged: (v) => set((x) => x.copyWith(period: v)),
              ),
              AppDropdown<ComparisonBasis>(
                label: 'Compare with',
                value: d.comparison,
                items: ComparisonBasis.values,
                itemLabel: (c) => c.label,
                onChanged: (v) => set((x) => x.copyWith(comparison: v)),
              ),
            ]),
            const SizedBox(height: 20),
            ChoiceRow<int>(
              label: 'Financial year starts in',
              value: d.fyStartMonth,
              options: FinancialYear.startMonths,
              labelOf: (m) => _months[m] ?? '$m',
              onChanged: (m) => set((x) => x.copyWith(fyStartMonth: m)),
            ),
            const SizedBox(height: 12),
            SettingsNote(
              'Changing the start month changes how financial years, quarters '
              'and financial-year goals are counted for everyone.',
              tone: d.fyStartMonth == FinancialYear.defaultStartMonth
                  ? SettingsNoteTone.info
                  : SettingsNoteTone.warning,
            ),
          ],
        ),
        SettingsCard(
          title: 'Orders and tables',
          children: [
            ChoiceRow<OrderStatus?>(
              label: 'Status for new orders',
              value: d.orderStatus,
              options: [null, ...OrderStatus.values],
              labelOf: (s) => s?.label ?? 'None',
              onChanged: (v) => set((x) => x.copyWith(orderStatus: () => v)),
            ),
            const SizedBox(height: 20),
            ChoiceRow<int>(
              label: 'Rows per table page',
              value: d.pageSize,
              options: DefaultSettings.pageSizes,
              labelOf: (n) => '$n',
              onChanged: (n) => set((x) => x.copyWith(pageSize: n)),
            ),
          ],
        ),
        SettingsCard(
          title: 'Data refresh',
          children: [
            ChoiceRow<int>(
              label: 'Refresh data when the tab comes back after',
              helper: 'Each refresh reads from the server, so keep it modest. '
                  '“Off” refreshes only when someone taps Sync now.',
              value: sync.autoRefreshMinutes,
              options: SyncSettings.choices,
              labelOf: (m) => m == 0 ? 'Off' : '$m min',
              onChanged: (m) => draft.update(
                  (s) => s.copyWith(sync: SyncSettings(autoRefreshMinutes: m))),
            ),
          ],
        ),
      ],
    );
  }
}
