import 'package:flutter/material.dart';

import '../../models/app_settings.dart' show ChartPaletteStyle;
import 'app_colors.dart';
import 'tokens.dart';

/// Builds [AppTokens] for a brand colour and brightness.
///
/// Light with the default brand is the exact palette the app always had
/// (`AppColors`). Dark is muted rather than neon: a deep blue-grey canvas,
/// and the brand and status colours lifted until they meet WCAG AA (4.5:1)
/// on the card surface, so text in those colours stays readable.
class AppPalette {
  AppPalette._();

  static const Color defaultBrand = AppColors.primary;

  static final AppTokens lightDefault = light();
  static final AppTokens darkDefault = dark();

  static AppTokens light({
    Color brand = defaultBrand,
    ChartPaletteStyle chartPalette = ChartPaletteStyle.brand,
  }) {
    const card = AppColors.card;
    final isDefault = brand.toARGB32() == defaultBrand.toARGB32();
    final primary = brand;
    return AppTokens(
      brightness: Brightness.light,
      primary: primary,
      primaryDark: isDefault ? AppColors.primaryDark : _shift(primary, -0.14),
      primaryLight:
          isDefault ? AppColors.primaryLight : _tint(primary, card, 0.10),
      primarySurface:
          isDefault ? AppColors.primarySurface : _tint(primary, card, 0.07),
      background: AppColors.background,
      card: card,
      surfaceAlt: AppColors.surfaceAlt,
      border: AppColors.border,
      borderStrong: AppColors.borderStrong,
      textPrimary: AppColors.textPrimary,
      textSecondary: AppColors.textSecondary,
      textTertiary: AppColors.textTertiary,
      textOnPrimary: isDefault ? AppColors.textOnPrimary : _on(primary),
      success: AppColors.success,
      successSurface: AppColors.successSurface,
      warning: AppColors.warning,
      warningSurface: AppColors.warningSurface,
      error: AppColors.error,
      errorSurface: AppColors.errorSurface,
      info: AppColors.info,
      infoSurface: AppColors.infoSurface,
      chartSeries: _chartColors(chartPalette, primary),
      sidebar: card,
      hover: AppColors.textPrimary.withValues(alpha: 0.04),
      focusRing: primary,
      skeletonBase: AppColors.surfaceAlt,
      skeletonHighlight: AppColors.border,
      scrim: const Color(0x66111827),
      inverseSurface: AppColors.textPrimary,
      onInverseSurface: Colors.white,
      cardShadow: [
        BoxShadow(
          color: const Color(0xFF1F2937).withValues(alpha: 0.05),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ],
      raisedShadow: [
        BoxShadow(
          color: const Color(0xFF1F2937).withValues(alpha: 0.10),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }

  static AppTokens dark({
    Color brand = defaultBrand,
    ChartPaletteStyle chartPalette = ChartPaletteStyle.brand,
  }) {
    const canvas = Color(0xFF0E1016);
    const card = Color(0xFF161A23);
    final primary = readableOn(brand, card);
    Color status(Color c) => readableOn(c, card);
    final success = status(AppColors.success);
    final warning = status(AppColors.warning);
    final error = status(AppColors.error);
    final info = status(AppColors.info);
    return AppTokens(
      brightness: Brightness.dark,
      primary: primary,
      primaryDark: _shift(primary, -0.10),
      primaryLight: _tint(primary, card, 0.18),
      primarySurface: _tint(primary, card, 0.10),
      background: canvas,
      card: card,
      surfaceAlt: const Color(0xFF1C212C),
      border: const Color(0xFF272D39),
      borderStrong: const Color(0xFF363D4B),
      textPrimary: const Color(0xFFE8EAF0),
      textSecondary: const Color(0xFFA4AAB8),
      textTertiary: const Color(0xFF7A8191),
      textOnPrimary: _on(primary),
      success: success,
      successSurface: _tint(success, card, 0.14),
      warning: warning,
      warningSurface: _tint(warning, card, 0.14),
      error: error,
      errorSurface: _tint(error, card, 0.14),
      info: info,
      infoSurface: _tint(info, card, 0.14),
      chartSeries: [
        for (final c in _chartColors(chartPalette, primary))
          identical(c, primary) ? c : readableOn(c, card, min: 3.0),
      ],
      sidebar: const Color(0xFF12151D),
      hover: Colors.white.withValues(alpha: 0.05),
      focusRing: primary,
      skeletonBase: const Color(0xFF1C212C),
      skeletonHighlight: const Color(0xFF272D39),
      scrim: const Color(0x99000000),
      inverseSurface: const Color(0xFFE8EAF0),
      onInverseSurface: card,
      cardShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.28),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ],
      raisedShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.45),
          blurRadius: 28,
          offset: const Offset(0, 10),
        ),
      ],
    );
  }

  static const List<Color> _vivid = [
    Color(0xFF6D28D9),
    Color(0xFF0EA5E9),
    Color(0xFF22C55E),
    Color(0xFFF59E0B),
    Color(0xFFEF4444),
    Color(0xFF14B8A6),
    Color(0xFFEC4899),
    Color(0xFF3B82F6),
    Color(0xFF84CC16),
    Color(0xFFF97316),
  ];

  static const List<Color> _calm = [
    Color(0xFF5B7DB1),
    Color(0xFF6BA292),
    Color(0xFFC9A66B),
    Color(0xFFB77D7D),
    Color(0xFF8C7BB0),
    Color(0xFF6FA3B5),
    Color(0xFFA3B26B),
    Color(0xFFC08A6B),
    Color(0xFF7A8FA6),
    Color(0xFF9C8AA5),
  ];

  /// Ten series colours for a palette style. Brand is today's palette with
  /// the brand colour first; vivid leads with the brand too; calm is muted;
  /// mono steps through shades of the brand colour.
  static List<Color> _chartColors(ChartPaletteStyle style, Color brand) {
    switch (style) {
      case ChartPaletteStyle.brand:
        return [brand, ...AppColors.chartSeries.skip(1)];
      case ChartPaletteStyle.vivid:
        return [brand, ..._vivid.skip(1)];
      case ChartPaletteStyle.calm:
        return _calm;
      case ChartPaletteStyle.mono:
        final hsl = HSLColor.fromColor(brand);
        return [
          for (var i = 0; i < 10; i++)
            hsl
                .withLightness(0.30 + i * 0.05)
                .withSaturation(
                    (hsl.saturation * (1 - i * 0.04)).clamp(0.0, 1.0))
                .toColor(),
        ];
    }
  }

  /// [color], lightened (on a dark [surface]) or darkened (on a light one)
  /// just enough to reach [min] contrast against [surface].
  static Color readableOn(Color color, Color surface, {double min = 4.5}) {
    if (AppTokens.contrastRatio(color, surface) >= min) return color;
    final darkSurface = surface.computeLuminance() < 0.5;
    var hsl = HSLColor.fromColor(color);
    for (var i = 0; i < 50; i++) {
      final l = (hsl.lightness + (darkSurface ? 0.02 : -0.02)).clamp(0.0, 1.0);
      hsl = hsl.withLightness(l);
      final c = hsl.toColor();
      if (AppTokens.contrastRatio(c, surface) >= min || l <= 0 || l >= 1) {
        return c;
      }
    }
    return hsl.toColor();
  }

  static Color _tint(Color color, Color over, double alpha) =>
      Color.alphaBlend(color.withValues(alpha: alpha), over);

  static Color _shift(Color color, double by) {
    final hsl = HSLColor.fromColor(color);
    return hsl.withLightness((hsl.lightness + by).clamp(0.0, 1.0)).toColor();
  }

  static Color _on(Color background) =>
      AppTokens.contrastRatio(Colors.white, background) >=
              AppTokens.contrastRatio(AppTokens.textOnLight, background)
          ? Colors.white
          : AppTokens.textOnLight;
}
