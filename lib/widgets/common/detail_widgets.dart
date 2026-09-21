import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:universal_html/html.dart' as html;

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import 'confirm_dialog.dart';
import 'responsive.dart';

/// Shared building blocks for entity detail screens (business, campaign, order,
/// expense, dealer, …). Keeps the field row / copy button / link button / URL
/// helpers in one place instead of re-declaring them per screen.

/// Whether [value] can be opened as a real web URL. A fully-qualified URL
/// (has an http/https scheme) or a bare domain (contains a dot, no leading '@')
/// qualifies; handle-style values like "@acme" do not.
bool looksLikeUrl(String value) {
  final v = value.trim();
  if (v.isEmpty) return false;
  if (v.startsWith(RegExp(r'https?://', caseSensitive: false))) return true;
  return !v.startsWith('@') && v.contains('.');
}

/// Opens [url] in a new browser tab, prepending https:// for bare domains.
/// No-ops for values that are not resolvable URLs (see [looksLikeUrl]).
void openExternalUrl(String url) {
  var normalised = url.trim();
  if (!looksLikeUrl(normalised)) return;
  if (!normalised.startsWith(RegExp(r'https?://', caseSensitive: false))) {
    normalised = 'https://$normalised';
  }
  html.window.open(normalised, '_blank');
}

/// A single labelled field on a detail card: icon + label + value, with a copy
/// button and optional link rendering.
class DetailField {
  const DetailField(this.label, this.value, this.icon, {this.isLink = false});
  final String label;
  final String value;
  final IconData icon;

  /// When true the value renders as a link button opening in a new tab.
  final bool isLink;
}

/// A responsive grid of [DetailField]s (1 column on mobile, 2 otherwise).
class DetailGrid extends StatelessWidget {
  const DetailGrid({super.key, required this.fields});

  final List<DetailField> fields;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = Responsive.isMobile(context) ? 1 : 2;
        const gap = AppSpacing.lg;
        final tileWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: AppSpacing.lg,
          children: [
            for (final f in fields)
              SizedBox(width: tileWidth, child: DetailFieldTile(field: f)),
          ],
        );
      },
    );
  }
}

/// One field row: leading icon, label, value (or link), trailing copy button.
class DetailFieldTile extends StatelessWidget {
  const DetailFieldTile({super.key, required this.field});
  final DetailField field;

  @override
  Widget build(BuildContext context) {
    final value = field.value.trim();
    final hasValue = value.isNotEmpty;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(field.icon, size: 18, color: AppColors.textTertiary),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(field.label,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(height: 2),
              if (field.isLink && hasValue && looksLikeUrl(value))
                LinkButton(value: value)
              else
                Text(hasValue ? value : '—',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
        if (hasValue)
          CopyButton(label: field.label.toLowerCase(), value: value),
      ],
    );
  }
}

/// A small icon button that copies [value] to the clipboard and confirms via a
/// snackbar.
class CopyButton extends StatelessWidget {
  const CopyButton({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.copy_outlined, size: 15),
      color: AppColors.textTertiary,
      tooltip: 'Copy $label',
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      padding: EdgeInsets.zero,
      splashRadius: 18,
      onPressed: () async {
        await Clipboard.setData(ClipboardData(text: value));
        if (context.mounted) showSuccessSnack(context, 'Copied $label');
      },
    );
  }
}

/// Renders a value as a link button that opens in a new browser tab.
class LinkButton extends StatelessWidget {
  const LinkButton({super.key, required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => openExternalUrl(value),
        icon: const Icon(Icons.open_in_new, size: 15),
        label: Text(value,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          alignment: Alignment.centerLeft,
        ),
      ),
    );
  }
}

/// The standard two-column detail body: [left] content with a [right] activity
/// column (Last Activity + comments). Stacks on mobile.
class DetailTwoColumn extends StatelessWidget {
  const DetailTwoColumn({super.key, required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    if (Responsive.isMobile(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          left,
          const SizedBox(height: AppSpacing.lg),
          right,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 2, child: left),
        const SizedBox(width: AppSpacing.lg),
        SizedBox(width: 340, child: right),
      ],
    );
  }
}
