import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/app_routes.dart';

/// Lets anything inside the shell switch sections the way the sidebar does:
/// back to where you left that section, or to its list if you're already in
/// it. Provided by `AppShell`.
class ShellNav extends InheritedWidget {
  const ShellNav({
    super.key,
    required this.location,
    required this.goSection,
    required super.child,
  });

  /// The current location (path + query).
  final String location;

  /// Switches to the section [route] (a section root such as `/orders`).
  final void Function(String route) goSection;

  static ShellNav? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellNav>();

  /// Opens [route]: section roots switch shell branch (keeping that section's
  /// place); anything else is a plain `go`. Works outside the shell too.
  static void go(BuildContext context, String route) {
    final nav = context.getInheritedWidgetOfExactType<ShellNav>();
    navigate(nav, GoRouter.of(context), route);
  }

  /// [go] with the shell and router captured up front — for dialogs and
  /// sheets, which sit above the shell.
  static void navigate(ShellNav? nav, GoRouter router, String route) {
    if (nav != null && Routes.sectionOf(route) == route) {
      nav.goSection(route);
    } else {
      router.go(route);
    }
  }

  @override
  bool updateShouldNotify(ShellNav oldWidget) =>
      oldWidget.location != location;
}
