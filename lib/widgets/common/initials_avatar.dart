import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// An auto-generated "logo" for a named entity: the initials on a deterministic
/// colour derived from the name, so the same customer always gets the same
/// avatar without storing an image.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({
    super.key,
    required this.name,
    this.size = 40,
    this.fontSize,
  });

  final String name;
  final double size;
  final double? fontSize;

  static String initialsOf(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final p = parts.first;
      return (p.length >= 2 ? p.substring(0, 2) : p).toUpperCase();
    }
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  /// A stable colour for [name] chosen from the chart palette.
  static Color colorOf(String name) {
    final palette = AppColors.chartSeries;
    final key = name.trim().toLowerCase();
    // A small, stable string hash (avoids String.hashCode's per-run seed).
    var h = 0;
    for (final unit in key.codeUnits) {
      h = (h * 31 + unit) & 0x7fffffff;
    }
    return palette[h % palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final base = colorOf(name);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Color.alphaBlend(base.withValues(alpha: 0.16), Colors.white),
        shape: BoxShape.circle,
        border: Border.all(color: base.withValues(alpha: 0.35)),
      ),
      child: Text(
        initialsOf(name),
        style: TextStyle(
          color: base,
          fontSize: fontSize ?? size * 0.38,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
