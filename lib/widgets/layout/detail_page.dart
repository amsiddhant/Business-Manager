import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_x.dart';
import '../common/initials_avatar.dart';
import '../common/responsive.dart';
import '../common/state_views.dart';
import 'app_page.dart';
import 'kpi_strip.dart';

/// A small fact in a detail page's header ("Business · Acme", "12 Mar 2026").
class DetailMeta {
  const DetailMeta(this.icon, this.text, {this.tooltip, this.onTap});

  final IconData icon;
  final String text;
  final String? tooltip;
  final VoidCallback? onTap;
}

/// An entry in a detail page's "More" menu.
class DetailAction {
  const DetailAction({
    required this.label,
    required this.icon,
    required this.onSelected,
    this.destructive = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onSelected;

  /// Shown in the error colour, below a divider.
  final bool destructive;
}

/// The layout of every record page: a header (back, avatar, title, status,
/// facts and actions), a strip of headline figures, then the record's
/// sections beside its activity (last activity + comments). On phones the
/// sections and the activity are two tabs.
class DetailPage extends StatefulWidget {
  const DetailPage({
    super.key,
    required this.title,
    required this.onBack,
    required this.children,
    this.backLabel = 'Back',
    this.subtitle,
    this.icon,
    this.avatarName,
    this.status,
    this.meta = const [],
    this.primaryAction,
    this.actions = const [],
    this.menu = const [],
    this.kpis = const [],
    this.banner,
    this.activity,
    this.activityLabel = 'Activity',
  })  : _state = _PageState.ready,
        message = null;

  /// The page while the data first loads.
  const DetailPage.loading({
    super.key,
    required this.title,
    required this.onBack,
    this.backLabel = 'Back',
  })  : _state = _PageState.loading,
        children = const [],
        subtitle = null,
        icon = null,
        avatarName = null,
        status = null,
        meta = const [],
        primaryAction = null,
        actions = const [],
        menu = const [],
        kpis = const [],
        banner = null,
        activity = null,
        activityLabel = 'Activity',
        message = null;

  /// The record doesn't exist, or this user can't see it.
  const DetailPage.notFound({
    super.key,
    required this.title,
    required this.onBack,
    this.backLabel = 'Back',
    this.message,
  })  : _state = _PageState.notFound,
        children = const [],
        subtitle = null,
        icon = null,
        avatarName = null,
        status = null,
        meta = const [],
        primaryAction = null,
        actions = const [],
        menu = const [],
        kpis = const [],
        banner = null,
        activity = null,
        activityLabel = 'Activity';

  final _PageState _state;
  final String title;
  final VoidCallback onBack;

  /// Where back goes ("Orders").
  final String backLabel;
  final String? subtitle;

  /// Shown in a tinted tile when there's no [avatarName].
  final IconData? icon;

  /// Shows the initials avatar for this name (customers, dealers…).
  final String? avatarName;
  final Widget? status;
  final List<DetailMeta> meta;

  /// The main button (usually Edit).
  final Widget? primaryAction;
  final List<Widget> actions;
  final List<DetailAction> menu;
  final List<KpiItem> kpis;

  /// A notice above the sections (e.g. "Read-only: managed by its dealer").
  final Widget? banner;

  /// The record's sections, top to bottom.
  final List<Widget> children;

  /// The right-hand column (usually `DetailActivityColumn`).
  final Widget? activity;
  final String activityLabel;

  /// For [DetailPage.notFound].
  final String? message;

  @override
  State<DetailPage> createState() => _DetailPageState();
}

enum _PageState { loading, notFound, ready }

class _DetailPageState extends State<DetailPage> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final mobile = Responsive.isMobile(context);
    switch (w._state) {
      case _PageState.loading:
        return AppPage(children: [
          _BackRow(label: w.backLabel, onBack: w.onBack),
          const SizedBox(height: AppSpacing.md),
          const SkeletonCard(lines: 2, height: 120),
          const SizedBox(height: AppSpacing.lg),
          const SkeletonCard(lines: 5),
        ]);
      case _PageState.notFound:
        return AppPage(children: [
          _BackRow(label: w.backLabel, onBack: w.onBack),
          const SizedBox(height: AppSpacing.xxl),
          EmptyView(
            icon: Icons.search_off,
            title: '${w.title} not found',
            message: w.message ??
                'It may have been removed, or you may not have access to it.',
            action: FilledButton.icon(
              onPressed: w.onBack,
              icon: const Icon(Icons.arrow_back, size: 18),
              label: Text('Back to ${w.backLabel}'),
            ),
          ),
        ]);
      case _PageState.ready:
        break;
    }

    Widget sections() => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (w.banner != null) ...[
              w.banner!,
              const SizedBox(height: AppSpacing.lg),
            ],
            for (var i = 0; i < w.children.length; i++) ...[
              if (i > 0) const SizedBox(height: AppSpacing.lg),
              w.children[i],
            ],
          ],
        );

    final Widget body;
    if (w.activity == null) {
      body = sections();
    } else if (mobile) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<int>(
            segments: [
              const ButtonSegment(
                  value: 0,
                  label: Text('Overview'),
                  icon: Icon(Icons.dashboard_outlined, size: 18)),
              ButtonSegment(
                  value: 1,
                  label: Text(w.activityLabel),
                  icon: const Icon(Icons.forum_outlined, size: 18)),
            ],
            selected: {_tab},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _tab = s.first),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (_tab == 0) sections() else w.activity!,
        ],
      );
    } else {
      body = LayoutBuilder(builder: (context, c) {
        final side = c.maxWidth >= 1200 ? 380.0 : 320.0;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: sections()),
            const SizedBox(width: AppSpacing.lg),
            SizedBox(width: side, child: w.activity),
          ],
        );
      });
    }

    return AppPage(children: [
      _Header(page: w),
      if (w.kpis.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.lg),
        KpiStrip(items: w.kpis),
      ],
      const SizedBox(height: AppSpacing.lg),
      body,
    ]);
  }
}

class _BackRow extends StatelessWidget {
  const _BackRow({required this.label, required this.onBack});

  final String label;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: onBack,
        style: TextButton.styleFrom(
          foregroundColor: t.textSecondary,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          visualDensity: VisualDensity.compact,
        ),
        icon: const Icon(Icons.arrow_back, size: 18),
        label: Text(label),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.page});

  final DetailPage page;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final p = page;
    final mobile = Responsive.isMobile(context);

    final Widget? leading = p.avatarName != null
        ? InitialsAvatar(name: p.avatarName!, size: mobile ? 44 : 56)
        : p.icon == null
            ? null
            : Container(
                width: mobile ? 44 : 56,
                height: mobile ? 44 : 56,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [t.primarySurface, t.primaryLight],
                  ),
                  borderRadius: BorderRadius.circular(AppSpacing.radius),
                  border: Border.all(color: t.primary.withValues(alpha: 0.15)),
                ),
                child: Icon(p.icon, size: mobile ? 22 : 26, color: t.primary),
              );

    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(p.title,
                style: TextStyle(
                    fontSize: mobile ? 20 : 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    color: t.textPrimary)),
            ?p.status,
          ],
        ),
        if (p.subtitle != null) ...[
          const SizedBox(height: 4),
          Text(p.subtitle!,
              style: TextStyle(fontSize: 14, color: t.textSecondary)),
        ],
        if (p.meta.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [for (final m in p.meta) _MetaChip(meta: m)],
          ),
        ],
      ],
    );

    final buttons = <Widget>[
      ...p.actions,
      ?p.primaryAction,
      if (p.menu.isNotEmpty) _MoreMenu(actions: p.menu),
    ];

    final top = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (leading != null) ...[
          leading,
          const SizedBox(width: AppSpacing.lg),
        ],
        Expanded(child: titleBlock),
        if (!mobile && buttons.isNotEmpty) ...[
          const SizedBox(width: AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: buttons,
          ),
        ],
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BackRow(label: p.backLabel, onBack: p.onBack),
        const SizedBox(height: AppSpacing.sm),
        Container(
          padding: EdgeInsets.all(mobile ? AppSpacing.lg : AppSpacing.xl),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            border: Border.all(color: t.border),
            boxShadow: t.cardShadow,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              stops: const [0, 0.45],
              colors: [t.primarySurface, t.card],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              top,
              if (mobile && buttons.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: buttons,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.meta});

  final DetailMeta meta;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final link = meta.onTap != null;
    Widget chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: t.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(meta.icon, size: 14, color: link ? t.primary : t.textTertiary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(meta.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: link ? FontWeight.w600 : FontWeight.w500,
                    color: link ? t.primary : t.textSecondary)),
          ),
        ],
      ),
    );
    if (link) {
      chip = Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: meta.onTap,
          child: chip,
        ),
      );
    }
    if (meta.tooltip != null) {
      chip = Tooltip(message: meta.tooltip!, child: chip);
    }
    return chip;
  }
}

class _MoreMenu extends StatelessWidget {
  const _MoreMenu({required this.actions});

  final List<DetailAction> actions;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final safe = [for (final a in actions) if (!a.destructive) a];
    final danger = [for (final a in actions) if (a.destructive) a];
    Widget item(DetailAction a) => MenuItemButton(
          leadingIcon: Icon(a.icon,
              size: 18, color: a.destructive ? t.error : t.textSecondary),
          onPressed: a.onSelected,
          child: Text(a.label,
              style: TextStyle(color: a.destructive ? t.error : null)),
        );
    return MenuAnchor(
      alignmentOffset: const Offset(0, 4),
      menuChildren: [
        for (final a in safe) item(a),
        if (safe.isNotEmpty && danger.isNotEmpty) const Divider(height: 8),
        for (final a in danger) item(a),
      ],
      builder: (context, menu, _) => OutlinedButton.icon(
        onPressed: () => menu.isOpen ? menu.close() : menu.open(),
        icon: const Icon(Icons.more_horiz, size: 18),
        label: const Text('More'),
      ),
    );
  }
}
