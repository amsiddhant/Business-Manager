import 'package:flutter/material.dart';

import '../../core/enums.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/money.dart';

/// Renders a [Money] value with the correct currency symbol and grouping.
/// Negative amounts are shown in the error colour by default.
class CurrencyText extends StatelessWidget {
  const CurrencyText(
    this.money, {
    super.key,
    this.currency = CurrencyCode.inr,
    this.style,
    this.colorNegative = true,
    this.precise = false,
  });

  final Money money;
  final CurrencyCode currency;
  final TextStyle? style;
  final bool colorNegative;
  final bool precise;

  @override
  Widget build(BuildContext context) {
    final text = precise
        ? MoneyFormatter.formatPrecise(money, currency)
        : MoneyFormatter.format(money, currency);
    final effective = (style ?? const TextStyle()).copyWith(
      color: colorNegative && money.isNegative
          ? AppColors.error
          : style?.color,
    );
    return Text(text, style: effective);
  }
}
