import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_x.dart';

/// One figure on a [KpiStrip].
class KpiItem {
  const KpiItem({
    required this.label,
    required this.value,
    this.icon,
    this.tone,
    this.caption,
    this.tooltip,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData? icon;

  /// Colours the value (e.g. success for a profit, error for a loss).
  final Color? tone;

  /// A short line under the value ("of ₹2.4L budget").
  final String? caption;

  /// How the figure is worked out.
  final String? tooltip;
  final VoidCallback? onTap;
}

/// A row of headline figures for a list or detail page. Tiles share the
/// width evenly and wrap onto more rows when narrow (two to a row on phones).
class KpiStrip extends StatelessWidget {
  const KpiStrip({
    super.key,
    required this.items,
    this.minTileWidth = 168,
    this.maxColumns = 6,
  });

  final List<KpiItem> items;
  final double minTileWidth;
  final int maxColumns;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, c) {
      const gap = AppSpacing.md;
      var columns = ((c.maxWidth + gap) / (minTileWidth + gap)).floor();
      columns = columns.clamp(2, maxColumns).clamp(1, items.length);
      // Even rows: 5 tiles on a 4-wide screen read better as 3 + 2.
      final rows = (items.length / columns).ceil();
      columns = (items.length / rows).ceil();
      final width = (c.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final item in items)
            SizedBox(width: width, child: _KpiTile(item: item)),
        ],
      );
    });
  }
}

class _KpiTile extends StatefulWidget {
  const _KpiTile({required this.item});

  final KpiItem item;

  @override
  State<_KpiTile> createState() => _KpiTileState();
}

class _KpiTileState extends State<_KpiTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final motion = context.motion;
    final item = widget.item;
    final accent = item.tone ?? t.primary;
    final radius = BorderRadius.circular(AppSpacing.radius);

    final tile = AnimatedContainer(
      duration: motion.fast,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: radius,
        border: Border.all(color: _hover ? t.borderStrong : t.border),
        boxShadow: _hover ? t.raisedShadow : t.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (item.icon != null) ...[
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(item.icon, size: 14, color: accent),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              Expanded(
                child: Text(item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: t.textSecondary)),
              ),
              if (item.tooltip != null)
                Tooltip(
                  message: item.tooltip!,
                  child: Icon(Icons.info_outline,
                      size: 14, color: t.textTertiary),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: AnimatedSwitcher(
              duration: motion.base,
              child: Text(
                item.value,
                key: ValueKey(item.value),
                maxLines: 1,
                style: TextStyle(
                  fontSize: 19,
                  height: 1.15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                  color: item.tone ?? t.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          if (item.caption != null) ...[
            const SizedBox(height: 4),
            Text(item.caption!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: t.textTertiary)),
          ],
        ],
      ),
    );

    return Semantics(
      button: item.onTap != null,
      label: '${item.label}: ${item.value}',
      excludeSemantics: item.onTap == null,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        cursor: item.onTap == null
            ? MouseCursor.defer
            : SystemMouseCursors.click,
        child: item.onTap == null
            ? tile
            : Material(
                type: MaterialType.transparency,
                child: InkWell(
                  borderRadius: radius,
                  onTap: item.onTap,
                  child: tile,
                ),
              ),
      ),
    );
  }
}
