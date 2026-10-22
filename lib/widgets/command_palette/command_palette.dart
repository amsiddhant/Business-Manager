import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_x.dart';
import '../../models/app_user.dart';
import '../../services/search_index.dart';
import '../../state/app_state.dart';
import '../../state/data_controller.dart';
import '../../state/user_prefs.dart';
import '../common/responsive.dart';
import '../layout/shell_nav.dart';
import 'command_registry.dart';

/// "Ctrl K" / "⌘K", for hints.
String get paletteShortcutLabel =>
    defaultTargetPlatform == TargetPlatform.macOS ? '⌘K' : 'Ctrl K';

/// The command palette: jump to any page or record, create things and run
/// actions from the keyboard. Full-screen on mobile.
class CommandPalette extends StatefulWidget {
  const CommandPalette._({
    required this.registry,
    required this.user,
    required this.initialQuery,
  });

  final CommandRegistry registry;
  final AppUser user;
  final String initialQuery;

  /// Opens the palette over the shell. [context] must be inside the shell.
  static Future<void> show(BuildContext context, {String initialQuery = ''}) {
    final user = context.read<AppState>().currentUser;
    if (user == null) return Future.value();
    final registry = CommandRegistry(context, nav: ShellNav.maybeOf(context));
    final mobile = Responsive.isMobile(context);
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close command palette',
      barrierColor: context.tokens.scrim,
      transitionDuration: context.motion.fast,
      pageBuilder: (_, _, _) {
        final palette = CommandPalette._(
          registry: registry,
          user: user,
          initialQuery: initialQuery,
        );
        if (mobile) return Dialog.fullscreen(child: palette);
        return Align(
          alignment: const Alignment(0, -0.55),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640, maxHeight: 540),
            child: Material(
              type: MaterialType.card,
              elevation: 12,
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              clipBehavior: Clip.antiAlias,
              child: palette,
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: context.motion.allowsMovement
            ? ScaleTransition(
                scale: Tween(begin: 0.98, end: 1.0).animate(animation),
                child: child,
              )
            : child,
      ),
    );
  }

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  late final TextEditingController _query =
      TextEditingController(text: widget.initialQuery);
  final _scroll = ScrollController();
  final _keys = <int, GlobalKey>{};
  int _selected = 0;
  List<PaletteCommand> _items = const [];

  @override
  void initState() {
    super.initState();
    _query.addListener(_onQuery);
  }

  @override
  void dispose() {
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onQuery() => setState(() => _selected = 0);

  List<PaletteCommand> _compute() {
    final r = widget.registry;
    final user = widget.user;
    final data = context.read<DataController>();
    final index = SearchIndex.of(data);
    final q = _query.text.trim().toLowerCase();

    if (q.isEmpty) {
      final recent = r
          .recent(user, context.read<UserPrefs>().recentCommands, index)
          .take(5)
          .toList();
      final shown = {for (final c in recent) c.id};
      return [
        ...recent,
        ...r.navigate(user).where((c) => !shown.contains(c.id)),
        ...r.create(user).where((c) => !shown.contains(c.id)),
      ];
    }

    List<PaletteCommand> best(List<PaletteCommand> list, int max) {
      final scored = [
        for (final c in list)
          if (c.score(q) case final s when s > 0) (s, c),
      ]..sort((a, b) => b.$1.compareTo(a.$1));
      return [for (final (_, c) in scored.take(max)) c];
    }

    return [
      ...best(r.navigate(user), 6),
      ...best(r.create(user), 4),
      for (final hit in index.search(q, limit: 12)) r.record(hit),
      ...best(r.actions(), 6),
    ];
  }

  void _move(int delta) {
    if (_items.isEmpty) return;
    setState(() => _selected = (_selected + delta) % _items.length);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _keys[_selected]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx,
            duration: context.motion.fast,
            alignmentPolicy: delta > 0
                ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
                : ScrollPositionAlignmentPolicy.keepVisibleAtStart);
      }
    });
  }

  void _run(PaletteCommand c) {
    final shellContext = widget.registry.context;
    // Remember it (the "Recent" copy shares the original's id).
    shellContext.read<UserPrefs>().pushRecentCommand(c.id);
    Navigator.of(context).pop();
    if (shellContext.mounted) c.run(shellContext);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    _items = _compute();
    if (_selected >= _items.length) _selected = 0;

    final rows = <Widget>[];
    CommandSection? last;
    for (var i = 0; i < _items.length; i++) {
      final c = _items[i];
      if (c.section != last) {
        last = c.section;
        rows.add(_SectionHeader(c.section.label));
      }
      final key = _keys.putIfAbsent(i, GlobalKey.new);
      rows.add(_CommandRow(
        key: key,
        command: c,
        selected: i == _selected,
        onHover: () {
          if (_selected != i) setState(() => _selected = i);
        },
        onTap: () => _run(c),
      ));
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(1),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-1),
        const SingleActivator(LogicalKeyboardKey.enter): () {
          if (_items.isNotEmpty) _run(_items[_selected]);
        },
        const SingleActivator(LogicalKeyboardKey.numpadEnter): () {
          if (_items.isNotEmpty) _run(_items[_selected]);
        },
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.sm, AppSpacing.sm, AppSpacing.sm),
            child: Row(
              children: [
                Icon(Icons.search, color: t.textTertiary),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Semantics(
                    label: 'Search pages, records and actions',
                    child: TextField(
                      controller: _query,
                      autofocus: true,
                      textInputAction: TextInputAction.go,
                      style: const TextStyle(fontSize: 16),
                      decoration: const InputDecoration(
                        hintText: 'Search or jump to…',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        isDense: true,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close, color: t.textSecondary),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: t.border),
          Flexible(
            child: _items.isEmpty
                ? _Empty(query: _query.text.trim())
                : ListView(
                    controller: _scroll,
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.sm, horizontal: AppSpacing.sm),
                    children: rows,
                  ),
          ),
          Divider(height: 1, color: t.border),
          const _Footer(),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xs),
        child: Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.7,
            color: context.tokens.textTertiary,
          ),
        ),
      );
}

class _CommandRow extends StatelessWidget {
  const _CommandRow({
    super.key,
    required this.command,
    required this.selected,
    required this.onHover,
    required this.onTap,
  });

  final PaletteCommand command;
  final bool selected;
  final VoidCallback onHover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final c = command;
    return MouseRegion(
      onHover: (_) => onHover(),
      child: Material(
        color: selected ? t.primaryLight : t.card.withValues(alpha: 0),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: 10),
            child: Row(
              children: [
                Icon(c.icon,
                    size: 20, color: selected ? t.primary : t.textSecondary),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: t.textPrimary,
                        ),
                      ),
                      if (c.subtitle case final s?)
                        Text(
                          s,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              TextStyle(fontSize: 12, color: t.textSecondary),
                        ),
                    ],
                  ),
                ),
                if (c.hint case final h?) ...[
                  const SizedBox(width: AppSpacing.sm),
                  KeyHint(h),
                ],
                if (selected) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Icon(Icons.keyboard_return, size: 16, color: t.textTertiary),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A small key-cap style label, e.g. `G O` or `Ctrl K`.
class KeyHint extends StatelessWidget {
  const KeyHint(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: t.surfaceAlt,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: t.textSecondary,
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 32, color: context.tokens.textTertiary),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Nothing matches “$query”.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.tokens.textSecondary),
            ),
          ],
        ),
      );
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: 12, color: context.tokens.textTertiary);
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      child: Wrap(
        spacing: AppSpacing.lg,
        runSpacing: AppSpacing.xs,
        children: [
          for (final (key, what) in const [
            ('↑ ↓', 'move'),
            ('Enter', 'open'),
            ('Esc', 'close'),
          ])
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                KeyHint(key),
                const SizedBox(width: 6),
                Text(what, style: style),
              ],
            ),
        ],
      ),
    );
  }
}
