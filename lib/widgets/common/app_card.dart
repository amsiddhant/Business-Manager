import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_x.dart';

/// The base surface for dashboards, details and forms: an outlined card with
/// a soft shadow. Tappable cards ([onTap]) lift slightly on hover and show a
/// stronger border, so it's clear they open something.
class AppCard extends StatefulWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.xl),
    this.onTap,
    this.raised = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  /// Always use the deeper shadow (e.g. a card floating over a chart).
  final bool raised;

  @override
  State<AppCard> createState() => _AppCardState();
}

class _AppCardState extends State<AppCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final motion = context.motion;
    final radius = BorderRadius.circular(AppSpacing.radius);
    final interactive = widget.onTap != null;
    final hovered = interactive && _hover;

    Widget content = Padding(padding: widget.padding, child: widget.child);
    if (interactive) {
      content = Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: widget.onTap,
          onHover: (h) {
            if (h != _hover) setState(() => _hover = h);
          },
          borderRadius: radius,
          child: content,
        ),
      );
    }

    return AnimatedContainer(
      duration: motion.fast,
      curve: AppMotion.standard,
      transform: hovered && motion.allowsMovement
          ? Matrix4.translationValues(0, -1.5, 0)
          : Matrix4.identity(),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: radius,
        border: Border.all(color: hovered ? t.borderStrong : t.border),
        boxShadow: widget.raised || hovered ? t.raisedShadow : t.cardShadow,
      ),
      child: content,
    );
  }
}

/// A card with a header row (title + optional trailing action) and body.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.all(AppSpacing.xl),
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    // The header must always keep a readable inset, even when [padding] is
    // zero — full-bleed cards (e.g. data tables) set zero padding so the body
    // spans edge to edge, but the title/subtitle would then sit flush against
    // the card's rounded corner and spill out. Top the header up to a minimum
    // inset so it stays readable regardless of the body padding; when the card
    // is already padded (the default) the top-up is zero and layout is
    // unchanged.
    final resolved = padding.resolve(Directionality.of(context));
    double topUp(double edge) =>
        edge < AppSpacing.xl ? AppSpacing.xl - edge : 0;
    final headerPadding = EdgeInsets.only(
      left: topUp(resolved.left),
      right: topUp(resolved.right),
      top: topUp(resolved.top),
    );

    final header = Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: context.tokens.textPrimary)),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!,
                    style: TextStyle(
                        fontSize: 12.5, color: context.tokens.textSecondary)),
              ],
            ],
          ),
        ),
        ?trailing,
      ],
    );

    return AppCard(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          headerPadding == EdgeInsets.zero
              ? header
              : Padding(padding: headerPadding, child: header),
          const SizedBox(height: AppSpacing.lg),
          child,
        ],
      ),
    );
  }
}
