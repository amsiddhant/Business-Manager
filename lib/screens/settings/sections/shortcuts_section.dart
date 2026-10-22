import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/routing/nav_registry.dart';
import '../../../core/shortcuts.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_x.dart';
import '../settings_widgets.dart';

/// The keyboard shortcuts, for reference.
class ShortcutsSection extends StatelessWidget {
  const ShortcutsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final mod = defaultTargetPlatform == TargetPlatform.macOS ? '⌘' : 'Ctrl';
    final groups = <(String, List<(String, String)>)>[
      (
        'Anywhere',
        [
          ('$mod K', 'Open the command palette'),
          ('/', 'Search'),
          ('N', 'New record in this section'),
          ('?', 'Show the shortcuts'),
        ],
      ),
      (
        'Go to',
        [
          for (final e in kGoShortcuts.entries)
            (
              'G then ${e.key.keyLabel.toUpperCase()}',
              NavRegistry.destinationFor(e.value)?.label ?? e.value,
            ),
        ],
      ),
      (
        'In forms',
        [
          ('$mod Enter', 'Save'),
          ('$mod S', 'Save'),
          ('Esc', 'Close'),
        ],
      ),
    ];
    return SettingsPanel(
      title: 'Shortcuts',
      subtitle: 'Single keys work when you are not typing in a field',
      children: [
        for (final (title, rows) in groups)
          SettingsCard(
            title: title,
            children: [
              for (final (keys, what) in rows) _ShortcutRow(keys, what),
            ],
          ),
      ],
    );
  }
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow(this.keys, this.what);
  final String keys;
  final String what;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(what, style: TextStyle(color: t.textPrimary))),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
            decoration: BoxDecoration(
              color: t.surfaceAlt,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: t.border),
            ),
            child: Text(keys,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: t.textSecondary)),
          ),
        ],
      ),
    );
  }
}
