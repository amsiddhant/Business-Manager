import 'package:flutter/widgets.dart';

import '../../core/theme/app_theme.dart';

/// Screen-size classification used for responsive layout decisions.
enum ScreenType { mobile, tablet, desktop }

/// Utility helpers for responsive layout.
class Responsive {
  Responsive._();

  static ScreenType of(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width <= AppSpacing.mobileMax) return ScreenType.mobile;
    if (width <= AppSpacing.tabletMax) return ScreenType.tablet;
    return ScreenType.desktop;
  }

  static bool isMobile(BuildContext context) =>
      of(context) == ScreenType.mobile;
  static bool isTablet(BuildContext context) =>
      of(context) == ScreenType.tablet;
  static bool isDesktop(BuildContext context) =>
      of(context) == ScreenType.desktop;

  /// True when the persistent sidebar should be shown inline (desktop) vs a
  /// drawer (tablet/mobile).
  static bool showInlineSidebar(BuildContext context) => isDesktop(context);
}

/// Renders different widgets by screen type. [tablet] falls back to [mobile]
/// when omitted; [desktop] falls back to [tablet]/[mobile].
class ResponsiveBuilder extends StatelessWidget {
  const ResponsiveBuilder({
    super.key,
    required this.mobile,
    this.tablet,
    this.desktop,
  });

  final Widget mobile;
  final Widget? tablet;
  final Widget? desktop;

  @override
  Widget build(BuildContext context) {
    switch (Responsive.of(context)) {
      case ScreenType.desktop:
        return desktop ?? tablet ?? mobile;
      case ScreenType.tablet:
        return tablet ?? mobile;
      case ScreenType.mobile:
        return mobile;
    }
  }
}
