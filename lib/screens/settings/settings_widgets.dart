import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_x.dart';
import '../../widgets/common/app_card.dart';
import '../../widgets/common/responsive.dart';

/// The detail side of Settings: a section's title, what it's for, an optional
/// "Reset to defaults", and its cards.
class SettingsPanel extends StatelessWidget {
  const SettingsPanel({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.onReset,
    this.resetLabel = 'Reset to defaults',
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final VoidCallback? onReset;
  final String resetLabel;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final mobile = Responsive.isMobile(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: mobile ? 20 : 22,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                          color: t.textPrimary)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(subtitle!,
                        style:
                            TextStyle(fontSize: 13.5, color: t.textSecondary)),
                  ],
                ],
              ),
            ),
            if (onReset != null)
              TextButton.icon(
                onPressed: onReset,
                icon: const Icon(Icons.restart_alt, size: 18),
                label: Text(resetLabel),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.lg),
          children[i],
        ],
      ],
    );
  }
}

/// A card inside a panel: an optional heading and description, then content.
class SettingsCard extends StatelessWidget {
  const SettingsCard({
    super.key,
    required this.children,
    this.title,
    this.subtitle,
    this.trailing,
  });

  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title!,
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: t.textPrimary)),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(subtitle!,
                            style: TextStyle(
                                fontSize: 12.5, color: t.textSecondary)),
                      ],
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          ...children,
        ],
      ),
    );
  }
}

/// A labelled switch with a line of explanation.
class SettingSwitch extends StatelessWidget {
  const SettingSwitch({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.leading,
    this.dense = false,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final bool value;

  /// Null makes the switch read-only.
  final ValueChanged<bool>? onChanged;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: dense,
      secondary: leading,
      title: Text(title,
          style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: onChanged == null ? t.textTertiary : t.textPrimary)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!,
              style: TextStyle(fontSize: 12.5, color: t.textSecondary)),
      value: value,
      onChanged: onChanged,
    );
  }
}

/// A short message in a tinted box.
class SettingsNote extends StatelessWidget {
  const SettingsNote(
    this.message, {
    super.key,
    this.tone = SettingsNoteTone.info,
    this.icon,
  });

  final String message;
  final SettingsNoteTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final (surface, color, fallback) = switch (tone) {
      SettingsNoteTone.info => (t.infoSurface, t.info, Icons.info_outline),
      SettingsNoteTone.success => (
          t.successSurface,
          t.success,
          Icons.check_circle_outline
        ),
      SettingsNoteTone.warning => (
          t.warningSurface,
          t.warning,
          Icons.warning_amber_rounded
        ),
      SettingsNoteTone.error => (t.errorSurface, t.error, Icons.error_outline),
    };
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? fallback, size: 18, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(message,
                style: TextStyle(fontSize: 13, color: t.textPrimary)),
          ),
        ],
      ),
    );
  }
}

enum SettingsNoteTone { info, success, warning, error }

/// A labelled row of single-choice chips.
class ChoiceRow<T> extends StatelessWidget {
  const ChoiceRow({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.labelOf,
    required this.onChanged,
    this.helper,
    this.enabled = true,
  });

  final String label;
  final String? helper;
  final T value;
  final List<T> options;
  final String Function(T) labelOf;
  final ValueChanged<T>? onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: t.textSecondary)),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final o in options)
              ChoiceChip(
                label: Text(labelOf(o)),
                selected: o == value,
                onSelected: enabled && onChanged != null
                    ? (_) => onChanged!(o)
                    : null,
              ),
          ],
        ),
        if (helper != null) ...[
          const SizedBox(height: 6),
          Text(helper!, style: TextStyle(fontSize: 11.5, color: t.textTertiary)),
        ],
      ],
    );
  }
}

/// A number with − and + buttons, clamped to [min]..[max].
class NumberStepper extends StatelessWidget {
  const NumberStepper({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.step = 1,
    this.suffix = '',
    this.helper,
    this.decimals = 0,
  });

  final String label;
  final String? helper;
  final num value;
  final num min;
  final num max;
  final num step;
  final String suffix;
  final int decimals;
  final ValueChanged<num> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    num clamp(num v) => v < min ? min : (v > max ? max : v);
    // Round away float drift (2.5 + 0.5 …).
    num next(num v) => num.parse(clamp(v).toStringAsFixed(decimals));
    final text = '${value.toStringAsFixed(decimals)}$suffix';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: t.textSecondary)),
        const SizedBox(height: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton.outlined(
              tooltip: 'Decrease $label',
              visualDensity: VisualDensity.compact,
              onPressed:
                  value > min ? () => onChanged(next(value - step)) : null,
              icon: const Icon(Icons.remove, size: 18),
            ),
            Container(
              constraints: const BoxConstraints(minWidth: 76),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: Semantics(
                label: '$label, $text',
                excludeSemantics: true,
                child: Text(text,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: t.textPrimary,
                        fontFeatures: const [FontFeature.tabularFigures()])),
              ),
            ),
            IconButton.outlined(
              tooltip: 'Increase $label',
              visualDensity: VisualDensity.compact,
              onPressed:
                  value < max ? () => onChanged(next(value + step)) : null,
              icon: const Icon(Icons.add, size: 18),
            ),
          ],
        ),
        if (helper != null) ...[
          const SizedBox(height: 6),
          Text(helper!, style: TextStyle(fontSize: 11.5, color: t.textTertiary)),
        ],
      ],
    );
  }
}

/// Lays [children] out in a wrapping grid of equal columns on wide screens,
/// one per row on narrow ones.
class SettingsGrid extends StatelessWidget {
  const SettingsGrid({super.key, required this.children, this.columns = 2});

  final List<Widget> children;
  final int columns;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth < 520 ? 1 : columns;
      const gap = AppSpacing.xl;
      final width = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: AppSpacing.lg,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    });
  }
}
