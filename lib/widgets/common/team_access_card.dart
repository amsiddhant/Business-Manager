import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_exception.dart';
import '../../core/enums.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_x.dart';
import '../../models/app_user.dart';
import '../../models/business.dart';
import '../../state/app_state.dart';
import 'app_card.dart';
import 'initials_avatar.dart';
import 'status_badge.dart';

/// The people with access to a record: Owner / Admins / Users, either for
/// one business ([TeamAccessCard.business]) or as a tree per business (a
/// customer tagged to several).
///
/// Enumerating user profiles is Owner-only in the Firestore rules
/// (`allow list: if isOwner()`), so a non-owner's roster query is rejected with
/// permission-denied ("rules are not filters"). For non-owner viewers we
/// therefore show the tagged businesses but gate the roster behind an
/// Owner-only note rather than issuing a query that would fail.
class TeamAccessCard extends StatefulWidget {
  /// A branch per business in [businesses].
  const TeamAccessCard({
    super.key,
    required this.businesses,
    this.subtitle = 'Businesses, owners, admins & users with access',
  }) : _flat = false;

  /// The role groups of one business, without the business level.
  TeamAccessCard.business(
    Business business, {
    super.key,
    this.subtitle = 'Owners, admins & users with access to this business',
  })  : businesses = [business],
        _flat = true;

  /// The businesses to show, already resolved for the viewer's scope.
  final List<Business> businesses;
  final String subtitle;
  final bool _flat;

  @override
  State<TeamAccessCard> createState() => _TeamAccessCardState();
}

class _TeamAccessCardState extends State<TeamAccessCard> {
  Future<List<AppUser>>? _rosterFuture;

  @override
  void initState() {
    super.initState();
    final appState = context.read<AppState>();
    if (appState.currentUser?.isOwner ?? false) {
      _rosterFuture = appState.repository.fetchUsersCached();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final appState = context.watch<AppState>();
    final isOwnerViewer = appState.currentUser?.isOwner ?? false;
    final businesses = widget.businesses;
    final flat = widget._flat;

    return SectionCard(
      title: 'Team Access',
      subtitle: widget.subtitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (businesses.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Text('Not tagged to any accessible business.',
                  style: TextStyle(color: t.textSecondary)),
            )
          else if (!isOwnerViewer)
            flat
                ? const _OwnerOnlyNote()
                : _TeamTree(
                    businesses: businesses, roster: const [], gated: true)
          else
            FutureBuilder<List<AppUser>>(
              future: _rosterFuture,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                }
                if (snap.hasError) {
                  return Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                    child: Text(ErrorMapper.friendly(snap.error!),
                        style: TextStyle(fontSize: 13, color: t.textSecondary)),
                  );
                }
                final roster = snap.data ?? const <AppUser>[];
                if (flat) {
                  return _RoleGroups(
                      business: businesses.single, roster: roster);
                }
                return _TeamTree(
                  businesses: businesses,
                  roster: roster,
                  gated: false,
                );
              },
            ),
        ],
      ),
    );
  }
}

/// The Business → Owner / Admins / Users expansion tree. When [gated] is true
/// (non-owner viewer) the per-business roster is replaced with an Owner-only
/// note, since listing user profiles is not permitted for that caller.
class _TeamTree extends StatelessWidget {
  const _TeamTree({
    required this.businesses,
    required this.roster,
    required this.gated,
  });

  final List<Business> businesses;
  final List<AppUser> roster;
  final bool gated;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final b in businesses)
          _BusinessNode(business: b, roster: roster, gated: gated),
      ],
    );
  }
}

/// A single business branch in the tree with nested Owner / Admins / Users
/// groups.
class _BusinessNode extends StatelessWidget {
  const _BusinessNode({
    required this.business,
    required this.roster,
    required this.gated,
  });

  final Business business;
  final List<AppUser> roster;
  final bool gated;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Theme(
      // Remove the default divider lines ExpansionTile paints when expanded.
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(left: AppSpacing.md),
        leading: Icon(Icons.business_outlined, size: 20, color: t.textTertiary),
        title: Text(business.name,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(business.id,
            style: TextStyle(fontSize: 11, color: t.textTertiary)),
        children: [
          if (gated)
            const Padding(
              padding: EdgeInsets.only(left: AppSpacing.md),
              child: _OwnerOnlyNote(),
            )
          else
            _RoleGroups(business: business, roster: roster),
        ],
      ),
    );
  }
}

/// Owner / Admins / Users of [business]. Owners have access to every
/// business; admins and users only to those assigned to them.
class _RoleGroups extends StatelessWidget {
  const _RoleGroups({required this.business, required this.roster});

  final Business business;
  final List<AppUser> roster;

  @override
  Widget build(BuildContext context) {
    List<AppUser> assigned(UserRole role) => [
          for (final u in roster)
            if (u.role == role && u.assignedBusinessIds.contains(business.id))
              u,
        ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RoleGroup(
          label: 'Owner',
          icon: Icons.shield_outlined,
          people: [
            for (final u in roster)
              if (u.role == UserRole.owner) u,
          ],
        ),
        _RoleGroup(
            label: 'Admins',
            icon: Icons.admin_panel_settings_outlined,
            people: assigned(UserRole.admin)),
        _RoleGroup(
            label: 'Users',
            icon: Icons.person_outline,
            people: assigned(UserRole.user)),
      ],
    );
  }
}

/// Listing user profiles is Owner-only, so other viewers see this instead.
class _OwnerOnlyNote extends StatelessWidget {
  const _OwnerOnlyNote();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Text(
          'The team roster (admins & users) is visible to Owners only.',
          style: TextStyle(fontSize: 12, color: context.tokens.textTertiary),
        ),
      );
}

/// A role sub-group (Owner / Admins / Users) listing its people, itself an
/// expandable node so the tree can be drilled into level by level.
class _RoleGroup extends StatelessWidget {
  const _RoleGroup({
    required this.label,
    required this.icon,
    required this.people,
  });

  final String label;
  final IconData icon;
  final List<AppUser> people;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(left: AppSpacing.lg),
        dense: true,
        leading: Icon(icon, size: 18, color: t.textTertiary),
        title: Text('$label (${people.length})',
            style:
                const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        children: people.isEmpty
            ? [
                Padding(
                  padding: const EdgeInsets.only(
                      left: AppSpacing.lg, bottom: AppSpacing.sm),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('None',
                        style: TextStyle(fontSize: 12, color: t.textTertiary)),
                  ),
                ),
              ]
            : [for (final p in people) _PersonTile(person: p)],
      ),
    );
  }
}

/// A leaf node: one person's avatar, name and email.
class _PersonTile extends StatelessWidget {
  const _PersonTile({required this.person});

  final AppUser person;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          InitialsAvatar(name: person.name, size: 28),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(person.name.isEmpty ? person.loginId : person.name,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500)),
                if (person.email.isNotEmpty)
                  Text(person.email,
                      style: TextStyle(fontSize: 11, color: t.textTertiary)),
              ],
            ),
          ),
          StatusBadge.role(person.role),
        ],
      ),
    );
  }
}
