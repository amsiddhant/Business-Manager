import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_x.dart';

/// A tile in a [DashboardSection], sized in twelfths of the row. Tablets and
/// phones get their own spans, so a pair of charts side by side on a desktop
/// stacks on narrower screens.
class DashTile {
  const DashTile({
    required this.child,
    this.span = 6,
    int? tablet,
    this.mobile = 12,
  }) : tablet = tablet ?? (span >= 6 ? 12 : 6);

  final Widget child;
  final int span;
  final int tablet;
  final int mobile;
}

/// A titled group of dashboard tiles on a 12-column grid.
class DashboardSection extends StatelessWidget {
  const DashboardSection({
    super.key,
    required this.tiles,
    this.title,
    this.subtitle,
    this.trailing,
  });

  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final List<DashTile> tiles;

  static const desktopMin = 1100.0;
  static const tabletMin = 640.0;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final gap = w < tabletMin ? AppSpacing.md : AppSpacing.lg;
      int spanOf(DashTile tile) =>
          (w >= desktopMin ? tile.span : (w >= tabletMin ? tile.tablet : tile.mobile))
              .clamp(1, 12);
      double widthOf(int span) {
        // Exact for the spans that tile a row evenly (1, 2, 3, 4, 6, 12).
        final perRow = 12 / span;
        return ((w - gap * (perRow - 1)) / perRow).floorToDouble();
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(title!,
                            style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.3,
                                color: t.textPrimary)),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(subtitle!,
                            style: TextStyle(
                                fontSize: 12.5, color: t.textTertiary)),
                      ],
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final tile in tiles)
                SizedBox(width: widthOf(spanOf(tile)), child: tile.child),
            ],
          ),
        ],
      );
    });
  }
}
