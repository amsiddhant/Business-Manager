import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_x.dart';
import 'responsive.dart';

/// A page title block with an optional icon, record count, subtitle and
/// trailing actions. Wraps gracefully on narrow screens.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.count,
    this.icon,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  /// How many records the page lists, shown as a pill by the title.
  final int? count;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final t = context.tokens;
    final heading = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(title,
              style: TextStyle(
                  fontSize: isMobile ? 20 : 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3)),
        ),
        if (count != null) ...[
          const SizedBox(width: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
            decoration: BoxDecoration(
              color: t.primarySurface,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text('$count',
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: t.primary,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ),
        ],
      ],
    );
    Widget titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        heading,
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle!,
              style: TextStyle(color: t.textSecondary, fontSize: 13.5)),
        ],
      ],
    );
    if (icon != null) {
      titleBlock = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: isMobile ? 36 : 44,
            height: isMobile ? 36 : 44,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [t.primarySurface, t.primaryLight],
              ),
              borderRadius: BorderRadius.circular(AppSpacing.radius),
            ),
            child: Icon(icon, size: isMobile ? 18 : 22, color: t.primary),
          ),
          const SizedBox(width: AppSpacing.md),
          Flexible(child: titleBlock),
        ],
      );
    }

    if (actions.isEmpty) return titleBlock;

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          titleBlock,
          const SizedBox(height: AppSpacing.md),
          Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: actions),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: titleBlock),
        Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: actions),
      ],
    );
  }
}
