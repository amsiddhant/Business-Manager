import 'package:flutter/material.dart';

/// Centralised colour palette for the light SaaS theme.
class AppColors {
  AppColors._();

  // Brand
  static const Color primary = Color(0xFF582DD3);
  static const Color primaryDark = Color(0xFF3F1FA0);
  static const Color primaryLight = Color(0xFFEEE9FB);
  static const Color primarySurface = Color(0xFFF3F0FD);

  // Neutrals / surfaces
  static const Color background = Color(0xFFF7F8FC);
  static const Color card = Color(0xFFFFFFFF);
  static const Color surfaceAlt = Color(0xFFF1F3F9);
  static const Color border = Color(0xFFE6E8F0);
  static const Color borderStrong = Color(0xFFD5D8E4);

  // Text
  static const Color textPrimary = Color(0xFF1F2937);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textTertiary = Color(0xFF9CA3AF);
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  // Semantic
  static const Color success = Color(0xFF16A34A);
  static const Color successSurface = Color(0xFFE7F6EC);
  static const Color warning = Color(0xFFD97706);
  static const Color warningSurface = Color(0xFFFCF3E4);
  static const Color error = Color(0xFFDC2626);
  static const Color errorSurface = Color(0xFFFCEAEA);
  static const Color info = Color(0xFF2563EB);
  static const Color infoSurface = Color(0xFFE8F0FE);

  // Chart series palette
  static const List<Color> chartSeries = [
    Color(0xFF582DD3),
    Color(0xFF2563EB),
    Color(0xFF16A34A),
    Color(0xFFD97706),
    Color(0xFFDC2626),
    Color(0xFF0891B2),
    Color(0xFFDB2777),
    Color(0xFF7C3AED),
    Color(0xFF65A30D),
    Color(0xFF9333EA),
  ];
}
