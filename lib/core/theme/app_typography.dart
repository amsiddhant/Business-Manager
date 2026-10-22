import 'package:flutter/painting.dart';

/// Figures that line up in columns — use for money, counts and percentages
/// so values don't jitter as they change.
const List<FontFeature> kTabularFigures = [FontFeature.tabularFigures()];

extension TabularText on TextStyle {
  /// This style with tabular (fixed-width) digits.
  TextStyle get tabular => copyWith(fontFeatures: kTabularFigures);
}
