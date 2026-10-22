import 'package:flutter/material.dart';

import '../../../core/theme/theme_x.dart';
import '../../../services/profit_calculation_service.dart';

/// The change against the comparison period: ▲ 12.4% / ▼ 2.1 pts, green for
/// good news and red for bad (costs going up are bad news). [onBrand] is for
/// the hero band's coloured background.
class DeltaChip extends StatelessWidget {
  const DeltaChip({
    super.key,
    required this.delta,
    required this.versus,
    this.onBrand = false,
  });

  final MetricDelta delta;

  /// "vs previous period", shown in the tooltip.
  final String versus;
  final bool onBrand;

  static String describe(MetricDelta d) {
    final c = d.change;
    if (c == null) return 'No comparison';
    if (c.abs() < 0.05) return d.metric.isPercent ? '0.0 pts' : '0.0%';
    final mag = c.abs() >= 1000 ? '999+' : c.abs().toStringAsFixed(1);
    return d.metric.isPercent ? '$mag pts' : '$mag%';
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final c = delta.change;
    final good = delta.favourable;
    final up = c != null && c >= 0.05;
    final down = c != null && c <= -0.05;
    final Color fg;
    final Color bg;
    fg = good == null ? t.textSecondary : (good ? t.success : t.error);
    if (onBrand) {
      // A solid card-coloured pill reads on any brand colour.
      bg = t.card.withValues(alpha: 0.94);
    } else {
      bg = good == null
          ? t.surfaceAlt
          : (good ? t.successSurface : t.errorSurface);
    }
    final label = describe(delta);
    final icon = up
        ? Icons.arrow_upward_rounded
        : down
            ? Icons.arrow_downward_rounded
            : Icons.remove_rounded;
    return Tooltip(
      message: c == null
          ? 'Nothing to compare with $versus'
          : '${up ? 'Up' : down ? 'Down' : 'No change'} $label $versus',
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 3, 8, 3),
        decoration: ShapeDecoration(color: bg, shape: const StadiumBorder()),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (c != null) ...[
              Icon(icon, size: 13, color: fg),
              const SizedBox(width: 2),
            ],
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: fg,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  )),
            ),
          ],
        ),
      ),
    );
  }
}
