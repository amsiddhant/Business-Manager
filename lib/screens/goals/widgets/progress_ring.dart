import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/theme_x.dart';

/// A ring that fills to [percent] (capped at a full circle). It sweeps from
/// its old value to the new one when the motion setting allows movement, and
/// just shows the value otherwise.
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.percent,
    required this.color,
    this.size = 88,
    this.strokeWidth = 9,
    this.semanticsLabel,
    this.child,
  });

  final double percent;
  final Color color;
  final double size;
  final double strokeWidth;
  final String? semanticsLabel;

  /// Shown in the middle (e.g. the percent).
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final motion = context.motion;
    final end = (percent.isFinite ? percent / 100 : 0.0).clamp(0.0, 1.0);
    return Semantics(
      label: semanticsLabel ?? '${percent.round()} percent',
      child: ExcludeSemantics(
        child: SizedBox(
          width: size,
          height: size,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: motion.allowsMovement ? 0.0 : end, end: end),
            duration: motion.chart,
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => CustomPaint(
              painter: _RingPainter(
                progress: value,
                color: color,
                track: t.border,
                strokeWidth: strokeWidth,
              ),
              child: Center(child: child),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.color,
    required this.track,
    required this.strokeWidth,
  });

  final double progress;
  final Color color;
  final Color track;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(strokeWidth / 2, strokeWidth / 2,
        size.width - strokeWidth, size.height - strokeWidth);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = track;
    canvas.drawArc(rect, 0, math.pi * 2, false, base);
    if (progress <= 0) return;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * progress, false, arc);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.track != track ||
      old.strokeWidth != strokeWidth;
}
