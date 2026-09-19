import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/enums.dart';
import '../../core/permissions.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_utils.dart';
import '../../core/validators.dart';
import '../../data/repository.dart';
import '../../models/app_user.dart';
import '../../models/business.dart';
import '../../state/app_state.dart';
import '../../state/data_controller.dart';
import '../../widgets/common/confirm_dialog.dart';
import '../../widgets/common/data_table_card.dart';
import '../../widgets/common/page_header.dart';
import '../../widgets/common/state_views.dart';
import '../../widgets/common/status_badge.dart';
import '../../widgets/forms/form_dialog.dart';
import '../../widgets/forms/form_fields.dart';

/// Owner-only user management: create Admin/User accounts, edit profiles,
/// assign businesses, tune per-user permission overrides and enable/disable
/// accounts. Users are fetched directly (they are not part of the cached
/// working set).
class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  late Future<List<AppUser>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<AppUser>> _load() =>
      context.read<AppState>().repository.fetchUsers();

  // Use a block body: `setState(() => _future = _load())` would *return* the
  // assigned Future from the closure, which setState rejects at runtime.
  void _reload() => setState(() {
        _future = _load();
      });

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final data = context.watch<DataController>();
    final user = appState.currentUser;
    final canManage = user?.can(Permission.manageUsers) ?? false;

    if (!canManage) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(title: 'Users'),
          SizedBox(height: 48),
          EmptyView(
            title: 'Restricted',
            message: 'Only the owner can manage users.',
            icon: Icons.lock_outline,
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: 'Users',
          subtitle: 'Manage team members, roles and access',
          actions: [
            ElevatedButton.icon(
              onPressed: () => _openForm(null, data.selectableBusinesses),
              icon: const Icon(Icons.person_add_alt, size: 18),
              label: const Text('Add User'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        FutureBuilder<List<AppUser>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.only(top: 32),
                child: LoadingView(),
              );
            }
            if (snapshot.hasError) {
              return Padding(
                padding: const EdgeInsets.only(top: 32),
                child: ErrorView(
                  message: snapshot.error.toString(),
                  onRetry: _reload,
                ),
              );
            }
            final users = snapshot.data ?? const <AppUser>[];
            return _UsersTable(
              users: users,
              currentUid: user?.uid,
              businesses: data.businesses,
              onEdit: (u) => _openForm(u, data.selectableBusinesses),
              onToggleStatus: _toggleStatus,
              onResetPassword: _resetPassword,
            );
          },
        ),
      ],
    );
  }

  Future<void> _openForm(AppUser? existing, List<Business> businesses) async {
    final repo = context.read<AppState>().repository;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _UserFormDialog(
        existing: existing,
        repo: repo,
        businesses: businesses,
      ),
    );
    if (saved == true) {
      _reload();
      if (mounted) {
        showSuccessSnack(
            context,
            existing == null
                ? 'User created successfully'
                : 'User updated successfully');
      }
    }
  }

  Future<void> _toggleStatus(AppUser u) async {
    final repo = context.read<AppState>().repository;
    final disabling = u.isActive;
    final ok = await showConfirmDialog(
      context,
      title: disabling ? 'Disable user?' : 'Enable user?',
      message: disabling
          ? 'Disable "${u.name}"? They will be signed out and blocked from '
              'logging in until re-enabled.'
          : 'Re-enable "${u.name}" so they can log in again?',
      confirmLabel: disabling ? 'Disable' : 'Enable',
      destructive: disabling,
    );
    if (ok != true) return;
    try {
      await repo.setUserStatus(
          u.uid, disabling ? AccountStatus.disabled : AccountStatus.active);
      _reload();
      if (mounted) {
        showSuccessSnack(context, disabling ? 'User disabled' : 'User enabled');
      }
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  Future<void> _resetPassword(AppUser u) async {
    final appState = context.read<AppState>();
    final ok = await showConfirmDialog(
      context,
      title: 'Send password reset?',
      message: 'Send a password reset email to ${u.email}?',
      confirmLabel: 'Send',
      destructive: false,
    );
    if (ok != true) return;
    try {
      await appState.sendPasswordReset(u.email);
      if (mounted) showSuccessSnack(context, 'Password reset email sent');
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }
}

class _UsersTable extends StatelessWidget {
  const _UsersTable({
    required this.users,
    required this.currentUid,
    required this.businesses,
    required this.onEdit,
    required this.onToggleStatus,
    required this.onResetPassword,
  });

  final List<AppUser> users;
  final String? currentUid;
  final List<Business> businesses;
  final ValueChanged<AppUser> onEdit;
  final ValueChanged<AppUser> onToggleStatus;
  final ValueChanged<AppUser> onResetPassword;

  String _accessLabel(AppUser u) {
    if (u.isOwner) return 'All businesses';
    if (u.assignedBusinessIds.isEmpty) return 'None';
    return u.assignedBusinessIds
        .map((id) =>
            businesses.where((b) => b.id == id).map((b) => b.name).firstOrNull ??
            id)
        .join(', ');
  }

  @override
  Widget build(BuildContext context) {
    return AppDataTable<AppUser>(
      rows: users,
      searchableText: (u) => '${u.name} ${u.email} ${u.loginId}',
      emptyTitle: 'No users found',
      columns: [
        AppColumn(
          label: 'Name',
          cell: (u) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(u.name,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(u.email,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
          sortValue: (u) => u.name.toLowerCase(),
        ),
        AppColumn(
          label: 'Login ID',
          cell: (u) => Text(u.loginId),
          sortValue: (u) => u.loginId.toLowerCase(),
        ),
        AppColumn(
          label: 'Role',
          cell: (u) => StatusBadge.role(u.role),
          sortValue: (u) => u.role.label,
        ),
        AppColumn(
          label: 'Access',
          cell: (u) => ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(_accessLabel(u),
                maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
          sortValue: (u) => _accessLabel(u),
        ),
        AppColumn(
          label: 'Last Login',
          cell: (u) => Text(AppDate.format(u.lastLoginAt)),
          sortValue: (u) => u.lastLoginAt?.millisecondsSinceEpoch ?? 0,
        ),
        AppColumn(
          label: 'Status',
          cell: (u) => StatusBadge.account(u.status),
          sortValue: (u) => u.status.label,
        ),
        AppColumn(
          label: '',
          cell: (u) => _RowActions(
            user: u,
            isSelf: u.uid == currentUid,
            onEdit: () => onEdit(u),
            onToggleStatus: () => onToggleStatus(u),
            onResetPassword: () => onResetPassword(u),
          ),
        ),
      ],
    );
  }
}

class _RowActions extends StatelessWidget {
  const _RowActions({
    required this.user,
    required this.isSelf,
    required this.onEdit,
    required this.onToggleStatus,
    required this.onResetPassword,
  });

  final AppUser user;
  final bool isSelf;
  final VoidCallback onEdit;
  final VoidCallback onToggleStatus;
  final VoidCallback onResetPassword;

  @override
  Widget build(BuildContext context) {
    // The owner account is not editable/disable-able from this screen.
    if (user.isOwner) {
      return const Padding(
        padding: EdgeInsets.only(right: AppSpacing.sm),
        child: Text('Owner',
            style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Edit',
          icon: const Icon(Icons.edit_outlined, size: 18),
          onPressed: onEdit,
        ),
        IconButton(
          tooltip: 'Send password reset',
          icon: const Icon(Icons.lock_reset, size: 18),
          onPressed: onResetPassword,
        ),
        IconButton(
          tooltip: user.isActive ? 'Disable' : 'Enable',
          icon: Icon(
            user.isActive ? Icons.block : Icons.check_circle_outline,
            size: 18,
            color: user.isActive ? AppColors.error : AppColors.success,
          ),
          // Guard against disabling yourself.
          onPressed: isSelf ? null : onToggleStatus,
        ),
      ],
    );
  }
}

class _UserFormDialog extends StatefulWidget {
  const _UserFormDialog({
    required this.existing,
    required this.repo,
    required this.businesses,
  });

  final AppUser? existing;
  final Repository repo;
  final List<Business> businesses;

  @override
  State<_UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends State<_UserFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _loginId;
  late final TextEditingController _password;
  late UserRole _role;
  late Set<String> _assigned;
  late Set<Permission> _granted;
  late Set<Permission> _revoked;

  AppUser? get _existing => widget.existing;
  bool get _isNew => _existing == null;

  @override
  void initState() {
    super.initState();
    final u = _existing;
    _name = TextEditingController(text: u?.name ?? '');
    _email = TextEditingController(text: u?.email ?? '');
    _loginId = TextEditingController(text: u?.loginId ?? '');
    _password = TextEditingController();
    _role = u?.role ?? UserRole.user;
    _assigned = {...?u?.assignedBusinessIds};
    _granted = {...?u?.grantedPermissions};
    _revoked = {...?u?.revokedPermissions};
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _loginId.dispose();
    _password.dispose();
    super.dispose();
  }

  /// Permissions that can be toggled as overrides — excludes owner-only
  /// administration flags, which never apply to Admin/User accounts.
  static const _tunable = <Permission>[
    Permission.editProduct,
    Permission.deleteProduct,
    Permission.editCampaign,
    Permission.deleteCampaign,
    Permission.editOrder,
    Permission.deleteOrder,
    Permission.createExpense,
    Permission.editExpense,
    Permission.deleteExpense,
    Permission.createDealer,
    Permission.editDealer,
    Permission.deleteDealer,
    Permission.exportData,
  ];

  static const _permLabels = <Permission, String>{
    Permission.editProduct: 'Edit products',
    Permission.deleteProduct: 'Delete products',
    Permission.editCampaign: 'Edit campaigns',
    Permission.deleteCampaign: 'Delete campaigns',
    Permission.editOrder: 'Edit orders',
    Permission.deleteOrder: 'Delete orders',
    Permission.createExpense: 'Add expenses',
    Permission.editExpense: 'Edit expenses',
    Permission.deleteExpense: 'Delete expenses',
    Permission.createDealer: 'Add dealers',
    Permission.editDealer: 'Edit dealers',
    Permission.deleteDealer: 'Delete dealers',
    Permission.exportData: 'Export data',
  };

  @override
  Widget build(BuildContext context) {
    // Effective set for preview = role defaults + granted − revoked.
    final effective = Permissions.resolve(
      _role,
      granted: _granted,
      revoked: _revoked,
    );
    return FormDialog(
      title: _isNew ? 'Add User' : 'Edit User',
      onSubmit: _submit,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppTextField(
              label: 'Full Name',
              controller: _name,
              isRequired: true,
              validator: (v) => Validators.required(v, field: 'Name'),
            ),
            const FormGap(),
            FormRow([
              AppTextField(
                label: 'Login ID',
                controller: _loginId,
                isRequired: true,
                helper: 'Username the person types to sign in.',
                validator: (v) => Validators.required(v, field: 'Login ID'),
              ),
              AppTextField(
                label: 'Email',
                controller: _email,
                isRequired: true,
                keyboardType: TextInputType.emailAddress,
                enabled: _isNew,
                helper: _isNew ? null : 'Email cannot be changed.',
                validator: Validators.email,
              ),
            ]),
            const FormGap(),
            FormRow([
              AppDropdown<UserRole>(
                label: 'Role',
                isRequired: true,
                value: _role,
                // Owner is never assignable from this screen.
                items: const [UserRole.admin, UserRole.user],
                itemLabel: (r) => r.label,
                onChanged: (v) => setState(() => _role = v ?? _role),
              ),
              if (_isNew)
                AppTextField(
                  label: 'Temporary Password',
                  controller: _password,
                  isRequired: true,
                  obscureText: true,
                  validator: Validators.password,
                )
              else
                const SizedBox.shrink(),
            ]),
            const FormGap(),
            LabeledField(
              label: 'Assigned Businesses',
              helper: 'Which businesses this user can access.',
              child: widget.businesses.isEmpty
                  ? const Text('No businesses available.',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textTertiary))
                  : Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        for (final b in widget.businesses)
                          FilterChip(
                            label: Text(b.name),
                            selected: _assigned.contains(b.id),
                            onSelected: (sel) => setState(() {
                              if (sel) {
                                _assigned.add(b.id);
                              } else {
                                _assigned.remove(b.id);
                              }
                            }),
                          ),
                      ],
                    ),
            ),
            const FormGap(),
            LabeledField(
              label: 'Permission Overrides',
              helper: 'Toggle capabilities on top of the role defaults.',
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final p in _tunable)
                    FilterChip(
                      label: Text(_permLabels[p] ?? p.name),
                      selected: effective.contains(p),
                      onSelected: (sel) =>
                          setState(() => _togglePermission(p, sel)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Records an override relative to the role default: if the desired state
  /// matches the default we clear any override, otherwise we grant/revoke.
  void _togglePermission(Permission p, bool desired) {
    final defaultOn = Permissions.forRole(_role).contains(p);
    _granted.remove(p);
    _revoked.remove(p);
    if (desired && !defaultOn) {
      _granted.add(p);
    } else if (!desired && defaultOn) {
      _revoked.add(p);
    }
  }

  Future<bool> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return false;
    try {
      if (_isNew) {
        final created = await widget.repo.createUser(
          loginId: _loginId.text.trim(),
          name: _name.text.trim(),
          email: _email.text.trim(),
          role: _role,
          assignedBusinessIds: _assigned.toList(),
          password: _password.text,
        );
        // Persist any permission overrides chosen at creation time.
        if (_granted.isNotEmpty || _revoked.isNotEmpty) {
          await widget.repo.saveUserProfile(created.copyWith(
            grantedPermissions: _granted,
            revokedPermissions: _revoked,
          ));
        }
      } else {
        await widget.repo.saveUserProfile(_existing!.copyWith(
          loginId: _loginId.text.trim(),
          name: _name.text.trim(),
          role: _role,
          assignedBusinessIds: _assigned.toList(),
          grantedPermissions: _granted,
          revokedPermissions: _revoked,
        ));
      }
      return true;
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
      return false;
    }
  }
}
