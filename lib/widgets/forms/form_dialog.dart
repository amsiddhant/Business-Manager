import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_x.dart';
import '../../models/app_settings.dart';
import '../../state/org_settings.dart';
import '../../state/user_prefs.dart';
import '../common/responsive.dart';
import 'app_form.dart';
import 'form_draft_store.dart';
import 'form_fields.dart';

/// The shell of every create/edit form. Opened with [showAppForm] it's a
/// side panel on wide screens and full screen on phones; opened with
/// `showDialog` it's a centred dialog.
///
/// It runs the save ([onSubmit]: true closes, false stays open), lists the
/// fields that need attention, asks before throwing away unsaved changes,
/// keeps a draft of create forms ([draftKey]) and saves on Ctrl/⌘ + Enter
/// or S.
class FormDialog extends StatefulWidget {
  const FormDialog({
    super.key,
    required this.title,
    required this.child,
    required this.onSubmit,
    this.submitLabel = 'Save',
    this.width = 560,
    this.subtitle,
    this.icon,
    this.draftKey,
  });

  final String title;
  final Widget child;

  /// Performs the save. Returns true to close the dialog, false to keep it open
  /// (e.g. validation failed). Exceptions are surfaced via a snackbar.
  final Future<bool> Function() onSubmit;
  final String submitLabel;
  final double width;
  final String? subtitle;
  final IconData? icon;

  /// Keeps what's typed, so closing by mistake loses nothing. Pass it for
  /// create forms only (e.g. 'order.new').
  final String? draftKey;

  @override
  State<FormDialog> createState() => _FormDialogState();
}

class _FieldError {
  const _FieldError(this.label, this.message, this.element);

  final String label;
  final String? message;
  final Element element;
}

class _Section {
  const _Section(this.key, this.title, this.icon);

  final GlobalKey key;
  final String title;
  final IconData? icon;
}

enum _Leave { stay, discard, keepDraft }

class _FormDialogState extends State<FormDialog> implements FormHooks {
  bool _submitting = false;
  bool _dirty = false;
  bool _leaving = false;
  final _bodyKey = GlobalKey();
  final _scroll = ScrollController();
  final Map<String, TextEditingController> _texts = {};
  final List<_Section> _sections = [];
  bool _sectionsPending = false;
  List<_FieldError> _errors = const [];

  bool _draftsChecked = false;
  FormDraftStore? _drafts;
  FormDraft? _offer;
  Timer? _draftTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_draftsChecked) return;
    _draftsChecked = true;
    final key = widget.draftKey;
    if (key == null) return;
    // No drafts (saving or offering) when the organisation turns them off.
    if (!context.readOrgSettings().features.isOn(AppFeature.drafts)) return;
    try {
      _drafts = FormDraftStore(context.read<UserPrefs>());
    } on ProviderNotFoundException {
      return;
    }
    _offer = _drafts!.load(key);
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  /// setState that's safe to call while the fields are building.
  void _update() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  // ---------------------------------------------------------------- hooks --

  @override
  void markDirty() {
    if (!_dirty) {
      _dirty = true;
      _update();
    }
    if (widget.draftKey == null || _drafts == null) return;
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 800), _saveDraft);
  }

  @override
  void registerText(String key, TextEditingController controller) =>
      _texts[key] = controller;

  @override
  void registerSection(GlobalKey key, String title, IconData? icon) {
    _sections.add(_Section(key, title, icon));
    _sectionsChanged();
  }

  @override
  void unregisterSection(GlobalKey key) {
    _sections.removeWhere((s) => s.key == key);
    _sectionsChanged();
  }

  void _sectionsChanged() {
    if (_sectionsPending) return;
    _sectionsPending = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _sectionsPending = false;
      if (mounted) setState(() {});
    });
  }

  // --------------------------------------------------------------- drafts --

  Future<void> _saveDraft() async {
    final key = widget.draftKey;
    if (key == null || _drafts == null || _leaving) return;
    await _drafts!.save(key, {
      for (final e in _texts.entries) e.key: e.value.text,
    });
  }

  void _restoreDraft() {
    final draft = _offer;
    if (draft == null) return;
    for (final e in draft.fields.entries) {
      _texts[e.key]?.text = e.value;
    }
    setState(() => _offer = null);
    markDirty();
  }

  Future<void> _discardDraft() async {
    setState(() => _offer = null);
    final key = widget.draftKey;
    if (key != null) await _drafts?.clear(key);
  }

  // --------------------------------------------------------------- submit --

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      final shouldClose = await widget.onSubmit();
      if (!mounted) return;
      if (shouldClose) {
        _draftTimer?.cancel();
        _leaving = true;
        final key = widget.draftKey;
        if (key != null) unawaited(_drafts?.clear(key));
        Navigator.of(context).pop(true);
      } else {
        _findErrors();
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Collects the fields showing an error, named by their labels, and
  /// scrolls to the first.
  void _findErrors() {
    final root = _bodyKey.currentContext;
    if (root is! Element) return;
    final found = <_FieldError>[];
    void visit(Element e) {
      if (e is StatefulElement) {
        final state = e.state;
        if (state is FormFieldState && state.hasError) {
          found.add(_FieldError(
            e.findAncestorWidgetOfExactType<LabeledField>()?.label ?? 'A field',
            state.errorText,
            e,
          ));
        }
      }
      e.visitChildren(visit);
    }

    root.visitChildren(visit);
    setState(() => _errors = found);
    if (found.isNotEmpty) _jumpTo(found.first.element);
  }

  void _jumpTo(BuildContext target) {
    if (!target.mounted) return;
    Scrollable.ensureVisible(target,
        duration: context.motion.base, alignment: 0.2);
  }

  // ---------------------------------------------------------------- leave --

  void _close() => Navigator.of(context).maybePop(false);

  Future<void> _confirmLeave() async {
    if (_submitting || _leaving) return;
    final canDraft = widget.draftKey != null && _drafts != null;
    final choice = await showDialog<_Leave>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Discard changes?'),
        content: Text(canDraft
            ? "You haven't saved this yet. Keep a draft to finish it later, "
                'or discard what you typed.'
            : "You haven't saved your changes. If you leave now they'll be "
                'lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, _Leave.discard),
            style: TextButton.styleFrom(foregroundColor: dialog.tokens.error),
            child: const Text('Discard'),
          ),
          if (canDraft)
            TextButton(
              onPressed: () => Navigator.pop(dialog, _Leave.keepDraft),
              child: const Text('Keep draft'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, _Leave.stay),
            child: const Text('Keep editing'),
          ),
        ],
      ),
    );
    if (!mounted || choice == null || choice == _Leave.stay) return;
    _draftTimer?.cancel();
    final key = widget.draftKey;
    if (choice == _Leave.discard) {
      if (key != null) await _drafts?.clear(key);
    } else {
      await _saveDraft();
    }
    if (!mounted) return;
    setState(() => _leaving = true);
    Navigator.of(context).pop(false);
  }

  // ---------------------------------------------------------------- build --

  @override
  Widget build(BuildContext context) {
    final mode = AppFormScope.modeOf(context);
    final expand = mode != AppFormMode.dialog;
    final t = context.tokens;

    final body = Scrollbar(
      controller: _scroll,
      child: SingleChildScrollView(
        controller: _scroll,
        padding: EdgeInsets.all(
            mode == AppFormMode.fullScreen ? AppSpacing.lg : AppSpacing.xl),
        child: KeyedSubtree(
          key: _bodyKey,
          child: FormHooksScope(
            hooks: this,
            child: Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onKeyEvent: (_, e) {
                final typed = e is KeyDownEvent &&
                    (e.character?.isNotEmpty ?? false) &&
                    !HardwareKeyboard.instance.isControlPressed &&
                    !HardwareKeyboard.instance.isMetaPressed;
                if (typed) markDirty();
                return KeyEventResult.ignored;
              },
              child: widget.child,
            ),
          ),
        ),
      ),
    );

    final column = Column(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(context),
        if (_sections.length >= 2) _sectionChips(context),
        if (_offer case final draft?) _draftBanner(context, draft),
        if (_errors.isNotEmpty) _errorBanner(context),
        Divider(height: 1, color: t.border),
        expand ? Expanded(child: body) : Flexible(child: body),
        Divider(height: 1, color: t.border),
        _footer(context, mode),
      ],
    );

    // Ctrl/⌘ + Enter or S saves from anywhere in the form.
    final save = _submitting ? () {} : _submit;
    final content = PopScope<Object?>(
      canPop: !_dirty || _leaving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter, control: true): save,
          const SingleActivator(LogicalKeyboardKey.enter, meta: true): save,
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): save,
          const SingleActivator(LogicalKeyboardKey.keyS, meta: true): save,
        },
        child: column,
      ),
    );

    switch (mode) {
      case AppFormMode.panel:
        return Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: formPanelWidth(context, widget.width),
            height: double.infinity,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: t.card,
                border: Border(left: BorderSide(color: t.border)),
                boxShadow: t.raisedShadow,
              ),
              child: Scaffold(
                backgroundColor: Colors.transparent,
                body: SafeArea(left: false, child: content),
              ),
            ),
          ),
        );
      case AppFormMode.fullScreen:
        return Scaffold(
          backgroundColor: t.card,
          body: SafeArea(child: content),
        );
      case AppFormMode.dialog:
        if (Responsive.isMobile(context)) {
          return Dialog(
            insetPadding: const EdgeInsets.all(AppSpacing.md),
            child: content,
          );
        }
        return Dialog(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: widget.width,
              maxHeight: MediaQuery.sizeOf(context).height * 0.9,
            ),
            child: content,
          ),
        );
    }
  }

  Widget _header(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl, AppSpacing.lg, AppSpacing.md, AppSpacing.lg),
      child: Row(
        children: [
          if (widget.icon != null) ...[
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: t.primarySurface,
                borderRadius: BorderRadius.circular(AppSpacing.radius),
              ),
              child: Icon(widget.icon, size: 20, color: t.primary),
            ),
            const SizedBox(width: AppSpacing.md),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.title,
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: t.textPrimary)),
                if (widget.subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(widget.subtitle!,
                      style:
                          TextStyle(fontSize: 12.5, color: t.textSecondary)),
                ],
              ],
            ),
          ),
          if (_dirty && !_leaving)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration:
                        BoxDecoration(color: t.warning, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Text('Unsaved',
                      style: TextStyle(fontSize: 12, color: t.textSecondary)),
                ],
              ),
            ),
          IconButton(
            tooltip: 'Close',
            onPressed: _submitting ? null : _close,
            icon: Icon(Icons.close, color: t.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _sectionChips(BuildContext context) {
    final t = context.tokens;
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.sm),
        children: [
          for (final s in _sections)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: ActionChip(
                avatar: s.icon == null
                    ? null
                    : Icon(s.icon, size: 16, color: t.primary),
                label: Text(s.title),
                labelStyle: TextStyle(fontSize: 12.5, color: t.textPrimary),
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  final ctx = s.key.currentContext;
                  if (ctx != null) _jumpTo(ctx);
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _draftBanner(BuildContext context, FormDraft draft) {
    final t = context.tokens;
    return _Banner(
      color: t.infoSurface,
      border: t.info,
      icon: Icons.history,
      child: Row(
        children: [
          Expanded(
            child: Text(
                'You have an unsaved draft from ${_ago(draft.savedAt)}.',
                style: TextStyle(fontSize: 13, color: t.textPrimary)),
          ),
          TextButton(onPressed: _discardDraft, child: const Text('Discard')),
          const SizedBox(width: AppSpacing.xs),
          FilledButton.tonal(
              onPressed: _restoreDraft, child: const Text('Restore')),
        ],
      ),
    );
  }

  Widget _errorBanner(BuildContext context) {
    final t = context.tokens;
    final n = _errors.length;
    return _Banner(
      color: t.errorSurface,
      border: t.error,
      icon: Icons.error_outline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(n == 1 ? '1 field needs attention' : '$n fields need attention',
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: t.error)),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: 2,
            children: [
              for (final e in _errors)
                InkWell(
                  onTap: () => _jumpTo(e.element),
                  child: Text(
                    e.message == null ? e.label : '${e.label}: ${e.message}',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: t.textPrimary,
                      decoration: TextDecoration.underline,
                      decorationColor: t.error.withValues(alpha: 0.5),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _footer(BuildContext context, AppFormMode mode) {
    final t = context.tokens;
    final saveButton = FilledButton(
      onPressed: _submitting ? null : _submit,
      child: _submitting
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: t.textOnPrimary),
            )
          : Text(widget.submitLabel),
    );
    final cancel = TextButton(
      onPressed: _submitting ? null : _close,
      child: const Text('Cancel'),
    );
    if (mode == AppFormMode.fullScreen) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Expanded(child: cancel),
            const SizedBox(width: AppSpacing.sm),
            Expanded(flex: 2, child: saveButton),
          ],
        ),
      );
    }
    final mac = defaultTargetPlatform == TargetPlatform.macOS;
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl, vertical: AppSpacing.md),
      child: Row(
        children: [
          if (!Responsive.isMobile(context))
            Expanded(
              child: Text(
                '${mac ? '⌘' : 'Ctrl'} + Enter to save · Esc to close',
                style: TextStyle(fontSize: 12, color: t.textTertiary),
                overflow: TextOverflow.ellipsis,
              ),
            )
          else
            const Spacer(),
          cancel,
          const SizedBox(width: AppSpacing.sm),
          saveButton,
        ],
      ),
    );
  }

  static String _ago(DateTime at) {
    final d = DateTime.now().difference(at);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    return d.inDays == 1 ? 'yesterday' : '${d.inDays} days ago';
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.color,
    required this.border,
    required this.icon,
    required this.child,
  });

  final Color color;
  final Color border;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(
            AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.md),
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          border: Border.all(color: border.withValues(alpha: 0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icon, size: 18, color: border),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: child),
          ],
        ),
      );
}

/// Two fields side-by-side on wide layouts, stacked on mobile.
class FormRow extends StatelessWidget {
  const FormRow(this.children, {super.key});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (Responsive.isMobile(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.lg),
            children[i],
          ],
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.lg),
          Expanded(child: children[i]),
        ],
      ],
    );
  }
}

/// Vertical spacing between form fields.
class FormGap extends StatelessWidget {
  const FormGap({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox(height: AppSpacing.lg);
}
