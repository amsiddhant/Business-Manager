import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/app_settings.dart' show ChartPaletteStyle, CornerStyle;
import 'app_density.dart';
import 'app_motion.dart';
import 'app_palette.dart';
import 'tokens.dart';

/// Design tokens for spacing and radii, kept in one place for consistency.
class AppSpacing {
  AppSpacing._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  static const double radius = 12;
  static const double radiusSm = 8;
  static const double radiusLg = 16;

  /// Layout breakpoints (width in logical pixels).
  static const double mobileMax = 640;
  static const double tabletMax = 1024;
}

/// The corner radii in effect: the base radii times the organisation's
/// corner style (sharp 0.5, standard 1, rounded 1.5). Read it with
/// `AppShape.of(context)`; outside a themed tree it is the standard shape.
@immutable
class AppShape extends ThemeExtension<AppShape> {
  const AppShape([this.scale = 1]);

  final double scale;

  static const AppShape standard = AppShape();

  static AppShape of(BuildContext context) =>
      Theme.of(context).extension<AppShape>() ?? standard;

  double get radiusSm => AppSpacing.radiusSm * scale;
  double get radius => AppSpacing.radius * scale;
  double get radiusLg => AppSpacing.radiusLg * scale;

  BorderRadius get sm => BorderRadius.circular(radiusSm);
  BorderRadius get md => BorderRadius.circular(radius);
  BorderRadius get lg => BorderRadius.circular(radiusLg);

  @override
  AppShape copyWith({double? scale}) => AppShape(scale ?? this.scale);

  @override
  AppShape lerp(AppShape? other, double t) =>
      other == null ? this : AppShape(scale + (other.scale - scale) * t);
}

/// Builds the app's [ThemeData] from a brand colour, brightness, density and
/// motion level. Every component reads its colours from [AppTokens], so the
/// whole app follows light/dark mode and the admin's brand colour.
class AppTheme {
  AppTheme._();

  static ThemeData get light => build();
  static ThemeData get dark => build(brightness: Brightness.dark);

  static ThemeData build({
    Color brand = AppPalette.defaultBrand,
    Brightness brightness = Brightness.light,
    AppDensity density = AppDensity.comfortable,
    MotionLevel motion = MotionLevel.full,
    CornerStyle corners = CornerStyle.standard,
    ChartPaletteStyle chartPalette = ChartPaletteStyle.brand,
  }) {
    final t = brightness == Brightness.dark
        ? AppPalette.dark(brand: brand, chartPalette: chartPalette)
        : AppPalette.light(brand: brand, chartPalette: chartPalette);
    final shape = AppShape(corners.scale);
    final base = ThemeData(useMaterial3: true, brightness: brightness);
    final textTheme = GoogleFonts.interTextTheme(base.textTheme).apply(
      bodyColor: t.textPrimary,
      displayColor: t.textPrimary,
    );

    final colorScheme = ColorScheme.fromSeed(
      seedColor: brand,
      brightness: brightness,
      primary: t.primary,
      onPrimary: t.textOnPrimary,
      primaryContainer: t.primaryLight,
      onPrimaryContainer: t.isDark ? t.textPrimary : t.primaryDark,
      surface: t.card,
      onSurface: t.textPrimary,
      onSurfaceVariant: t.textSecondary,
      surfaceContainerLowest: t.card,
      surfaceContainerLow: t.card,
      surfaceContainer: t.card,
      surfaceContainerHigh: t.surfaceAlt,
      surfaceContainerHighest: t.surfaceAlt,
      outline: t.borderStrong,
      outlineVariant: t.border,
      error: t.error,
      onError: t.onColor(t.error),
      errorContainer: t.errorSurface,
      onErrorContainer: t.error,
      inverseSurface: t.inverseSurface,
      onInverseSurface: t.onInverseSurface,
      scrim: t.scrim,
    );

    final radiusSm = shape.sm;
    OutlineInputBorder field(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: radiusSm,
          borderSide: BorderSide(color: color, width: width),
        );
    final buttonPadding = EdgeInsets.symmetric(
      horizontal: AppSpacing.lg,
      vertical: density.fieldPadding,
    );
    const buttonText = TextStyle(fontWeight: FontWeight.w600, fontSize: 14);
    final motionTheme = AppMotion(motion);

    return base.copyWith(
      colorScheme: colorScheme,
      extensions: [t, AppDensityTheme(density), motionTheme, shape],
      visualDensity: density.visualDensity,
      scaffoldBackgroundColor: t.background,
      canvasColor: t.background,
      textTheme: textTheme,
      primaryColor: t.primary,
      dividerColor: t.border,
      hoverColor: t.hover,
      focusColor: t.focusRing.withValues(alpha: 0.12),
      splashFactory: motion == MotionLevel.full
          ? InkSparkle.splashFactory
          : NoSplash.splashFactory,
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          for (final p in TargetPlatform.values)
            p: _FadeThroughTransitionsBuilder(motionTheme),
        },
      ),
      dividerTheme: DividerThemeData(color: t.border, thickness: 1, space: 1),
      cardTheme: CardThemeData(
        elevation: 0,
        color: t.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: shape.md,
          side: BorderSide(color: t.border),
        ),
        margin: EdgeInsets.zero,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: t.card,
        foregroundColor: t.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: t.textPrimary),
        titleTextStyle: TextStyle(
          color: t.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      iconTheme: IconThemeData(color: t.textSecondary),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: t.card,
        isDense: true,
        contentPadding: EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: density.fieldPadding,
        ),
        hintStyle: TextStyle(color: t.textTertiary),
        labelStyle: TextStyle(color: t.textSecondary),
        floatingLabelStyle: TextStyle(color: t.primary),
        helperStyle: TextStyle(color: t.textTertiary),
        errorStyle: TextStyle(color: t.error),
        prefixIconColor: t.textTertiary,
        suffixIconColor: t.textTertiary,
        border: field(t.border),
        enabledBorder: field(t.border),
        disabledBorder: field(t.border.withValues(alpha: 0.6)),
        focusedBorder: field(t.primary, 1.6),
        errorBorder: field(t.error),
        focusedErrorBorder: field(t.error, 1.6),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: t.primary,
        selectionColor: t.primary.withValues(alpha: 0.24),
        selectionHandleColor: t.primary,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: t.primary,
          foregroundColor: t.textOnPrimary,
          disabledBackgroundColor: t.surfaceAlt,
          disabledForegroundColor: t.textTertiary,
          elevation: 0,
          padding: buttonPadding,
          textStyle: buttonText,
          shape: RoundedRectangleBorder(borderRadius: radiusSm),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: t.primary,
          foregroundColor: t.textOnPrimary,
          padding: buttonPadding,
          textStyle: buttonText,
          shape: RoundedRectangleBorder(borderRadius: radiusSm),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: t.primary,
          side: BorderSide(color: t.borderStrong),
          padding: buttonPadding,
          textStyle: buttonText,
          shape: RoundedRectangleBorder(borderRadius: radiusSm),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: t.primary,
          textStyle: buttonText,
          shape: RoundedRectangleBorder(borderRadius: radiusSm),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: t.textSecondary,
          shape: RoundedRectangleBorder(borderRadius: radiusSm),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          foregroundColor: t.textSecondary,
          selectedForegroundColor: t.primary,
          selectedBackgroundColor: t.primarySurface,
          side: BorderSide(color: t.border),
          textStyle: buttonText.copyWith(fontSize: 13),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: t.surfaceAlt,
        selectedColor: t.primaryLight,
        side: BorderSide.none,
        labelStyle: TextStyle(
          color: t.textPrimary,
          fontWeight: FontWeight.w500,
          fontSize: 12,
        ),
        secondaryLabelStyle: TextStyle(
          color: t.primary,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
        checkmarkColor: t.primary,
        iconTheme: IconThemeData(color: t.textSecondary, size: 16),
        shape: RoundedRectangleBorder(borderRadius: radiusSm),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: t.card,
        surfaceTintColor: Colors.transparent,
        barrierColor: t.scrim,
        titleTextStyle: TextStyle(
          color: t.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        contentTextStyle: TextStyle(color: t.textSecondary, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: shape.lg),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: t.card,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: t.scrim,
        showDragHandle: true,
        dragHandleColor: t.borderStrong,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(shape.radiusLg),
          ),
        ),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: t.sidebar,
        surfaceTintColor: Colors.transparent,
        scrimColor: t.scrim,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: t.inverseSurface,
        contentTextStyle: TextStyle(color: t.onInverseSurface),
        actionTextColor: t.isDark ? t.primaryDark : t.primaryLight,
        shape: RoundedRectangleBorder(borderRadius: radiusSm),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: t.card,
        surfaceTintColor: Colors.transparent,
        textStyle: TextStyle(color: t.textPrimary, fontSize: 14),
        shape: RoundedRectangleBorder(
          borderRadius: radiusSm,
          side: BorderSide(color: t.border),
        ),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(t.card),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: radiusSm,
              side: BorderSide(color: t.border),
            ),
          ),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: t.inverseSurface,
          borderRadius: radiusSm,
        ),
        textStyle: TextStyle(color: t.onInverseSurface, fontSize: 12),
        waitDuration: const Duration(milliseconds: 400),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: t.textSecondary,
        textColor: t.textPrimary,
        selectedColor: t.primary,
        selectedTileColor: t.primarySurface,
        shape: RoundedRectangleBorder(borderRadius: radiusSm),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: t.sidebar,
        indicatorColor: t.primaryLight,
        selectedIconTheme: IconThemeData(color: t.primary),
        unselectedIconTheme: IconThemeData(color: t.textSecondary),
        selectedLabelTextStyle: TextStyle(
          color: t.primary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelTextStyle: TextStyle(
          color: t.textSecondary,
          fontSize: 12,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: t.card,
        surfaceTintColor: Colors.transparent,
        indicatorColor: t.primaryLight,
        height: 64,
        elevation: 0,
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            color: s.contains(WidgetState.selected)
                ? t.primary
                : t.textSecondary,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => TextStyle(
            fontSize: 12,
            fontWeight: s.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
            color: s.contains(WidgetState.selected)
                ? t.primary
                : t.textSecondary,
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: t.primary,
        foregroundColor: t.textOnPrimary,
        elevation: 2,
        highlightElevation: 4,
        shape: RoundedRectangleBorder(borderRadius: shape.lg),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: t.primary,
        unselectedLabelColor: t.textSecondary,
        indicatorColor: t.primary,
        dividerColor: t.border,
        labelStyle: buttonText,
        unselectedLabelStyle: buttonText.copyWith(fontWeight: FontWeight.w500),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? t.textOnPrimary : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? t.primary : null,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? t.primary : null,
        ),
        checkColor: WidgetStatePropertyAll(t.textOnPrimary),
        side: BorderSide(color: t.borderStrong, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? t.primary : t.borderStrong,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: t.primary,
        linearTrackColor: t.surfaceAlt,
        circularTrackColor: t.surfaceAlt,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(
          t.textTertiary.withValues(alpha: 0.45),
        ),
        radius: const Radius.circular(8),
        thickness: const WidgetStatePropertyAll(6),
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: t.error,
        textColor: t.onColor(t.error),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: t.card,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: t.primary,
        headerForegroundColor: t.textOnPrimary,
        shape: RoundedRectangleBorder(borderRadius: shape.lg),
      ),
      dataTableTheme: DataTableThemeData(
        headingTextStyle: TextStyle(
          color: t.textSecondary,
          fontWeight: FontWeight.w600,
          fontSize: 12.5,
        ),
        dataTextStyle: TextStyle(color: t.textPrimary, fontSize: 13.5),
        headingRowColor: WidgetStatePropertyAll(t.surfaceAlt),
        dividerThickness: 1,
      ),
    );
  }
}

/// A short fade (and, with full motion, a slight scale-up) between pages.
/// Nothing moves under reduced motion, and there's no transition at all when
/// motion is off.
class _FadeThroughTransitionsBuilder extends PageTransitionsBuilder {
  const _FadeThroughTransitionsBuilder(this.motion);

  final AppMotion motion;

  @override
  Duration get transitionDuration => motion.slow;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (!motion.enabled) return child;
    final fadeIn = CurvedAnimation(
      parent: animation,
      curve: const Interval(0.25, 1, curve: AppMotion.emphasized),
    );
    final fadeOut = CurvedAnimation(
      parent: secondaryAnimation,
      curve: const Interval(0, 0.4, curve: Curves.easeIn),
    );
    Widget result = FadeTransition(
      opacity: fadeIn,
      child: FadeTransition(
        opacity: ReverseAnimation(fadeOut),
        child: child,
      ),
    );
    if (motion.allowsMovement) {
      result = ScaleTransition(
        scale: Tween<double>(begin: 0.98, end: 1).animate(fadeIn),
        child: result,
      );
    }
    return result;
  }
}
