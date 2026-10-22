import 'package:flutter/material.dart';

/// How tightly controls and table rows are packed. Comfortable is the
/// app's original spacing.
enum AppDensity {
  compact('Compact', controlHeight: 36, rowHeight: 40, fieldPadding: 8),
  comfortable('Comfortable',
      controlHeight: 40, rowHeight: 48, fieldPadding: 12),
  spacious('Spacious', controlHeight: 44, rowHeight: 56, fieldPadding: 14);

  const AppDensity(
    this.label, {
    required this.controlHeight,
    required this.rowHeight,
    required this.fieldPadding,
  });

  final String label;
  final double controlHeight;
  final double rowHeight;

  /// Vertical padding inside text fields.
  final double fieldPadding;

  VisualDensity get visualDensity => switch (this) {
        AppDensity.compact => const VisualDensity(horizontal: -1, vertical: -2),
        AppDensity.comfortable => VisualDensity.standard,
        AppDensity.spacious => const VisualDensity(horizontal: 0, vertical: 1),
      };

  static AppDensity fromName(String? name) => AppDensity.values
      .firstWhere((d) => d.name == name, orElse: () => AppDensity.comfortable);
}

/// Carries the active [AppDensity] in the theme; read with `context.density`.
@immutable
class AppDensityTheme extends ThemeExtension<AppDensityTheme> {
  const AppDensityTheme(this.density);

  final AppDensity density;

  @override
  AppDensityTheme copyWith({AppDensity? density}) =>
      AppDensityTheme(density ?? this.density);

  @override
  AppDensityTheme lerp(AppDensityTheme? other, double t) =>
      t < 0.5 || other == null ? this : other;
}
