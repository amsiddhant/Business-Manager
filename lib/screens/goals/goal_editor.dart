import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/app_exception.dart';
import '../../core/enums.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_x.dart';
import '../../core/utils/date_utils.dart';
import '../../data/repository.dart';
import '../../models/goal.dart';
import '../../services/profit_calculation_service.dart';
import '../../state/app_state.dart';
import '../../state/data_controller.dart';
import '../../state/org_settings.dart';
import '../../widgets/forms/app_form.dart';
import '../../widgets/forms/form_dialog.dart';
import '../../widgets/forms/form_fields.dart';
import 'goal_style.dart';

/// Opens the goal editor for [businessId] (null = every business) on
/// [period]'s tab. Resolves to true when goals were saved.
Future<bool> showGoalEditor(
  BuildContext context, {
  String? businessId,
  GoalPeriod? period,
}) async {
  final repository = context.read<AppState>().repository;
  final data = context.read<DataController>();
  final messenger = ScaffoldMessenger.maybeOf(context);
  final defaults = context.readOrgSettings().defaults.currency;
  final business = businessId == null ? null : data.businessById(businessId);
  final saved = await showAppForm<bool>(
    context: context,
    builder: (_) => GoalEditor(
      repository: repository,
      data: data,
      businessId: businessId,
      scopeName: businessId == null
          ? 'All businesses'
          : (business?.name ?? 'This business'),
      currency: business?.currency ?? defaults,
      period: period ?? GoalPeriod.containing(GoalPeriodType.month, DateTime.now()),
      messenger: messenger,
    ),
  );
  return saved ?? false;
}

/// Targets for a whole financial year in one place: months, quarters or the
/// year, for the figures you pick. Shows last year's actuals under each cell.
class GoalEditor extends StatefulWidget {
  const GoalEditor({
    super.key,
    required this.repository,
    required this.data,
    required this.businessId,
    required this.scopeName,
    required this.currency,
    required this.period,
    this.messenger,
  });

  final Repository repository;
  final DataController data;

  /// null = organisation-wide goals.
  final String? businessId;
  final String scopeName;
  final CurrencyCode currency;

  /// The period the editor opens on (its type picks the tab, its FY the year).
  final GoalPeriod period;
  final ScaffoldMessengerState? messenger;

  @override
  State<GoalEditor> createState() => _GoalEditorState();
}

class _GoalEditorState extends State<GoalEditor> {
  static const _service = ProfitCalculationService();
  static const _labelWidth = 108.0;
  static const _columnWidth = 160.0;

  late final int _fyStart;
  late GoalPeriodType _tab;
  final Set<GoalMetric> _metrics = {GoalMetric.revenue, GoalMetric.netProfit};
  final Map<String, TextEditingController> _cells = {};
  final Map<String, Goal> _existing = {};
  final Map<String, String> _errors = {};
  final Map<String, List<int>> _history = {};
  final _note = TextEditingController();
  String? _formError;
  FormHooks? _hooks;

  String get _scope => widget.businessId ?? Goal.allBusinesses;

  @override
  void initState() {
    super.initState();
    _fyStart = FinancialYear.forDate(widget.period.range.start).startYear;
    _tab = widget.period.type;
    final keys = {
      for (final type in GoalPeriodType.values)
        for (final p in _periodsFor(type)) p.key,
    };
    for (final g in widget.data.goalsFor(widget.businessId)) {
      if (!keys.contains(g.period.key)) continue;
      final key = _cellKey(g.period, g.metric);
      _existing[key] = g;
      _metrics.add(g.metric);
      _cells[key] = TextEditingController(text: _toText(g.metric, g.target));
    }
  }

  @override
  void dispose() {
    for (final c in _cells.values) {
      c.dispose();
    }
    _note.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- model --

  List<GoalPeriod> _periodsFor(GoalPeriodType type) => switch (type) {
        GoalPeriodType.month => GoalPeriod.financialYear(_fyStart).months,
        GoalPeriodType.quarter => [
            for (var q = 1; q <= 4; q++) GoalPeriod.quarter(_fyStart, q),
          ],
        GoalPeriodType.financialYear => [GoalPeriod.financialYear(_fyStart)],
      };

  List<GoalMetric> get _selected =>
      [for (final m in GoalMetric.values) if (_metrics.contains(m)) m];

  String _cellKey(GoalPeriod period, GoalMetric metric) =>
      '${period.key}|${metric.name}';

  TextEditingController _cell(GoalPeriod period, GoalMetric metric) =>
      _cells.putIfAbsent(_cellKey(period, metric), TextEditingController.new);

  /// A target as typed: major units for money, a whole number for counts.
  String _toText(GoalMetric metric, int value) {
    if (metric.isCount) return '$value';
    return value % 100 == 0
        ? '${value ~/ 100}'
        : (value / 100).toStringAsFixed(2);
  }

  /// (value, null) for a good entry, (null, null) for an empty one and
  /// (null, message) for a bad one.
  (int?, String?) _parse(GoalMetric metric, String raw) {
    final text = raw.trim().replaceAll(',', '');
    if (text.isEmpty) return (null, null);
    final int value;
    if (metric.isCount) {
      final n = int.tryParse(text);
      if (n == null) return (null, 'Whole numbers only');
      value = n;
    } else {
      final d = double.tryParse(text);
      if (d == null || !d.isFinite) return (null, 'Enter a number');
      value = (d * 100).round();
    }
    if (value < 0) return (null, "Can't be negative");
    if (value > Goal.maxTarget) return (null, 'Too large');
    return (value, null);
  }

  List<int> _historyFor(GoalPeriodType tab, GoalMetric metric) =>
      _history.putIfAbsent(
        '${tab.name}|${metric.name}',
        () => _service.metricByRange(
          metric: metric,
          orders: widget.data.ordersFor(widget.businessId),
          campaigns: widget.data.campaignsFor(widget.businessId),
          expenses: widget.data.expensesFor(widget.businessId),
          ranges: [for (final p in _periodsFor(tab)) p.yearEarlier.range],
        ),
      );

  void _changed() {
    _hooks?.markDirty();
    setState(() {});
  }

  // ---------------------------------------------------------- column tools --

  Future<void> _split(GoalMetric metric) async {
    final history = _historyFor(_tab, metric);
    final result = await showDialog<({String total, bool byLastYear})>(
      context: context,
      builder: (_) => _SplitDialog(
        metric: metric,
        currency: widget.currency,
        canUseLastYear: history.any((v) => v > 0),
      ),
    );
    if (result == null || !mounted) return;
    final (total, error) = _parse(metric, result.total);
    if (total == null || error != null) return;
    final periods = _periodsFor(_tab);
    final parts = _service.seasonalSplit(total, [
      for (final v in history) result.byLastYear ? v.toDouble() : 0.0,
    ]);
    for (var i = 0; i < periods.length; i++) {
      _cell(periods[i], metric).text = _toText(metric, parts[i]);
      _errors.remove(_cellKey(periods[i], metric));
    }
    _changed();
  }

  void _copyForward(GoalMetric metric) {
    String? last;
    for (final p in _periodsFor(_tab)) {
      final c = _cell(p, metric);
      if (c.text.trim().isEmpty) {
        if (last != null) c.text = last;
      } else {
        last = c.text;
      }
    }
    _changed();
  }

  void _clear(GoalMetric metric) {
    for (final p in _periodsFor(_tab)) {
      _cell(p, metric).clear();
      _errors.remove(_cellKey(p, metric));
    }
    _changed();
  }

  // ----------------------------------------------------------------- save --

  Future<bool> _save() async {
    final note = _note.text.trim();
    if (note.length > Goal.maxNote) {
      setState(() => _formError = 'The note can be up to ${Goal.maxNote} '
          'characters.');
      return false;
    }
    final errors = <String, String>{};
    GoalPeriodType? errorTab;
    final toSave = <Goal>[];
    final toDelete = <Goal>[];
    for (final type in GoalPeriodType.values) {
      for (final p in _periodsFor(type)) {
        for (final metric in _selected) {
          final key = _cellKey(p, metric);
          final controller = _cells[key];
          if (controller == null) continue;
          final existing = _existing[key];
          final (value, error) = _parse(metric, controller.text);
          if (error != null) {
            errors[key] = error;
            errorTab ??= type;
          } else if (value == null) {
            if (existing != null) toDelete.add(existing);
          } else if (existing == null) {
            toSave.add(Goal(
              businessId: _scope,
              period: p,
              metric: metric,
              target: value,
              currency: widget.currency,
              note: note,
            ));
          } else if (existing.target != value) {
            toSave.add(existing.copyWith(
              target: value,
              currency: widget.currency,
              note: note.isNotEmpty ? note : existing.note,
              audit: existing.audit,
            ));
          }
        }
      }
    }
    if (errors.isNotEmpty) {
      setState(() {
        _errors
          ..clear()
          ..addAll(errors);
        _tab = errorTab ?? _tab;
        _formError = 'Some targets need a look. They are outlined below.';
      });
      return false;
    }
    if (toSave.isEmpty && toDelete.isEmpty) return true;
    try {
      if (toSave.isNotEmpty) await widget.repository.saveGoals(toSave);
      if (toDelete.isNotEmpty) await widget.repository.deleteGoals(toDelete);
    } catch (e) {
      if (mounted) setState(() => _formError = ErrorMapper.friendly(e));
      return false;
    }
    final saved = toSave.length;
    final removed = toDelete.length;
    final parts = [
      if (saved > 0) 'Saved $saved ${saved == 1 ? 'goal' : 'goals'}',
      if (removed > 0)
        '${saved > 0 ? 'removed' : 'Removed'} $removed '
            '${removed == 1 ? 'goal' : 'goals'}',
    ];
    widget.messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(parts.join(', '))));
    return true;
  }

  // ---------------------------------------------------------------- build --

  @override
  Widget build(BuildContext context) {
    return FormDialog(
      title: 'Set goals',
      subtitle:
          '${widget.scopeName} · ${GoalPeriod.financialYear(_fyStart).label}',
      icon: Icons.flag_outlined,
      width: 760,
      submitLabel: 'Save goals',
      onSubmit: _save,
      child: Builder(builder: (context) {
        _hooks = FormHooksScope.maybeOf(context);
        return _body(context);
      }),
    );
  }

  Widget _body(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_formError != null) ...[
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: t.errorSurface,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline, size: 18, color: t.error),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(_formError!,
                      style: TextStyle(color: t.error, fontSize: 13)),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        Text('Figures to set targets for',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: t.textSecondary)),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final m in GoalMetric.values)
              FilterChip(
                label: Text(m.label),
                selected: _metrics.contains(m),
                onSelected: (on) => setState(
                    () => on ? _metrics.add(m) : _metrics.remove(m)),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        SegmentedButton<GoalPeriodType>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: GoalPeriodType.month, label: Text('Monthly')),
            ButtonSegment(
                value: GoalPeriodType.quarter, label: Text('Quarterly')),
            ButtonSegment(
                value: GoalPeriodType.financialYear, label: Text('Yearly')),
          ],
          selected: {_tab},
          onSelectionChanged: (s) => setState(() => _tab = s.first),
        ),
        const SizedBox(height: AppSpacing.lg),
        _matrix(context),
        const SizedBox(height: AppSpacing.xl),
        LabeledField(
          label: 'Note (optional)',
          helper: 'Added to the goals you create or change here.',
          child: TextField(
            controller: _note,
            maxLines: 2,
            maxLength: Goal.maxNote,
            onChanged: (_) => _hooks?.markDirty(),
            decoration: const InputDecoration(
              hintText: 'Why these targets? Anything to remember?',
            ),
          ),
        ),
      ],
    );
  }

  Widget _matrix(BuildContext context) {
    final t = context.tokens;
    final metrics = _selected;
    if (metrics.isEmpty) {
      return Text('Choose at least one figure above to set its targets.',
          style: TextStyle(color: t.textSecondary, fontSize: 13));
    }
    final periods = _periodsFor(_tab);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(width: _labelWidth),
              for (final m in metrics) _header(context, m),
            ],
          ),
          Divider(height: AppSpacing.md, color: t.border),
          for (var i = 0; i < periods.length; i++)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: _labelWidth,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 11),
                    child: _rowLabel(context, periods[i]),
                  ),
                ),
                for (final m in metrics) _cellField(context, i, periods[i], m),
              ],
            ),
        ],
      ),
    );
  }

  Widget _rowLabel(BuildContext context, GoalPeriod p) {
    final t = context.tokens;
    final main = switch (p.type) {
      GoalPeriodType.month => AppDate.monthYear(p.range.start),
      GoalPeriodType.quarter => 'Q${p.index}',
      GoalPeriodType.financialYear => p.label,
    };
    final sub = p.type == GoalPeriodType.quarter
        ? '${DateFormat('MMM').format(p.range.start)} – '
            '${DateFormat('MMM').format(p.range.end)}'
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(main,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: t.textPrimary)),
        if (sub != null)
          Text(sub, style: TextStyle(fontSize: 11.5, color: t.textTertiary)),
      ],
    );
  }

  Widget _header(BuildContext context, GoalMetric metric) {
    final t = context.tokens;
    return SizedBox(
      width: _columnWidth,
      child: Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(metric.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: t.textPrimary)),
            ),
            PopupMenuButton<String>(
              tooltip: '${metric.label} tools',
              icon: Icon(Icons.more_vert, size: 18, color: t.textSecondary),
              onSelected: (v) {
                switch (v) {
                  case 'split':
                    _split(metric);
                  case 'copy':
                    _copyForward(metric);
                  case 'clear':
                    _clear(metric);
                }
              },
              itemBuilder: (_) => [
                if (_tab != GoalPeriodType.financialYear)
                  const PopupMenuItem(
                      value: 'split', child: Text('Split a yearly total…')),
                const PopupMenuItem(value: 'copy', child: Text('Copy forward')),
                const PopupMenuItem(value: 'clear', child: Text('Clear')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _cellField(
      BuildContext context, int index, GoalPeriod period, GoalMetric metric) {
    final t = context.tokens;
    final key = _cellKey(period, metric);
    final error = _errors[key];
    final last = _historyFor(_tab, metric)[index];
    final hint = error ??
        (last > 0
            ? 'Last year ${GoalStyle.value(metric, last, widget.currency, compact: true)}'
            : 'Last year: none');
    final radius = BorderRadius.circular(AppSpacing.radiusSm);
    final errorBorder = error == null
        ? null
        : OutlineInputBorder(
            borderRadius: radius, borderSide: BorderSide(color: t.error));
    return SizedBox(
      width: _columnWidth,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              label: '${metric.label} target for ${period.label}',
              child: TextField(
                controller: _cell(period, metric),
                textInputAction: TextInputAction.next,
                keyboardType: metric.isCount
                    ? TextInputType.number
                    : const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                      RegExp(metric.isCount ? r'[0-9]' : r'[0-9.,]')),
                ],
                onChanged: (_) {
                  _errors.remove(key);
                  _hooks?.markDirty();
                  setState(() {});
                },
                decoration: InputDecoration(
                  isDense: true,
                  prefixText: metric.isMoney ? '${widget.currency.symbol} ' : null,
                  enabledBorder: errorBorder,
                  focusedBorder: errorBorder,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 2),
              child: Text(hint,
                  style: TextStyle(
                      fontSize: 11,
                      color: error == null ? t.textTertiary : t.error)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Asks for a yearly total and how to spread it.
class _SplitDialog extends StatefulWidget {
  const _SplitDialog({
    required this.metric,
    required this.currency,
    required this.canUseLastYear,
  });

  final GoalMetric metric;
  final CurrencyCode currency;
  final bool canUseLastYear;

  @override
  State<_SplitDialog> createState() => _SplitDialogState();
}

class _SplitDialogState extends State<_SplitDialog> {
  final _total = TextEditingController();
  late bool _byLastYear = widget.canUseLastYear;

  @override
  void dispose() {
    _total.dispose();
    super.dispose();
  }

  void _apply() {
    if (_total.text.trim().isEmpty) return;
    Navigator.pop(context, (total: _total.text, byLastYear: _byLastYear));
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.metric;
    return AlertDialog(
      title: Text('Split a yearly ${m.label.toLowerCase()} total'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _total,
              autofocus: true,
              onSubmitted: (_) => _apply(),
              keyboardType: m.isCount
                  ? TextInputType.number
                  : const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                    RegExp(m.isCount ? r'[0-9]' : r'[0-9.,]')),
              ],
              decoration: InputDecoration(
                labelText: 'Yearly total',
                prefixText: m.isMoney ? '${widget.currency.symbol} ' : null,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: [
                const ButtonSegment(value: false, label: Text('Evenly')),
                ButtonSegment(
                    value: true,
                    enabled: widget.canUseLastYear,
                    label: const Text('Like last year')),
              ],
              selected: {_byLastYear},
              onSelectionChanged: (s) => setState(() => _byLastYear = s.first),
            ),
            if (!widget.canUseLastYear) ...[
              const SizedBox(height: AppSpacing.sm),
              Text('There is no data from last year to follow.',
                  style: TextStyle(
                      fontSize: 12, color: context.tokens.textTertiary)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _apply, child: const Text('Split')),
      ],
    );
  }
}
