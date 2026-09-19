import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../common/responsive.dart';
import 'app_header.dart';
import 'app_sidebar.dart';

/// The authenticated application shell: a responsive scaffold combining the
/// [AppSidebar] (inline on desktop, drawer on tablet/mobile), the [AppHeader]
/// and the routed page [child].
class AppShell extends StatelessWidget {
  const AppShell({
    super.key,
    required this.currentRoute,
    required this.child,
  });

  final String currentRoute;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final inlineSidebar = Responsive.showInlineSidebar(context);

    final scaffold = Scaffold(
      backgroundColor: AppColors.background,
      drawer: inlineSidebar
          ? null
          : Drawer(
              backgroundColor: AppColors.card,
              child: Builder(
                builder: (context) => AppSidebar(
                  currentRoute: currentRoute,
                  onNavigate: () => Navigator.of(context).maybePop(),
                ),
              ),
            ),
      body: SafeArea(
        child: Column(
          children: [
            Builder(
              builder: (context) => AppHeader(
                onMenuTap: () => Scaffold.of(context).openDrawer(),
              ),
            ),
            const MobileFilterBar(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1400),
                  child: child,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (inlineSidebar) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Row(
          children: [
            AppSidebar(currentRoute: currentRoute),
            Expanded(child: scaffold),
          ],
        ),
      );
    }
    return scaffold;
  }
}
