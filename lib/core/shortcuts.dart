import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../widgets/command_palette/command_palette.dart';
import '../widgets/layout/create_actions.dart';
import '../widgets/layout/shell_nav.dart';
import 'routing/app_routes.dart';
import 'theme/app_theme.dart';
import 'theme/theme_x.dart';

/// `G` then a letter jumps to a section.
final Map<LogicalKeyboardKey, String> kGoShortcuts = {
  LogicalKeyboardKey.keyD: Routes.dashboard,
  LogicalKeyboardKey.keyO: Routes.orders,
  LogicalKeyboardKey.keyC: Routes.customers,
  LogicalKeyboardKey.keyR: Routes.reports,
  LogicalKeyboardKey.keyP: Routes.products,
  LogicalKeyboardKey.keyM: Routes.campaigns,
  LogicalKeyboardKey.keyE: Routes.expenses,
  LogicalKeyboardKey.keyB: Routes.businesses,
  LogicalKeyboardKey.keyU: Routes.users,
  LogicalKeyboardKey.keyS: Routes.settings,
};

bool get _isMac => defaultTargetPlatform == TargetPlatform.macOS;

/// App-wide keyboard shortcuts for the signed-in shell:
///
/// * Ctrl/⌘ K or `/`: command palette
/// * `N`: new record for the current section
/// * `G` then a letter: go to a section ([kGoShortcuts])
/// * `?`: list the shortcuts
///
/// Single-key shortcuts are ignored while typing in a field, and all of them
/// while a dialog or sheet is open.
class AppShortcuts extends StatefulWidget {
  const AppShortcuts({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  State<AppShortcuts> createState() => _AppShortcutsState();
}

class _AppShortcutsState extends State<AppShortcuts> {
  bool _awaitingGo = false;
  Timer? _goTimer;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _goTimer?.cancel();
    super.dispose();
  }

  /// True when focus is in a text field.
  static bool _typing() {
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused == null) return false;
    return focused.widget is EditableText ||
        focused.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || !mounted) return false;
    // A dialog, sheet or the palette itself is on top.
    if (!(ModalRoute.isCurrentOf(context) ?? true)) return false;

    final keys = HardwareKeyboard.instance;
    final key = event.logicalKey;
    final command = _isMac ? keys.isMetaPressed : keys.isControlPressed;

    if (command && key == LogicalKeyboardKey.keyK) {
      CommandPalette.show(context);
      return true;
    }
    if (_typing() || keys.isControlPressed || keys.isMetaPressed ||
        keys.isAltPressed) {
      return false;
    }

    if (_awaitingGo) {
      _awaitingGo = false;
      _goTimer?.cancel();
      final route = kGoShortcuts[key];
      if (route == null) return false;
      final user = context.read<AppState>().currentUser;
      if (Routes.canOpen(user, route)) ShellNav.go(context, route);
      return true;
    }

    if (event.character == '?') {
      showShortcutsHelp(context);
      return true;
    }
    if (key == LogicalKeyboardKey.slash && !keys.isShiftPressed) {
      CommandPalette.show(context);
      return true;
    }
    if (key == LogicalKeyboardKey.keyG && !keys.isShiftPressed) {
      _awaitingGo = true;
      _goTimer?.cancel();
      _goTimer = Timer(const Duration(milliseconds: 1500),
          () => _awaitingGo = false);
      return true;
    }
    if (key == LogicalKeyboardKey.keyN && !keys.isShiftPressed) {
      final user = context.read<AppState>().currentUser;
      final action = createActionForLocation(user, widget.location);
      if (action != null) {
        action.run(context);
      } else {
        CommandPalette.show(context, initialQuery: 'new ');
      }
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The shortcuts list (`?`).
Future<void> showShortcutsHelp(BuildContext context) {
  final mod = _isMac ? '⌘' : 'Ctrl';
  final groups = <(String, List<(String, String)>)>[
    (
      'Anywhere',
      [
        ('$mod K', 'Open the command palette'),
        ('/', 'Search'),
        ('N', 'New record in this section'),
        ('?', 'Show these shortcuts'),
      ],
    ),
    (
      'Go to',
      [
        for (final e in kGoShortcuts.entries)
          ('G ${e.key.keyLabel.toUpperCase()}', _sectionName(e.value)),
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

  return showDialog<void>(
    context: context,
    builder: (context) {
      final t = context.tokens;
      return AlertDialog(
        title: const Text('Keyboard shortcuts'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (title, rows) in groups) ...[
                  Padding(
                    padding: const EdgeInsets.only(
                        top: AppSpacing.md, bottom: AppSpacing.xs),
                    child: Text(
                      title.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.7,
                        color: t.textTertiary,
                      ),
                    ),
                  ),
                  for (final (keys, what) in rows)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(what,
                                style: TextStyle(color: t.textPrimary)),
                          ),
                          KeyHint(keys),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}

String _sectionName(String route) {
  for (final d in kNavDestinations) {
    if (d.route == route) return d.label;
  }
  return route;
}
