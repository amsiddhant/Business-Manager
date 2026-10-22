import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/app_exception.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_x.dart';
import '../../core/utils/date_utils.dart';
import '../../state/app_state.dart';
import '../../state/settings_controller.dart';
import '../../widgets/common/confirm_dialog.dart';
import '../../widgets/common/page_header.dart';
import 'settings_draft.dart';
import 'settings_registry.dart';
import 'settings_widgets.dart';

/// Settings: a list of sections (Personal for everyone, Organisation for
/// people who can manage settings, System for the Owner) with the chosen
/// section beside it, or on its own page on a phone.
///
/// Organisation sections edit one shared draft that is kept while you move
/// between sections, and saved in one go from the bar at the bottom.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _wideAt = 900.0;

  final _search = TextEditingController();
  SettingsDraft? _draft;
  bool _dirty = false;
  bool _saving = false;
  String? _saveError;
  String? _selected;
  GoRouter? _router;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final router = GoRouter.maybeOf(context);
    if (!identical(router, _router)) {
      _router?.routeInformationProvider.removeListener(_onRoute);
      _router = router;
      router?.routeInformationProvider.addListener(_onRoute);
      _selected = _sectionFromUrl() ?? _selected;
    }
  }

  @override
  void dispose() {
    _router?.routeInformationProvider.removeListener(_onRoute);
    _draft?.removeListener(_onDraft);
    _draft?.dispose();
    _search.dispose();
    super.dispose();
  }

  String? _sectionFromUrl() =>
      _router?.routeInformationProvider.value.uri.queryParameters['section'];

  void _onRoute() {
    final id = _sectionFromUrl();
    if (!mounted || id == _selected) return;
    setState(() => _selected = id);
  }

  void _onDraft() {
    final dirty = _draft?.isDirty ?? false;
    if (dirty != _dirty && mounted) setState(() => _dirty = dirty);
  }

  void _open(String? id) {
    setState(() => _selected = id);
    _router?.go(id == null ? Routes.settings : '${Routes.settings}?section=$id');
  }

  /// The draft, created the first time an editor needs it and re-seeded
  /// (when nothing is being edited) as the saved settings load.
  SettingsDraft _draftFor(SettingsController ctl) {
    var draft = _draft;
    if (draft == null) {
      draft = SettingsDraft(ctl.editorSeed, logo: ctl.logo);
      draft.addListener(_onDraft);
      _draft = draft;
    } else if (!draft.isDirty && !draft.seed.sameAs(ctl.editorSeed)) {
      final d = draft;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && identical(_draft, d)) {
          d.reseed(ctl.editorSeed, logo: ctl.logo);
        }
      });
    }
    return draft;
  }

  Future<void> _save(SettingsController ctl, bool isOwner) async {
    final draft = _draft;
    if (draft == null || _saving) return;
    if (draft.settings.branding.appName.trim().isEmpty) {
      setState(() => _saveError = 'Give the app a name before saving.');
      _open('branding');
      return;
    }
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await ctl.save(draft.settings,
          logoChanged: draft.logoChanged, logoDataUrl: draft.logo);
      draft.markSaved(ctl.settings, logo: ctl.logo);
      if (mounted) showSuccessSnack(context, 'Settings saved');
    } catch (e) {
      if (mounted) setState(() => _saveError = _explain(e, isOwner));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static String _explain(Object e, bool isOwner) {
    final denied = (e is AppException && e.code == 'permission-denied') ||
        e.toString().contains('permission-denied');
    if (!denied) return ErrorMapper.friendly(e);
    return isOwner ? _deployRules : _rulesGeneric;
  }

  static const _deployRules =
      'Deploy the latest Firestore rules (`firebase deploy --only '
      'firestore:rules`) to save organisation settings.';
  static const _rulesGeneric =
      'Organisation settings can’t be saved right now. Ask the Owner to '
      'check that the latest Firestore rules are deployed.';

  Future<void> _resetAll() async {
    final ok = await showConfirmDialog(
      context,
      title: 'Reset all organisation settings?',
      message: 'Every organisation setting goes back to its default, and the '
          'logo is removed. Nothing changes for anyone until you save.',
      confirmLabel: 'Reset all',
    );
    if (ok) _draft?.resetAll();
  }

  Future<bool> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave without saving?'),
        content: const Text('You have unsaved organisation settings.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep editing')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Discard')),
        ],
      ),
    );
    return discard ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final ctl = context.watch<SettingsController>();
    final user = appState.currentUser;
    final isOwner = user?.isOwner ?? false;
    final canEdit = ctl.canEdit(user);

    final visible = [
      for (final s in kSettingsSections)
        if (switch (s.group) {
          SettingsGroup.personal => true,
          SettingsGroup.organisation => canEdit,
          SettingsGroup.system => isOwner,
        })
          s,
    ];
    final draft = canEdit ? _draftFor(ctl) : null;

    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= _wideAt;
      var current = visible.where((s) => s.id == _selected).firstOrNull;
      if (current == null && wide) current = visible.first;
      final inDetailOnPhone = !wide && current != null;
      final blocked = _dirty && !inDetailOnPhone;

      final list = _SectionList(
        sections: visible,
        query: _search.text,
        searchController: _search,
        selectedId: wide ? current?.id : null,
        showSubtitles: !wide,
        onSelect: (s) => _open(s.id),
        onResetAll: canEdit ? _resetAll : null,
      );

      final detail = current == null
          ? const SizedBox.shrink()
          : _Detail(
              section: current,
              draft: draft ?? SettingsDraft(ctl.editorSeed),
              controller: ctl,
              isOwner: isOwner,
              saveError: _saveError,
              showBack: !wide,
              onBack: () => _open(null),
            );

      final bar = (draft != null && _dirty)
          ? _SaveBar(
              saving: _saving,
              onDiscard: () {
                draft.discard();
                setState(() => _saveError = null);
              },
              onSave: () => _save(ctl, isOwner),
            )
          : null;

      final pad = wide ? AppSpacing.xl : AppSpacing.lg;
      return PopScope(
        canPop: !inDetailOnPhone && !blocked,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          if (inDetailOnPhone) {
            _open(null);
            return;
          }
          if (await _confirmDiscard() && mounted) {
            draft?.discard();
            if (context.mounted) Navigator.of(context).maybePop();
          }
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (wide || current == null)
              Padding(
                padding: EdgeInsets.fromLTRB(pad, pad, pad, AppSpacing.md),
                child: const PageHeader(
                  title: 'Settings',
                  icon: Icons.settings_outlined,
                  subtitle: 'Your preferences and your organisation’s setup',
                ),
              ),
            Expanded(
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(width: 300, child: list),
                        VerticalDivider(
                            width: 1, color: context.tokens.border),
                        Expanded(child: detail),
                      ],
                    )
                  : (current == null ? list : detail),
            ),
            ?bar,
          ],
        ),
      );
    });
  }
}

// ---- Section list -----------------------------------------------------------

class _SectionList extends StatelessWidget {
  const _SectionList({
    required this.sections,
    required this.query,
    required this.searchController,
    required this.selectedId,
    required this.showSubtitles,
    required this.onSelect,
    required this.onResetAll,
  });

  final List<SettingsSectionDef> sections;
  final String query;
  final TextEditingController searchController;
  final String? selectedId;
  final bool showSubtitles;
  final ValueChanged<SettingsSectionDef> onSelect;
  final VoidCallback? onResetAll;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final matches = [for (final s in sections) if (s.matches(query)) s];
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        TextField(
          controller: searchController,
          decoration: InputDecoration(
            hintText: 'Search settings',
            prefixIcon: const Icon(Icons.search, size: 20),
            isDense: true,
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: searchController.clear,
                  ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (matches.isEmpty)
          Text('No settings match “${query.trim()}”.',
              style: TextStyle(fontSize: 13, color: t.textSecondary)),
        for (final group in SettingsGroup.values)
          if (matches.any((s) => s.group == group)) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.sm, AppSpacing.sm, AppSpacing.sm, AppSpacing.xs),
              child: Text(group.label,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                      color: t.textTertiary)),
            ),
            for (final s in matches.where((s) => s.group == group))
              _SectionTile(
                section: s,
                selected: s.id == selectedId,
                showSubtitle: showSubtitles,
                onTap: () => onSelect(s),
              ),
            const SizedBox(height: AppSpacing.md),
          ],
        if (onResetAll != null && query.isEmpty) ...[
          const Divider(),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onResetAll,
              icon: const Icon(Icons.restart_alt, size: 18),
              label: const Text('Reset all organisation settings'),
            ),
          ),
        ],
      ],
    );
  }
}

class _SectionTile extends StatelessWidget {
  const _SectionTile({
    required this.section,
    required this.selected,
    required this.showSubtitle,
    required this.onTap,
  });

  final SettingsSectionDef section;
  final bool selected;
  final bool showSubtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? t.primarySurface : Colors.transparent,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.md),
            child: Row(
              children: [
                Icon(section.icon,
                    size: 20, color: selected ? t.primary : t.textSecondary),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(section.title,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight:
                                  selected ? FontWeight.w600 : FontWeight.w500,
                              color: selected ? t.primary : t.textPrimary)),
                      if (showSubtitle)
                        Text(section.subtitle,
                            style: TextStyle(
                                fontSize: 12.5, color: t.textSecondary)),
                    ],
                  ),
                ),
                if (showSubtitle)
                  Icon(Icons.chevron_right, size: 20, color: t.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---- Detail -----------------------------------------------------------------

class _Detail extends StatelessWidget {
  const _Detail({
    required this.section,
    required this.draft,
    required this.controller,
    required this.isOwner,
    required this.saveError,
    required this.showBack,
    required this.onBack,
  });

  final SettingsSectionDef section;
  final SettingsDraft draft;
  final SettingsController controller;
  final bool isOwner;
  final String? saveError;
  final bool showBack;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final isOrg = section.group == SettingsGroup.organisation;
    final saved = controller.settings;

    Widget body;
    if (isOrg) {
      // Rebuild when the draft changes. Keyed by revision so text fields
      // reload after a reset or discard.
      body = ListenableBuilder(
        listenable: draft,
        builder: (context, _) => KeyedSubtree(
          key: ValueKey('${section.id}-${draft.revision}'),
          child: section.builder(context, draft),
        ),
      );
    } else {
      body = section.builder(context, draft);
    }

    return SingleChildScrollView(
      padding: EdgeInsets.all(showBack ? AppSpacing.lg : AppSpacing.xl),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showBack)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back, size: 18),
                    label: const Text('All settings'),
                  ),
                ),
              if (isOrg) ...[
                if (controller.hasRemote && saved.updatedAt != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: Text(
                      saved.updatedBy.isEmpty
                          ? 'Last changed ${AppDate.format(saved.updatedAt)}'
                          : 'Last changed by ${saved.updatedBy} · '
                              '${AppDate.format(saved.updatedAt)}',
                      style: TextStyle(fontSize: 12.5, color: t.textTertiary),
                    ),
                  ),
                if (controller.rulesMissing)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: SettingsNote(
                      isOwner
                          ? _SettingsScreenState._deployRules
                          : _SettingsScreenState._rulesGeneric,
                      tone: SettingsNoteTone.warning,
                    ),
                  ),
                if (saveError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: SettingsNote(saveError!,
                        tone: SettingsNoteTone.error),
                  ),
              ],
              body,
            ],
          ),
        ),
      ),
    );
  }
}

// ---- Save bar ---------------------------------------------------------------

class _SaveBar extends StatelessWidget {
  const _SaveBar({
    required this.saving,
    required this.onDiscard,
    required this.onSave,
  });

  final bool saving;
  final VoidCallback onDiscard;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Material(
      color: t.card,
      elevation: 6,
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg, vertical: AppSpacing.md),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: t.border)),
          ),
          child: Row(
            children: [
              Icon(Icons.edit_note, color: t.warning, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Unsaved changes',
                  style: TextStyle(
                      fontWeight: FontWeight.w600, color: t.textPrimary),
                ),
              ),
              TextButton(
                onPressed: saving ? null : onDiscard,
                child: const Text('Discard'),
              ),
              const SizedBox(width: AppSpacing.sm),
              ElevatedButton.icon(
                onPressed: saving ? null : onSave,
                icon: saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save_outlined, size: 18),
                label: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
