import 'package:intl/intl.dart';

import '../enums.dart';

/// A money value stored in integer **minor units** (e.g. paise for INR, cents
/// for USD) to avoid floating point rounding errors in financial arithmetic.
///
/// All arithmetic is done on the integer [minor] amount. Conversion to/from
/// human readable major-unit doubles happens only at the UI boundary.
class Money {
  const Money(this.minor);

  /// The amount expressed in the smallest currency unit (1/100 of the major
  /// unit for all currently supported currencies).
  final int minor;

  static const int _unit = 100;

  static const Money zero = Money(0);

  /// Builds a [Money] from a major-unit value (e.g. rupees) supplied as a
  /// double, rounding to the nearest minor unit.
  factory Money.fromMajor(num major) => Money((major * _unit).round());

  /// Parses a user supplied string such as "1,25,000.50" into money.
  factory Money.parse(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[^0-9.\-]'), '');
    if (cleaned.isEmpty || cleaned == '-') return Money.zero;
    final value = double.tryParse(cleaned) ?? 0;
    return Money.fromMajor(value);
  }

  double get major => minor / _unit;

  Money operator +(Money other) => Money(minor + other.minor);
  Money operator -(Money other) => Money(minor - other.minor);
  Money operator *(num factor) => Money((minor * factor).round());
  Money operator /(num divisor) =>
      divisor == 0 ? Money.zero : Money((minor / divisor).round());

  bool operator >(Money other) => minor > other.minor;
  bool operator <(Money other) => minor < other.minor;
  bool operator >=(Money other) => minor >= other.minor;
  bool operator <=(Money other) => minor <= other.minor;

  bool get isZero => minor == 0;
  bool get isNegative => minor < 0;
  bool get isPositive => minor > 0;

  @override
  bool operator ==(Object other) => other is Money && other.minor == minor;

  @override
  int get hashCode => minor.hashCode;

  @override
  String toString() => 'Money($minor)';
}

/// Formats [Money] values for display, honouring the business currency and
/// (for INR) the Indian grouping convention.
class MoneyFormatter {
  MoneyFormatter._();

  static final Map<String, NumberFormat> _cache = {};

  static NumberFormat _formatterFor(CurrencyCode currency, int decimals) {
    final key = '${currency.wire}_$decimals';
    return _cache.putIfAbsent(key, () {
      switch (currency) {
        case CurrencyCode.inr:
          // Indian grouping: 1,25,000
          return NumberFormat.currency(
            locale: 'en_IN',
            symbol: currency.symbol,
            decimalDigits: decimals,
          );
        case CurrencyCode.usd:
        case CurrencyCode.eur:
        case CurrencyCode.gbp:
          return NumberFormat.currency(
            locale: 'en_US',
            symbol: currency.symbol,
            decimalDigits: decimals,
          );
      }
    });
  }

  /// Formats a money value with currency symbol. Whole amounts drop the
  /// decimals for a cleaner dashboard; fractional amounts keep 2 places.
  static String format(Money money, CurrencyCode currency) {
    final hasFraction = money.minor % 100 != 0;
    return _formatterFor(currency, hasFraction ? 2 : 0).format(money.major);
  }

  /// Always formats with 2 decimal places (used in tables / exports).
  static String formatPrecise(Money money, CurrencyCode currency) =>
      _formatterFor(currency, 2).format(money.major);

  /// Compact form for chart axes / scorecards: ₹1.2L, ₹3.4Cr, $1.2K, $3.4M.
  static String compact(Money money, CurrencyCode currency) {
    final value = money.major;
    final sign = value < 0 ? '-' : '';
    final abs = value.abs();
    if (currency == CurrencyCode.inr) {
      if (abs >= 10000000) {
        return '$sign${currency.symbol}${(abs / 10000000).toStringAsFixed(2)}Cr';
      }
      if (abs >= 100000) {
        return '$sign${currency.symbol}${(abs / 100000).toStringAsFixed(2)}L';
      }
      if (abs >= 1000) {
        return '$sign${currency.symbol}${(abs / 1000).toStringAsFixed(1)}K';
      }
      return '$sign${currency.symbol}${abs.toStringAsFixed(0)}';
    }
    if (abs >= 1000000000) {
      return '$sign${currency.symbol}${(abs / 1000000000).toStringAsFixed(2)}B';
    }
    if (abs >= 1000000) {
      return '$sign${currency.symbol}${(abs / 1000000).toStringAsFixed(2)}M';
    }
    if (abs >= 1000) {
      return '$sign${currency.symbol}${(abs / 1000).toStringAsFixed(1)}K';
    }
    return '$sign${currency.symbol}${abs.toStringAsFixed(0)}';
  }
}

/// Percentage formatting helpers with safe zero handling.
class PercentFormatter {
  PercentFormatter._();

  /// Formats a ratio-derived percentage. [value] is already a percentage
  /// (e.g. 37.8 -> "37.8%").
  static String format(double value, {int decimals = 1}) {
    if (value.isNaN || value.isInfinite) return '—';
    return '${value.toStringAsFixed(decimals)}%';
  }

  /// Formats ROAS multiples (e.g. 2.5 -> "2.5x"), returning N/A for undefined.
  static String roas(double? value) {
    if (value == null || value.isNaN || value.isInfinite) return 'N/A';
    return '${value.toStringAsFixed(2)}x';
  }
}
