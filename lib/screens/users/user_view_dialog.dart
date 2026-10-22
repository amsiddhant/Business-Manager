import 'package:flutter/material.dart';

import '../../core/permissions.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_x.dart';
import '../../core/utils/date_utils.dart';
import '../../models/app_user.dart';
import '../../models/business.dart';
import '../../widgets/common/detail_widgets.dart';
import '../../widgets/common/initials_avatar.dart';
import '../../widgets/common/status_badge.dart';

/// What the owner chose to do from the read-only view dialog.
enum UserViewAction { edit, resetPassword }

/// Read-only detail dialog for a user. Rendered only on the owner-only Users
/// screen, so the viewer always sees the full profile — identity, role/status,
/// assigned businesses, effective permissions (role defaults ± overrides) and
/// the audit trail — with a copy button on every value. Pure presentation: it
/// pops a [UserViewAction] (or null) rather than doing any persistence itself.
class UserViewDialog extends StatelessWidget {
  const UserViewDialog({
    super.key,
    required this.user,
    required this.businesses,
  });

  final AppUser user;
  final List<Business> businesses;

  /// Human-readable business names for the assigned ids, falling back to the
  /// raw id for any business the roster no longer contains.
  static List<String> accessNames(AppUser user, List<Business> businesses) =>
      [
        for (final id in user.assignedBusinessIds)
          businesses.where((b) => b.id == id).map((b) => b.name).firstOrNull ??
              id,
      ];

  /// Turns a `Permission` enum name into a human label, e.g.
  /// `deleteProduct` → "Delete product".
  static String permissionLabel(Permission p) {
    // Split camelCase into words, lowercase, then capitalise the first letter.
    final words = p.name
        .replaceAllMapped(RegExp(r'(?<=[a-z])(?=[A-Z])'), (_) => ' ')
        .toLowerCase();
    if (words.isEmpty) return words;
    return '${words[0].toUpperCase()}${words.substring(1)}';
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final name = user.name.trim().isEmpty ? 'Unnamed user' : user.name;
    final access = accessNames(user, businesses);

    // Effective capabilities = role defaults + granted − revoked.
    final effective = Permissions.resolve(
      user.role,
      granted: user.grantedPermissions,
      revoked: user.revokedPermissions,
    );
    final sortedPerms = effective.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    final revoked = user.revokedPermissions.toList()
      ..sort((a, b) => a.index.compareTo(b.index));

    final profileFields = <DetailField>[
      DetailField('Name', user.name, Icons.person_outline),
      DetailField('Login ID', user.loginId, Icons.badge_outlined),
      DetailField('Email', user.email, Icons.mail_outline),
      DetailField('User ID', user.uid, Icons.tag),
      DetailField('Role', user.role.label, Icons.shield_outlined),
      DetailField(
          'Account status', user.status.label, Icons.toggle_on_outlined),
      DetailField('Last login', AppDate.format(user.lastLoginAt), Icons.login),
    ];

    final auditFields = <DetailField>[
      DetailField(
          'Created', AppDate.format(user.audit.createdAt), Icons.schedule),
      DetailField(
          'Created by', user.audit.createdBy ?? '', Icons.person_add_alt),
      DetailField(
          'Updated', AppDate.format(user.audit.updatedAt), Icons.update),
      DetailField('Updated by', user.audit.updatedBy ?? '',
          Icons.manage_accounts_outlined),
    ];

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header: avatar + name + role/status badges + close.
        Container(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl, AppSpacing.lg, AppSpacing.md, AppSpacing.lg),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [t.primarySurface, t.card],
            ),
          ),
          child: Row(
            children: [
              InitialsAvatar(name: name, size: 56),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(name,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                    Text(user.email,
                        style:
                            TextStyle(fontSize: 13, color: t.textSecondary)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      children: [
                        StatusBadge.role(user.role),
                        StatusBadge.account(user.status),
                      ],
                    ),
                  ],
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
        // Body: profile, businesses, permissions and audit.
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SectionLabel('Profile'),
                const SizedBox(height: AppSpacing.md),
                DetailGrid(fields: profileFields),
                const SizedBox(height: AppSpacing.xl),
                _SectionLabel(
                    'Assigned businesses${user.isOwner ? '' : ' (${access.length})'}'),
                const SizedBox(height: AppSpacing.sm),
                if (user.isOwner)
                  const _PermissionChip(label: 'All businesses')
                else if (access.isEmpty)
                  Text('None',
                      style:
                          TextStyle(fontSize: 13, color: t.textTertiary))
                else
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      for (final n in access) _PermissionChip(label: n),
                    ],
                  ),
                const SizedBox(height: AppSpacing.xl),
                _SectionLabel('Effective permissions (${sortedPerms.length})'),
                const SizedBox(height: AppSpacing.sm),
                if (sortedPerms.isEmpty)
                  Text('No permissions.',
                      style: TextStyle(fontSize: 13, color: t.textTertiary))
                else
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      for (final p in sortedPerms)
                        _PermissionChip(
                          label: permissionLabel(p),
                          isOverride: user.grantedPermissions.contains(p),
                        ),
                    ],
                  ),
                if (revoked.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  _SectionLabel(
                      'Revoked from role default (${revoked.length})'),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      for (final p in revoked)
                        _PermissionChip(
                            label: permissionLabel(p), isRevoked: true),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
                const _SectionLabel('Audit'),
                const SizedBox(height: AppSpacing.md),
                DetailGrid(fields: auditFields),
              ],
            ),
          ),
        ),
        // The owner account is not editable from this screen; every other
        // account offers a jump straight into the edit form.
        if (!user.isOwner) ...[
          Divider(height: 1, color: t.border),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                OutlinedButton.icon(
                  onPressed: () =>
                      Navigator.of(context).pop(UserViewAction.resetPassword),
                  icon: const Icon(Icons.lock_reset, size: 18),
                  label: const Text('Send password reset'),
                ),
                FilledButton.icon(
                  onPressed: () =>
                      Navigator.of(context).pop(UserViewAction.edit),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Edit'),
                ),
              ],
            ),
          ),
        ],
      ],
    );

    return Dialog(
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.all(AppSpacing.lg),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 600,
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: content,
      ),
    );
  }
}

/// Small uppercase section heading used inside [UserViewDialog].
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
        color: context.tokens.textSecondary,
      ),
    );
  }
}

/// A read-only pill. [isOverride] flags a capability granted on top of the
/// role default; [isRevoked] flags one removed from it.
class _PermissionChip extends StatelessWidget {
  const _PermissionChip({
    required this.label,
    this.isOverride = false,
    this.isRevoked = false,
  });

  final String label;
  final bool isOverride;
  final bool isRevoked;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final Color bg;
    final Color fg;
    if (isRevoked) {
      bg = t.errorSurface;
      fg = t.error;
    } else if (isOverride) {
      bg = t.primarySurface;
      fg = t.primary;
    } else {
      bg = t.surfaceAlt;
      fg = t.textSecondary;
    }
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isOverride)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Icon(Icons.add, size: 13),
            ),
          if (isRevoked)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Icon(Icons.remove, size: 13),
            ),
          Flexible(
            child: Text(label,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
          ),
        ],
      ),
    );
  }
}
