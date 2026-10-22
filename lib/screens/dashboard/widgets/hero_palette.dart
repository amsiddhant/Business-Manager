import 'package:flutter/material.dart';

import '../../../core/theme/theme_x.dart';

/// The hero band's colours, derived from the brand so they follow the admin's
/// brand colour and both themes. Light theme: a vivid brand gradient. Dark
/// theme: the brand sunk towards the canvas, so it glows without glaring.
class HeroPalette {
  const HeroPalette._(this.foreground, this.gradient, this.glows);

  /// Text and icons on the band (AA against every gradient stop).
  final Color foreground;
  final List<Color> gradient;

  /// The soft colour washes painted over the gradient.
  final List<Color> glows;

  factory HeroPalette.of(AppTokens t) {
    if (t.isDark) {
      return HeroPalette._(
        t.textPrimary,
        [
          Color.lerp(t.primary, t.background, 0.72)!,
          Color.lerp(t.primary, t.background, 0.5)!,
          Color.lerp(t.primary, t.background, 0.64)!,
        ],
        [
          t.chartSeries[5].withValues(alpha: 0.16),
          t.chartSeries[6].withValues(alpha: 0.12),
        ],
      );
    }
    final fg = t.textOnPrimary;
    // Push the far end away from the text colour, so contrast only improves.
    final away = fg.computeLuminance() > 0.5 ? Colors.black : Colors.white;
    return HeroPalette._(
      fg,
      [
        Color.lerp(t.primary, away, 0.32)!,
        t.primary,
        Color.lerp(t.primary, away, 0.14)!,
      ],
      [
        t.chartSeries[5].withValues(alpha: 0.30),
        t.chartSeries[6].withValues(alpha: 0.22),
      ],
    );
  }
}
