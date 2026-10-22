import 'package:flutter/material.dart';

/// Every colour the app paints with, for one brightness. Read it with
/// `context.tokens` (see `theme_x.dart`) — never hard-code a colour in a
/// widget, or it won't follow dark mode or the admin's brand colour.
///
/// The names match the old `AppColors` constants one-for-one, so the light
/// palette with the default brand is exactly what the app looked like before.
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.brightness,
    required this.primary,
    required this.primaryDark,
    required this.primaryLight,
    required this.primarySurface,
    required this.background,
    required this.card,
    required this.surfaceAlt,
    required this.border,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textOnPrimary,
    required this.success,
    required this.successSurface,
    required this.warning,
    required this.warningSurface,
    required this.error,
    required this.errorSurface,
    required this.info,
    required this.infoSurface,
    required this.chartSeries,
    required this.sidebar,
    required this.hover,
    required this.focusRing,
    required this.skeletonBase,
    required this.skeletonHighlight,
    required this.scrim,
    required this.inverseSurface,
    required this.onInverseSurface,
    required this.cardShadow,
    required this.raisedShadow,
  });

  final Brightness brightness;

  // Brand
  final Color primary;
  final Color primaryDark;
  final Color primaryLight;
  final Color primarySurface;

  // Surfaces
  final Color background;
  final Color card;
  final Color surfaceAlt;
  final Color border;
  final Color borderStrong;

  // Text
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textOnPrimary;

  // Status
  final Color success;
  final Color successSurface;
  final Color warning;
  final Color warningSurface;
  final Color error;
  final Color errorSurface;
  final Color info;
  final Color infoSurface;

  /// Ten distinguishable series colours, readable on [card].
  final List<Color> chartSeries;

  // Chrome and states
  final Color sidebar;
  final Color hover;
  final Color focusRing;
  final Color skeletonBase;
  final Color skeletonHighlight;
  final Color scrim;

  /// Snackbars and tooltips: the opposite of [card].
  final Color inverseSurface;
  final Color onInverseSurface;

  final List<BoxShadow> cardShadow;
  final List<BoxShadow> raisedShadow;

  bool get isDark => brightness == Brightness.dark;

  /// The text colour that reads best on [background] — white or near-black.
  Color onColor(Color background) =>
      contrastRatio(Colors.white, background) >=
              contrastRatio(textOnLight, background)
          ? Colors.white
          : textOnLight;

  static const Color textOnLight = Color(0xFF111827);

  /// WCAG contrast ratio between two colours (1–21).
  static double contrastRatio(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  /// Tokens are only ever produced by `AppPalette`; there is nothing to copy.
  @override
  AppTokens copyWith() => this;

  @override
  AppTokens lerp(AppTokens? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppTokens(
      brightness: t < 0.5 ? brightness : other.brightness,
      primary: c(primary, other.primary),
      primaryDark: c(primaryDark, other.primaryDark),
      primaryLight: c(primaryLight, other.primaryLight),
      primarySurface: c(primarySurface, other.primarySurface),
      background: c(background, other.background),
      card: c(card, other.card),
      surfaceAlt: c(surfaceAlt, other.surfaceAlt),
      border: c(border, other.border),
      borderStrong: c(borderStrong, other.borderStrong),
      textPrimary: c(textPrimary, other.textPrimary),
      textSecondary: c(textSecondary, other.textSecondary),
      textTertiary: c(textTertiary, other.textTertiary),
      textOnPrimary: c(textOnPrimary, other.textOnPrimary),
      success: c(success, other.success),
      successSurface: c(successSurface, other.successSurface),
      warning: c(warning, other.warning),
      warningSurface: c(warningSurface, other.warningSurface),
      error: c(error, other.error),
      errorSurface: c(errorSurface, other.errorSurface),
      info: c(info, other.info),
      infoSurface: c(infoSurface, other.infoSurface),
      chartSeries: [
        for (var i = 0; i < chartSeries.length; i++)
          c(chartSeries[i],
              other.chartSeries[i % other.chartSeries.length]),
      ],
      sidebar: c(sidebar, other.sidebar),
      hover: c(hover, other.hover),
      focusRing: c(focusRing, other.focusRing),
      skeletonBase: c(skeletonBase, other.skeletonBase),
      skeletonHighlight: c(skeletonHighlight, other.skeletonHighlight),
      scrim: c(scrim, other.scrim),
      inverseSurface: c(inverseSurface, other.inverseSurface),
      onInverseSurface: c(onInverseSurface, other.onInverseSurface),
      cardShadow: BoxShadow.lerpList(cardShadow, other.cardShadow, t)!,
      raisedShadow: BoxShadow.lerpList(raisedShadow, other.raisedShadow, t)!,
    );
  }
}
