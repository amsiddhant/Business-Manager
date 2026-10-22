import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_x.dart';
import '../../../core/utils/date_utils.dart';
import 'hero_palette.dart';
import 'kpi_tile.dart';

/// The top of the dashboard: a brand-gradient band with the greeting, what's
/// selected, the comparison switch, Sync, and the four headline KPIs.
class DashboardHero extends StatelessWidget {
  const DashboardHero({
    super.key,
    required this.name,
    required this.scope,
    required this.basis,
    required this.onBasis,
    required this.onSync,
    required this.syncing,
    required this.kpis,
    required this.versus,
    this.projection,
    this.now,
  });

  /// The user's name; the greeting uses the first word.
  final String? name;

  /// "All Businesses · This Financial Year · 1 Apr 2026 – 31 Mar 2027".
  final String scope;
  final ComparisonBasis basis;
  final ValueChanged<ComparisonBasis> onBasis;
  final VoidCallback onSync;
  final ValueListenable<bool> syncing;
  final List<KpiData> kpis;
  final String versus;

  /// "On pace for ₹4.2L revenue by 31 Mar" while the period is running.
  final String? projection;
  final DateTime? now;

  static String greeting(DateTime now) => now.hour < 12
      ? 'Good morning'
      : now.hour < 17
          ? 'Good afternoon'
          : 'Good evening';

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final palette = HeroPalette.of(t);
    final fg = palette.foreground;
    final first = name?.trim().split(RegExp(r'\s+')).first ?? '';
    final hello =
        '${greeting(now ?? DateTime.now())}${first.isEmpty ? '' : ', $first'}';

    return LayoutBuilder(builder: (context, c) {
      final narrow = c.maxWidth < 720;
      final pad = narrow ? AppSpacing.lg : AppSpacing.xl;

      final heading = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('DASHBOARD',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.6,
                  color: fg.withValues(alpha: 0.7))),
          const SizedBox(height: 6),
          Semantics(
            header: true,
            child: Text(hello,
                style: TextStyle(
                  fontSize: narrow ? 22 : 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.6,
                  height: 1.15,
                  color: fg,
                )),
          ),
          const SizedBox(height: 6),
          Text(scope,
              style: TextStyle(fontSize: 13, color: fg.withValues(alpha: 0.78))),
        ],
      );

      final actions = Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _BasisToggle(
              basis: basis, onChanged: onBasis, fg: fg, compact: narrow),
          ValueListenableBuilder<bool>(
            valueListenable: syncing,
            builder: (context, busy, _) => _GlassButton(
              fg: fg,
              onPressed: busy ? null : onSync,
              icon: busy
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: fg),
                    )
                  : Icon(Icons.sync, size: 16, color: fg),
              label: busy ? 'Syncing…' : 'Sync now',
            ),
          ),
        ],
      );

      final columns = c.maxWidth >= 960 ? 4 : 2;
      const gap = AppSpacing.md;
      final tileWidth = (c.maxWidth - pad * 2 - gap * (columns - 1)) / columns;

      return ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: palette.gradient,
            ),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(
                      painter: _Backdrop(glows: palette.glows, dots: fg)),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(pad),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (narrow) ...[
                      heading,
                      const SizedBox(height: AppSpacing.md),
                      actions,
                    ] else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: heading),
                          const SizedBox(width: AppSpacing.lg),
                          actions,
                        ],
                      ),
                    if (projection != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: ShapeDecoration(
                            color: fg.withValues(alpha: 0.12),
                            shape: StadiumBorder(
                                side: BorderSide(
                                    color: fg.withValues(alpha: 0.2))),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.auto_graph, size: 15, color: fg),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(projection!,
                                    style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w500,
                                        color: fg)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    SizedBox(height: narrow ? AppSpacing.lg : AppSpacing.xl),
                    Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: [
                        for (final k in kpis)
                          SizedBox(
                            width: tileWidth,
                            child: HeroKpiTile(data: k, versus: versus),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}

/// "vs previous period | vs last year" on the band.
class _BasisToggle extends StatelessWidget {
  const _BasisToggle({
    required this.basis,
    required this.onChanged,
    required this.fg,
    this.compact = false,
  });

  final ComparisonBasis basis;
  final ValueChanged<ComparisonBasis> onChanged;
  final Color fg;

  /// "Previous | Last year", for phones.
  final bool compact;

  String _label(ComparisonBasis b) => b == ComparisonBasis.previousPeriod
      ? (compact ? 'Previous' : 'vs previous')
      : (compact ? 'Last year' : 'vs last year');

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: ShapeDecoration(
        color: fg.withValues(alpha: 0.12),
        shape: StadiumBorder(side: BorderSide(color: fg.withValues(alpha: 0.2))),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final b in ComparisonBasis.values)
            Flexible(
              child: Semantics(
                button: true,
                selected: b == basis,
                label: 'Compare with ${b.label.toLowerCase()}',
                excludeSemantics: true,
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: b == basis ? null : () => onChanged(b),
                  child: AnimatedContainer(
                    duration: context.motion.fast,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: ShapeDecoration(
                      color: b == basis ? t.card : t.card.withValues(alpha: 0),
                      shape: const StadiumBorder(),
                    ),
                    child: Text(
                      _label(b),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: b == basis ? t.primary : fg,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _GlassButton extends StatelessWidget {
  const _GlassButton({
    required this.fg,
    required this.onPressed,
    required this.icon,
    required this.label,
  });

  final Color fg;
  final VoidCallback? onPressed;
  final Widget icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: fg.withValues(alpha: 0.12),
      shape: StadiumBorder(side: BorderSide(color: fg.withValues(alpha: 0.24))),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              icon,
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Two soft colour glows and a fading dot grid — painted once, never
/// animated.
class _Backdrop extends CustomPainter {
  const _Backdrop({required this.glows, required this.dots});
  final List<Color> glows;
  final Color dots;

  @override
  void paint(Canvas canvas, Size size) {
    void glow(Offset centre, double radius, Color color) {
      canvas.drawCircle(
        centre,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: centre, radius: radius)),
      );
    }

    final r = math.max(size.width, size.height);
    glow(Offset(size.width * 0.92, size.height * 0.05), r * 0.45, glows[0]);
    glow(Offset(size.width * 0.12, size.height * 1.05), r * 0.38, glows[1]);

    // Dots over the right half, fading out towards the middle.
    const step = 18.0;
    final paint = Paint();
    for (var x = size.width * 0.5; x < size.width; x += step) {
      final fade = (x - size.width * 0.5) / (size.width * 0.5);
      paint.color = dots.withValues(alpha: 0.08 * fade);
      for (var y = step / 2; y < size.height; y += step) {
        canvas.drawCircle(Offset(x, y), 1, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_Backdrop old) =>
      old.dots != dots || !listEquals(old.glows, glows);
}
