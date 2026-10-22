import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_x.dart';
import '../common/responsive.dart';

/// How a form is being shown.
enum AppFormMode {
  /// A centred dialog (a form opened with `showDialog`).
  dialog,

  /// A panel sliding in from the right, over a scrim (desktop and tablet).
  panel,

  /// The whole screen, sliding up (phones).
  fullScreen,
}

/// Opens a create/edit form — a `FormDialog`, or a widget that builds one —
/// as a side panel on wide screens and full screen on phones. A drop-in for
/// `showDialog`: the form pops `true` once saved, `false` when cancelled.
///
/// Escape, the scrim and the back button all ask the form first, so unsaved
/// changes are never lost by accident.
Future<T?> showAppForm<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  bool useRootNavigator = true,
}) {
  final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
  final mobile = Responsive.isMobile(context);
  return navigator.push<T>(AppFormRoute<T>(
    builder: builder,
    mode: mobile ? AppFormMode.fullScreen : AppFormMode.panel,
    themes: InheritedTheme.capture(from: context, to: navigator.context),
    scrim: context.tokens.scrim,
    motion: context.motion,
    dismissible: barrierDismissible,
    label: MaterialLocalizations.of(context).modalBarrierDismissLabel,
  ));
}

/// The route behind [showAppForm].
class AppFormRoute<T> extends PopupRoute<T> {
  AppFormRoute({
    required this.builder,
    required this.mode,
    required this.themes,
    required this.scrim,
    required this.motion,
    required this.dismissible,
    required this.label,
    super.settings,
  });

  final WidgetBuilder builder;
  final AppFormMode mode;
  final CapturedThemes themes;
  final Color scrim;
  final AppMotion motion;
  final bool dismissible;
  final String label;

  @override
  Color? get barrierColor => mode == AppFormMode.panel ? scrim : null;

  @override
  bool get barrierDismissible => dismissible && mode == AppFormMode.panel;

  @override
  String? get barrierLabel => label;

  @override
  Duration get transitionDuration => motion.allowsMovement
      ? const Duration(milliseconds: 280)
      : motion.base;

  @override
  Duration get reverseTransitionDuration => motion.allowsMovement
      ? const Duration(milliseconds: 200)
      : motion.fast;

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation) {
    // Its own messenger, so a form's snack bars show inside the form rather
    // than under the scrim.
    return themes.wrap(ScaffoldMessenger(
      child: AppFormScope(
        mode: mode,
        child: Builder(builder: builder),
      ),
    ));
  }

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    if (!motion.allowsMovement) {
      return FadeTransition(opacity: animation, child: child);
    }
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return SlideTransition(
      position: Tween<Offset>(
        begin: mode == AppFormMode.panel
            ? const Offset(1, 0)
            : const Offset(0, 0.08),
        end: Offset.zero,
      ).animate(curved),
      child: mode == AppFormMode.panel
          ? child
          : FadeTransition(opacity: curved, child: child),
    );
  }
}

/// Tells a form how it's being shown.
class AppFormScope extends InheritedWidget {
  const AppFormScope({super.key, required this.mode, required super.child});

  final AppFormMode mode;

  static AppFormMode modeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppFormScope>()?.mode ??
      AppFormMode.dialog;

  @override
  bool updateShouldNotify(AppFormScope oldWidget) => mode != oldWidget.mode;
}

/// What the fields of an open form report back to it: that something
/// changed (for the unsaved-changes guard), their text (for drafts) and
/// their sections (for the jump-to chips).
abstract class FormHooks {
  void markDirty();

  /// Remembers [controller]'s text under [key] in the form's draft.
  void registerText(String key, TextEditingController controller);

  void registerSection(GlobalKey key, String title, IconData? icon);
  void unregisterSection(GlobalKey key);
}

/// Puts [FormHooks] in reach of the fields inside a form.
class FormHooksScope extends InheritedWidget {
  const FormHooksScope({super.key, required this.hooks, required super.child});

  final FormHooks hooks;

  /// The open form's hooks, or null outside one. Doesn't rebuild the caller.
  static FormHooks? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<FormHooksScope>()?.hooks;

  @override
  bool updateShouldNotify(FormHooksScope oldWidget) => false;
}

/// The width of a side panel for a form designed [width] wide.
double formPanelWidth(BuildContext context, double width) {
  final screen = MediaQuery.sizeOf(context).width;
  return (width + AppSpacing.xxl * 2)
      .clamp(480.0, 760.0)
      .clamp(0.0, math.max(360.0, screen - AppSpacing.xxl * 2));
}
