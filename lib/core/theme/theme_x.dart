import 'package:flutter/material.dart';

import 'app_density.dart';
import 'app_motion.dart';
import 'app_palette.dart';
import 'tokens.dart';

export 'app_density.dart' show AppDensity;
export 'app_motion.dart' show AppMotion, MotionLevel;
export 'tokens.dart' show AppTokens;

/// Shorthands for the design system: `context.tokens.textSecondary`,
/// `context.motion.base`, `context.density.rowHeight`.
extension ThemeX on BuildContext {
  /// The colours for the current theme. Falls back to the default palette for
  /// the theme's brightness when no `AppTokens` is installed (e.g. a bare
  /// `MaterialApp` in a widget test).
  AppTokens get tokens {
    final theme = Theme.of(this);
    return theme.extension<AppTokens>() ??
        (theme.brightness == Brightness.dark
            ? AppPalette.darkDefault
            : AppPalette.lightDefault);
  }

  /// The effective motion: the app's setting, made stricter by the operating
  /// system's "reduce motion" preference.
  AppMotion get motion {
    final level = Theme.of(this).extension<AppMotion>()?.level ??
        MotionLevel.full;
    final os = MediaQuery.maybeDisableAnimationsOf(this) ?? false;
    return AppMotion(os ? level.atMost(MotionLevel.reduced) : level);
  }

  AppDensity get density =>
      Theme.of(this).extension<AppDensityTheme>()?.density ??
      AppDensity.comfortable;
}
