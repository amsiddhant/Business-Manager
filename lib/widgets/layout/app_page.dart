import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// The scrolling body of a routed page.
///
/// [children] are laid out top to bottom like a stretched `Column`, but built
/// lazily: a chart or table below the fold isn't built or laid out until it's
/// about to scroll into view. Once built, a section is kept alive, so a table's
/// sort, page and search survive scrolling away and back.
///
/// Content is at most [maxWidth] wide and centred on very wide screens.
class AppPage extends StatelessWidget {
  const AppPage({super.key, required this.children, this.maxWidth = 1400})
      : slivers = null;

  /// For pages that build their own slivers (e.g. a virtualised grid).
  const AppPage.slivers({
    super.key,
    required List<Widget> this.slivers,
    this.maxWidth = 1400,
  }) : children = const [];

  final List<Widget> children;
  final List<Widget>? slivers;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = math.max(
            AppSpacing.lg, (constraints.maxWidth - maxWidth) / 2);
        final slivers = this.slivers;
        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: EdgeInsets.symmetric(
                  horizontal: side, vertical: AppSpacing.lg),
              sliver: slivers != null
                  ? SliverMainAxisGroup(slivers: slivers)
                  : SliverList.list(
                      children: [
                        for (final child in children)
                          _KeepAlive(key: child.key, child: child),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _KeepAlive extends StatefulWidget {
  const _KeepAlive({super.key, required this.child});
  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
