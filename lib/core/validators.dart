/// Reusable form field validators. Each returns `null` when valid or an error
/// message string when invalid — the shape expected by [TextFormField].
class Validators {
  Validators._();

  static String? required(String? value, {String field = 'This field'}) {
    if (value == null || value.trim().isEmpty) return '$field is required';
    return null;
  }

  static String? email(String? value) {
    if (value == null || value.trim().isEmpty) return 'Email is required';
    final re = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$');
    if (!re.hasMatch(value.trim())) return 'Enter a valid email address';
    return null;
  }

  static String? password(String? value, {int min = 6}) {
    if (value == null || value.isEmpty) return 'Password is required';
    if (value.length < min) return 'Password must be at least $min characters';
    return null;
  }

  /// Validates an optional URL. Empty is allowed; if present it must parse to an
  /// absolute http/https URL.
  static String? url(String? value, {bool requiredField = false}) {
    if (value == null || value.trim().isEmpty) {
      return requiredField ? 'URL is required' : null;
    }
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !uri.hasScheme ||
        !(uri.scheme == 'http' || uri.scheme == 'https') ||
        !uri.hasAuthority) {
      return 'Enter a valid URL (https://…)';
    }
    return null;
  }

  /// Requires a non-negative number (>= 0).
  static String? nonNegativeNumber(String? value, {String field = 'Value'}) {
    if (value == null || value.trim().isEmpty) return '$field is required';
    final cleaned = value.replaceAll(RegExp(r'[,₹$€£\s]'), '');
    final parsed = double.tryParse(cleaned);
    if (parsed == null) return 'Enter a valid number';
    if (parsed < 0) return '$field cannot be negative';
    return null;
  }

  /// Optional non-negative number — empty is treated as valid (0).
  static String? optionalNonNegativeNumber(String? value,
      {String field = 'Value'}) {
    if (value == null || value.trim().isEmpty) return null;
    return nonNegativeNumber(value, field: field);
  }

  /// Requires a strictly positive integer (> 0), used for quantities.
  static String? positiveInteger(String? value, {String field = 'Value'}) {
    if (value == null || value.trim().isEmpty) return '$field is required';
    final parsed = int.tryParse(value.trim());
    if (parsed == null) return 'Enter a whole number';
    if (parsed <= 0) return '$field must be greater than zero';
    return null;
  }

  /// Composes multiple validators, returning the first error encountered.
  static String? Function(String?) compose(
      List<String? Function(String?)> validators) {
    return (value) {
      for (final v in validators) {
        final result = v(value);
        if (result != null) return result;
      }
      return null;
    };
  }
}
