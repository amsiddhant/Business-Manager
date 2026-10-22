import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../widgets/charts/chart_kit.dart';

/// A tiny trend line with a soft fill and a dot on the latest value. Draws
/// in from the left the first time [id] is shown.
class Sparkline extends StatelessWidget {
  const Sparkline({
    super.key,
    required this.id,
    required this.values,
    required this.color,
    this.strokeWidth = 2,
    this.fill = true,
    this.dotColor,
  });

  final String id;
  final List<double> values;
  final Color color;
  final double strokeWidth;
  final bool fill;

  /// The latest-value dot's ring (the surface behind the line).
  final Color? dotColor;

  @override
  Widget build(BuildContext context) {
    if (values.length < 2 || values.every((v) => v == 0)) {
      return const SizedBox.expand();
    }
    return ExcludeSemantics(
      child: ChartReveal(
        id: 'spark-$id',
        builder: (context, k) => CustomPaint(
          size: Size.infinite,
          painter: _SparkPainter(
              values: values,
              color: color,
              strokeWidth: strokeWidth,
              fill: fill,
              dotColor: dotColor,
              progress: k),
        ),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter({
    required this.values,
    required this.color,
    required this.strokeWidth,
    required this.fill,
    required this.dotColor,
    required this.progress,
  });

  final List<double> values;
  final Color color;
  final double strokeWidth;
  final bool fill;
  final Color? dotColor;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final lo = values.reduce(math.min), hi = values.reduce(math.max);
    final span = hi - lo == 0 ? 1 : hi - lo;
    final pad = strokeWidth + 3;
    final h = size.height - pad * 2;
    final w = size.width - pad * 2;
    final pts = [
      for (var i = 0; i < values.length; i++)
        Offset(pad + w * i / (values.length - 1),
            pad + h - (values[i] - lo) / span * h),
    ];

    final line = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      final p0 = pts[i - 1], p1 = pts[i];
      final mx = (p0.dx + p1.dx) / 2;
      line.cubicTo(mx, p0.dy, mx, p1.dy, p1.dx, p1.dy);
    }

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width * progress, size.height));
    if (fill) {
      final area = Path.from(line)
        ..lineTo(pts.last.dx, size.height)
        ..lineTo(pts.first.dx, size.height)
        ..close();
      canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0)],
          ).createShader(Offset.zero & size),
      );
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();

    if (progress >= 1) {
      final last = pts.last;
      if (dotColor != null) {
        canvas.drawCircle(last, strokeWidth + 2.5, Paint()..color = dotColor!);
      }
      canvas.drawCircle(last, strokeWidth + 1, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_SparkPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.dotColor != dotColor ||
      !_same(old.values, values);

  static bool _same(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
