import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_x.dart';
import '../../core/utils/date_utils.dart';
import 'app_form.dart';

/// A labelled wrapper placing a field label above its input, with an optional
/// "required" asterisk.
class LabeledField extends StatelessWidget {
  const LabeledField({
    super.key,
    required this.label,
    required this.child,
    this.isRequired = false,
    this.helper,
  });

  final String label;
  final Widget child;
  final bool isRequired;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: TextSpan(
            text: label,
            style: TextStyle(
                color: context.tokens.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500),
            children: [
              if (isRequired)
                TextSpan(
                    text: ' *', style: TextStyle(color: context.tokens.error)),
            ],
          ),
        ),
        const SizedBox(height: 6),
        child,
        if (helper != null) ...[
          const SizedBox(height: 4),
          Text(helper!,
              style: TextStyle(
                  color: context.tokens.textTertiary, fontSize: 11.5)),
        ],
      ],
    );
  }
}

/// A standard text form field with an outer label.
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.label,
    this.controller,
    this.initialValue,
    this.validator,
    this.keyboardType,
    this.isRequired = false,
    this.hintText,
    this.helper,
    this.maxLines = 1,
    this.obscureText = false,
    this.onChanged,
    this.inputFormatters,
    this.prefixText,
    this.enabled = true,
    this.prefixIcon,
    this.suffixIcon,
    this.textInputAction,
    this.onFieldSubmitted,
    this.autofillHints,
    this.focusNode,
    this.autofocus = false,
  });

  final String label;
  final TextEditingController? controller;
  final String? initialValue;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final bool isRequired;
  final String? hintText;
  final String? helper;
  final int maxLines;
  final bool obscureText;
  final ValueChanged<String>? onChanged;
  final List<TextInputFormatter>? inputFormatters;
  final String? prefixText;
  final bool enabled;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final Iterable<String>? autofillHints;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final hooks = FormHooksScope.maybeOf(context);
    // Passwords never go into a draft.
    if (hooks != null && controller != null && !obscureText && enabled) {
      hooks.registerText(label, controller!);
    }
    return LabeledField(
      label: label,
      isRequired: isRequired,
      helper: helper,
      child: TextFormField(
        controller: controller,
        initialValue: controller == null ? initialValue : null,
        validator: validator,
        keyboardType: keyboardType,
        maxLines: obscureText ? 1 : maxLines,
        obscureText: obscureText,
        onChanged: hooks == null
            ? onChanged
            : (v) {
                hooks.markDirty();
                onChanged?.call(v);
              },
        inputFormatters: inputFormatters,
        enabled: enabled,
        textInputAction: textInputAction,
        onFieldSubmitted: onFieldSubmitted,
        autofillHints: autofillHints,
        focusNode: focusNode,
        autofocus: autofocus,
        decoration: InputDecoration(
          hintText: hintText,
          prefixText: prefixText,
          prefixIcon: prefixIcon,
          suffixIcon: suffixIcon,
        ),
      ),
    );
  }
}

/// A money input that only accepts numbers/decimals and shows the currency
/// symbol. Digits are grouped once you leave the field (1,25,000 for ₹,
/// 125,000 otherwise); `Money.parse` and the validators ignore the commas.
class AppMoneyField extends StatefulWidget {
  const AppMoneyField({
    super.key,
    required this.label,
    required this.controller,
    this.isRequired = false,
    this.symbol = '₹',
    this.validator,
    this.helper,
    this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final bool isRequired;
  final String symbol;
  final String? Function(String?)? validator;
  final String? helper;
  final ValueChanged<String>? onChanged;

  @override
  State<AppMoneyField> createState() => _AppMoneyFieldState();
}

class _AppMoneyFieldState extends State<AppMoneyField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
    // After the first frame: the form may be listening to this controller.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_focus.hasFocus) _regroup();
    });
  }

  @override
  void dispose() {
    _focus
      ..removeListener(_onFocus)
      ..dispose();
    super.dispose();
  }

  void _onFocus() {
    if (_focus.hasFocus) {
      final c = widget.controller;
      final plain = c.text.replaceAll(',', '');
      if (plain != c.text) {
        c.value = TextEditingValue(
          text: plain,
          selection: TextSelection.collapsed(offset: plain.length),
        );
      }
    } else {
      _regroup();
    }
  }

  void _regroup() {
    final c = widget.controller;
    final grouped =
        groupMoneyDigits(c.text, indian: widget.symbol.trim() == '₹');
    if (grouped != c.text) c.text = grouped;
  }

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      label: widget.label,
      controller: widget.controller,
      focusNode: _focus,
      isRequired: widget.isRequired,
      validator: widget.validator,
      helper: widget.helper,
      onChanged: widget.onChanged,
      prefixText: '${widget.symbol} ',
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
      ],
    );
  }
}

/// "125000.5" → "1,25,000.5" ([indian]) or "125,000.5". Anything that isn't
/// a plain number comes back unchanged.
String groupMoneyDigits(String raw, {required bool indian}) {
  final plain = raw.replaceAll(',', '').trim();
  final m = RegExp(r'^(\d+)(\.\d*)?$').firstMatch(plain);
  if (m == null) return raw;
  final whole = m.group(1)!.replaceFirst(RegExp(r'^0+(?=\d)'), '');
  final fraction = m.group(2) ?? '';
  if (whole.length <= 3) return '$whole$fraction';
  final last3 = whole.substring(whole.length - 3);
  final rest = whole.substring(0, whole.length - 3);
  final size = indian ? 2 : 3;
  final groups = <String>[];
  for (var end = rest.length; end > 0; end -= size) {
    groups.insert(0, rest.substring((end - size).clamp(0, end), end));
  }
  return '${groups.join(',')},$last3$fraction';
}

/// A labelled dropdown.
class AppDropdown<T> extends StatelessWidget {
  const AppDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.itemLabel,
    required this.onChanged,
    this.isRequired = false,
    this.helper,
  });

  final String label;
  final T? value;
  final List<T> items;
  final String Function(T) itemLabel;
  final ValueChanged<T?> onChanged;
  final bool isRequired;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    return LabeledField(
      label: label,
      isRequired: isRequired,
      helper: helper,
      child: DropdownButtonFormField<T>(
        initialValue: value,
        isExpanded: true,
        items: [
          for (final item in items)
            DropdownMenuItem<T>(value: item, child: Text(itemLabel(item))),
        ],
        onChanged: (v) {
          FormHooksScope.maybeOf(context)?.markDirty();
          onChanged(v);
        },
      ),
    );
  }
}

/// A labelled, type-to-filter dropdown built on Material's [DropdownMenu].
///
/// Use this wherever a select has more than a handful of options or is scoped
/// to a linked entity (products of a business, customers of a business, …).
/// The caller is responsible for passing only the items the user is allowed to
/// see — filtering here is purely a UX convenience over that scoped list.
class AppSearchableDropdown<T> extends StatefulWidget {
  const AppSearchableDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.itemLabel,
    required this.onChanged,
    this.isRequired = false,
    this.helper,
    this.hintText,
    this.enabled = true,
  });

  final String label;
  final T? value;
  final List<T> items;
  final String Function(T) itemLabel;
  final ValueChanged<T?> onChanged;
  final bool isRequired;
  final String? helper;
  final String? hintText;
  final bool enabled;

  @override
  State<AppSearchableDropdown<T>> createState() =>
      _AppSearchableDropdownState<T>();
}

class _AppSearchableDropdownState<T> extends State<AppSearchableDropdown<T>> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value == null ? '' : widget.itemLabel(widget.value as T),
  );

  @override
  void didUpdateWidget(covariant AppSearchableDropdown<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keep the visible text in sync when the selection is changed externally
    // (e.g. the product's business changed and the customer ref was reset).
    if (widget.value != oldWidget.value) {
      final text =
          widget.value == null ? '' : widget.itemLabel(widget.value as T);
      if (_controller.text != text) _controller.text = text;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LabeledField(
      label: widget.label,
      isRequired: widget.isRequired,
      helper: widget.helper,
      child: DropdownMenu<T>(
        controller: _controller,
        enableFilter: true,
        requestFocusOnTap: true,
        enabled: widget.enabled,
        expandedInsets: EdgeInsets.zero,
        initialSelection: widget.value,
        hintText: widget.hintText,
        menuHeight: 320,
        inputDecorationTheme: Theme.of(context).inputDecorationTheme,
        onSelected: (v) {
          FormHooksScope.maybeOf(context)?.markDirty();
          widget.onChanged(v);
        },
        dropdownMenuEntries: [
          for (final item in widget.items)
            DropdownMenuEntry<T>(value: item, label: widget.itemLabel(item)),
        ],
      ),
    );
  }
}

/// A labelled date picker field. Optional dates can be cleared; "Today"
/// is one tap away, and the picker's pencil icon allows typing a date.
class AppDateField extends StatelessWidget {
  const AppDateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.isRequired = false,
    this.helper,
    this.firstDate,
    this.lastDate,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final bool isRequired;
  final String? helper;
  final DateTime? firstDate;
  final DateTime? lastDate;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final first = firstDate ?? DateTime(2015);
    final last = lastDate ?? DateTime(2100);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todayAllowed = !today.isBefore(DateUtils.dateOnly(first)) &&
        !today.isAfter(DateUtils.dateOnly(last));
    final isToday = value != null && DateUtils.isSameDay(value, today);

    void set(DateTime? d) {
      FormHooksScope.maybeOf(context)?.markDirty();
      onChanged(d);
    }

    return LabeledField(
      label: label,
      isRequired: isRequired,
      helper: helper,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        onTap: () async {
          final initial = value ?? (todayAllowed ? today : first);
          final picked = await showDatePicker(
            context: context,
            initialDate: initial.isBefore(first)
                ? first
                : (initial.isAfter(last) ? last : initial),
            firstDate: first,
            lastDate: last,
          );
          if (picked != null) set(picked);
        },
        child: InputDecorator(
          decoration: InputDecoration(
            prefixIcon: Icon(Icons.calendar_today_outlined,
                size: 18, color: t.textSecondary),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (todayAllowed && !isToday)
                  TextButton(
                    onPressed: () => set(today),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      textStyle: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                    child: const Text('Today'),
                  ),
                if (!isRequired && value != null)
                  IconButton(
                    tooltip: 'Clear date',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.close, size: 18, color: t.textSecondary),
                    onPressed: () => set(null),
                  ),
                const SizedBox(width: 4),
              ],
            ),
          ),
          child: Text(
            value == null ? 'Select date' : AppDate.format(value),
            style: TextStyle(
              color: value == null ? t.textTertiary : t.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
