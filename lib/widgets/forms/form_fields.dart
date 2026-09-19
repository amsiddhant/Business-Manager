import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_utils.dart';

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
            style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500),
            children: [
              if (isRequired)
                const TextSpan(
                    text: ' *', style: TextStyle(color: AppColors.error)),
            ],
          ),
        ),
        const SizedBox(height: 6),
        child,
        if (helper != null) ...[
          const SizedBox(height: 4),
          Text(helper!,
              style: const TextStyle(
                  color: AppColors.textTertiary, fontSize: 11.5)),
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

  @override
  Widget build(BuildContext context) {
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
        onChanged: onChanged,
        inputFormatters: inputFormatters,
        enabled: enabled,
        decoration: InputDecoration(hintText: hintText, prefixText: prefixText),
      ),
    );
  }
}

/// A money input that only accepts numbers/decimals and shows a currency prefix.
class AppMoneyField extends StatelessWidget {
  const AppMoneyField({
    super.key,
    required this.label,
    required this.controller,
    this.isRequired = false,
    this.symbol = '₹',
    this.validator,
    this.helper,
  });

  final String label;
  final TextEditingController controller;
  final bool isRequired;
  final String symbol;
  final String? Function(String?)? validator;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      label: label,
      controller: controller,
      isRequired: isRequired,
      validator: validator,
      helper: helper,
      prefixText: '$symbol ',
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
      ],
    );
  }
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
        onChanged: onChanged,
      ),
    );
  }
}

/// A labelled date picker field.
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
    return LabeledField(
      label: label,
      isRequired: isRequired,
      helper: helper,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: value ?? DateTime.now(),
            firstDate: firstDate ?? DateTime(2015),
            lastDate: lastDate ?? DateTime(2100),
          );
          if (picked != null) onChanged(picked);
        },
        child: InputDecorator(
          decoration: const InputDecoration(
            suffixIcon: Icon(Icons.calendar_today_outlined, size: 18),
          ),
          child: Text(
            value == null ? 'Select date' : AppDate.format(value),
            style: TextStyle(
              color: value == null
                  ? AppColors.textTertiary
                  : AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
