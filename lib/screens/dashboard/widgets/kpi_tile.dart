import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_x.dart';
import '../../../services/profit_calculation_service.dart';
import '../../../widgets/common/app_card.dart';
import 'animated_number.dart';
import 'delta_chip.dart';
import 'hero_palette.dart';
import 'sparkline.dart';

/// What a KPI tile shows. The tiles themselves only lay it out.
class KpiData {
  const KpiData({
    required this.id,
    required this.label,
    required this.value,
    required this.format,
    required this.icon,
    required this.tooltip,
    required this.delta,
    required this.trend,
    this.caption,
    this.accent,
    this.negative = false,
    this.onTap,
  });

  final String id;
  final String label;
  final double value;
  final String Function(double) format;
  final IconData icon;

  /// How the figure is worked out.
  final String tooltip;
  final MetricDelta delta;

  /// The trailing 12 months, oldest first.
  final List<double> trend;
  final String? caption;
  final Color? accent;

  /// Shows the value in the error colour (a loss).
  final bool negative;
  final VoidCallback? onTap;
}

/// A headline figure on the hero band: translucent over the brand gradient,
/// with a count-up value, the change and a 12-month sparkline.
class HeroKpiTile extends StatefulWidget {
  const HeroKpiTile({super.key, required this.data, required this.versus});

  final KpiData data;
  final String versus;

  @override
  State<HeroKpiTile> createState() => _HeroKpiTileState();
}

class _HeroKpiTileState extends State<HeroKpiTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final motion = context.motion;
    final d = widget.data;
    final on = HeroPalette.of(t).foreground;
    final radius = BorderRadius.circular(AppSpacing.radiusLg);

    final body = Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: on.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(d.icon, size: 16, color: on),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(d.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: on.withValues(alpha: 0.88))),
              ),
              Tooltip(
                message: d.tooltip,
                child: Icon(Icons.info_outline,
                    size: 16, color: on.withValues(alpha: 0.6)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: AnimatedNumber(
              value: d.value,
              format: d.format,
              countUpId: 'hero-${d.id}',
              style: TextStyle(
                fontSize: 26,
                height: 1.1,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.6,
                color: on,
              ),
            ),
          ),
          const SizedBox(height: 8),
          LayoutBuilder(builder: (context, c) {
            final chip = Flexible(
              child: DeltaChip(
                  delta: d.delta, versus: widget.versus, onBrand: true),
            );
            final caption = Text(d.caption ?? widget.versus,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11.5, color: on.withValues(alpha: 0.72)));
            // Two to a row on a phone: the caption gets its own line.
            if (c.maxWidth < 180) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [chip]),
                  const SizedBox(height: 4),
                  caption,
                ],
              );
            }
            return Row(
              children: [
                chip,
                const SizedBox(width: 8),
                Expanded(child: caption),
              ],
            );
          }),
          const SizedBox(height: 10),
          SizedBox(
            height: 34,
            child: Sparkline(id: 'hero-${d.id}', values: d.trend, color: on),
          ),
        ],
      ),
    );

    return Semantics(
      button: d.onTap != null,
      label: '${d.label} ${d.format(d.value)}, '
          '${DeltaChip.describe(d.delta)} ${widget.versus}',
      child: AnimatedContainer(
        duration: motion.fast,
        curve: AppMotion.standard,
        transform: _hover && motion.allowsMovement
            ? Matrix4.translationValues(0, -2, 0)
            : Matrix4.identity(),
        decoration: BoxDecoration(
          color: on.withValues(alpha: _hover ? 0.16 : 0.10),
          borderRadius: radius,
          border: Border.all(color: on.withValues(alpha: _hover ? 0.32 : 0.18)),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: radius,
            onTap: d.onTap,
            onHover: (h) {
              if (h != _hover) setState(() => _hover = h);
            },
            child: body,
          ),
        ),
      ),
    );
  }
}

/// A secondary figure: a compact card with the change and a sparkline.
class KpiTile extends StatelessWidget {
  const KpiTile({super.key, required this.data, required this.versus});

  final KpiData data;
  final String versus;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final d = data;
    final accent = d.accent ?? t.primary;
    return Semantics(
      button: d.onTap != null,
      label: '${d.label} ${d.format(d.value)}, '
          '${DeltaChip.describe(d.delta)} $versus',
      child: AppCard(
        onTap: d.onTap,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        child: LayoutBuilder(builder: (context, c) {
          // Narrow tiles (two to a row on a phone) drop the sparkline so the
          // figure keeps its size.
          final showSpark = c.maxWidth >= 200;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Icon(d.icon, size: 15, color: accent),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(d.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: t.textSecondary)),
                  ),
                  Tooltip(
                    message: d.tooltip,
                    child:
                        Icon(Icons.info_outline, size: 15, color: t.textTertiary),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: AnimatedNumber(
                            value: d.value,
                            format: d.format,
                            countUpId: 'kpi-${d.id}',
                            style: TextStyle(
                              fontSize: 20,
                              height: 1.15,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.4,
                              color: d.negative ? t.error : t.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            DeltaChip(delta: d.delta, versus: versus),
                            if (d.caption != null)
                              Text(d.caption!,
                                  style: TextStyle(
                                      fontSize: 11.5,
                                      color: d.negative
                                          ? t.error
                                          : t.textTertiary)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (showSpark) ...[
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 72,
                      height: 36,
                      child: Sparkline(
                          id: 'kpi-${d.id}',
                          values: d.trend,
                          color: accent,
                          strokeWidth: 1.6,
                          dotColor: t.card),
                    ),
                  ],
                ],
              ),
            ],
          );
        }),
      ),
    );
  }
}
