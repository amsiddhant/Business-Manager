import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/enums.dart';
import '../../core/permissions.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_utils.dart';
import '../../core/validators.dart';
import '../../data/repository.dart';
import '../../models/access_request.dart';
import '../../models/app_user.dart';
import '../../models/business.dart';
import '../../state/app_state.dart';
import '../../state/data_controller.dart';
import '../../widgets/common/app_card.dart';
import '../../widgets/common/confirm_dialog.dart';
import '../../widgets/common/data_table_card.dart';
import '../../widgets/common/detail_widgets.dart';
import '../../widgets/common/initials_avatar.dart';
import '../../widgets/common/page_header.dart';
import '../../widgets/common/state_views.dart';
import '../../widgets/common/status_badge.dart';
import '../../widgets/forms/form_dialog.dart';
import '../../widgets/forms/form_fields.dart';

/// Owner-only user management: approve pending access requests, create
/// Admin/User accounts, edit profiles, assign businesses, tune per-user
/// permission overrides, enable/disable and delete accounts. Users and access
/// requests are fetched directly (they are not part of the cached working set).
class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  late Future<_UsersData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_UsersData> _load() async {
    final repo = context.read<AppState>().repository;
    final users = await repo.fetchUsers();
    // Access requests are best-effort: a backend or ruleset without the
    // collection should not break the whole screen.
    var requests = const <AccessRequest>[];
    try {
      requests = await repo.fetchAccessRequests();
    } catch (_) {
      requests = const [];
    }
    return _UsersData(users: users, requests: requests);
  }

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
        FutureBuilder<_UsersData>(
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
            final result = snapshot.data ?? const _UsersData(users: [], requests: []);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (result.requests.isNotEmpty) ...[
                  _AccessRequestsCard(
                    requests: result.requests,
                    businesses: data.selectableBusinesses,
                    onApprove: (r) =>
                        _approveRequest(r, data.selectableBusinesses),
                    onDeny: _denyRequest,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
                _UsersTable(
                  users: result.users,
                  currentUid: user?.uid,
                  businesses: data.businesses,
                  onView: (u) => _openView(u, data.businesses),
                  onEdit: (u) => _openForm(u, data.selectableBusinesses),
                  onToggleStatus: _toggleStatus,
                  onResetPassword: _resetPassword,
                  onDelete: _deleteUser,
                ),
              ],
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

  /// Read-only detail modal. Owner-only screen, so it shows the full profile;
  /// from here the owner can jump straight into editing (except for the owner
  /// account itself, which isn't editable from this screen).
  Future<void> _openView(AppUser u, List<Business> businesses) async {
    final action = await showDialog<_UserViewAction>(
      context: context,
      builder: (_) => UserViewDialog(user: u, businesses: businesses),
    );
    if (action == _UserViewAction.edit && mounted) {
      await _openForm(u, context.read<DataController>().selectableBusinesses);
    }
  }

  Future<void> _approveRequest(
      AccessRequest request, List<Business> businesses) async {
    final repo = context.read<AppState>().repository;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _UserFormDialog(
        existing: null,
        request: request,
        repo: repo,
        businesses: businesses,
      ),
    );
    if (saved == true) {
      _reload();
      if (mounted) showSuccessSnack(context, 'Access granted');
    }
  }

  Future<void> _denyRequest(AccessRequest request) async {
    final repo = context.read<AppState>().repository;
    final ok = await showConfirmDialog(
      context,
      title: 'Deny access request?',
      message:
          'Dismiss the request from ${request.email}? They will not gain access. '
          'They can request again by signing in.',
      confirmLabel: 'Deny',
    );
    if (ok != true) return;
    try {
      await repo.denyAccessRequest(request.uid);
      _reload();
      if (mounted) showSuccessSnack(context, 'Request dismissed');
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
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

  Future<void> _deleteUser(AppUser u) async {
    final repo = context.read<AppState>().repository;
    final ok = await showConfirmDialog(
      context,
      title: 'Delete user?',
      message: 'Permanently delete "${u.name}" (${u.email})? This removes their '
          'profile and access. This action cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (ok != true) return;
    try {
      await repo.deleteUser(u.uid);
      _reload();
      if (mounted) showSuccessSnack(context, 'User deleted');
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

/// Combined payload for the screen's single future.
class _UsersData {
  const _UsersData({required this.users, required this.requests});
  final List<AppUser> users;
  final List<AccessRequest> requests;
}

/// Highlights identities that have signed in but have no profile yet, letting
/// the Owner grant access against the *existing* account (avoiding the
/// "email already in use" collision that blocks re-creating the account).
class _AccessRequestsCard extends StatelessWidget {
  const _AccessRequestsCard({
    required this.requests,
    required this.businesses,
    required this.onApprove,
    required this.onDeny,
  });

  final List<AccessRequest> requests;
  final List<Business> businesses;
  final ValueChanged<AccessRequest> onApprove;
  final ValueChanged<AccessRequest> onDeny;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.how_to_reg_outlined,
                  size: 20, color: AppColors.primary),
              const SizedBox(width: AppSpacing.sm),
              Text('Pending access requests',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(width: AppSpacing.sm),
              StatusBadge(
                  label: '${requests.length}', tone: BadgeTone.primary),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'These people signed in but have no profile yet. Approve to grant '
            'access to their existing account.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
          ),
          const SizedBox(height: AppSpacing.md),
          for (final r in requests) ...[
            const Divider(height: 1, color: AppColors.border),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: _RequestRow(
                request: r,
                onApprove: () => onApprove(r),
                onDeny: () => onDeny(r),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RequestRow extends StatelessWidget {
  const _RequestRow({
    required this.request,
    required this.onApprove,
    required this.onDeny,
  });

  final AccessRequest request;
  final VoidCallback onApprove;
  final VoidCallback onDeny;

  @override
  Widget build(BuildContext context) {
    final title = request.displayName.trim().isNotEmpty
        ? request.displayName.trim()
        : request.email;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(
                '${request.email} · requested ${AppDate.format(request.requestedAt)}',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        TextButton(onPressed: onDeny, child: const Text('Deny')),
        const SizedBox(width: AppSpacing.sm),
        ElevatedButton.icon(
          onPressed: onApprove,
          icon: const Icon(Icons.check, size: 16),
          label: const Text('Approve'),
        ),
      ],
    );
  }
}

class _UsersTable extends StatelessWidget {
  const _UsersTable({
    required this.users,
    required this.currentUid,
    required this.businesses,
    required this.onView,
    required this.onEdit,
    required this.onToggleStatus,
    required this.onResetPassword,
    required this.onDelete,
  });

  final List<AppUser> users;
  final String? currentUid;
  final List<Business> businesses;
  final ValueChanged<AppUser> onView;
  final ValueChanged<AppUser> onEdit;
  final ValueChanged<AppUser> onToggleStatus;
  final ValueChanged<AppUser> onResetPassword;
  final ValueChanged<AppUser> onDelete;

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
      onRowTap: onView,
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
            onView: () => onView(u),
            onEdit: () => onEdit(u),
            onToggleStatus: () => onToggleStatus(u),
            onResetPassword: () => onResetPassword(u),
            onDelete: () => onDelete(u),
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
    required this.onView,
    required this.onEdit,
    required this.onToggleStatus,
    required this.onResetPassword,
    required this.onDelete,
  });

  final AppUser user;
  final bool isSelf;
  final VoidCallback onView;
  final VoidCallback onEdit;
  final VoidCallback onToggleStatus;
  final VoidCallback onResetPassword;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    // The owner account is not editable/disable-able from this screen, but it
    // can still be viewed.
    if (user.isOwner) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'View',
            icon: const Icon(Icons.visibility_outlined, size: 18),
            onPressed: onView,
          ),
          const Padding(
            padding: EdgeInsets.only(left: AppSpacing.xs, right: AppSpacing.sm),
            child: Text('Owner',
                style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
          ),
        ],
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'View',
          icon: const Icon(Icons.visibility_outlined, size: 18),
          onPressed: onView,
        ),
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
        IconButton(
          tooltip: isSelf ? 'You cannot delete your own account' : 'Delete',
          icon: const Icon(Icons.delete_outline, size: 18),
          color: AppColors.error,
          // Guard against deleting yourself.
          onPressed: isSelf ? null : onDelete,
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
    this.request,
  });

  final AppUser? existing;

  /// When set (and [existing] is null) the dialog is in "approve" mode: it
  /// provisions a profile for an already-authenticated identity rather than
  /// creating a fresh auth account.
  final AccessRequest? request;
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
  AccessRequest? get _request => widget.request;

  /// Editing an existing profile.
  bool get _isEdit => _existing != null;

  /// Approving a pending request (auth account already exists).
  bool get _isApprove => _existing == null && _request != null;

  /// Creating a brand-new user (and a new auth account).
  bool get _isCreate => _existing == null && _request == null;

  @override
  void initState() {
    super.initState();
    final u = _existing;
    final r = _request;
    _name = TextEditingController(text: u?.name ?? r?.displayName ?? '');
    _email = TextEditingController(text: u?.email ?? r?.email ?? '');
    _loginId = TextEditingController(text: u?.loginId ?? r?.email ?? '');
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
    final title = _isEdit
        ? 'Edit User'
        : _isApprove
            ? 'Approve Access Request'
            : 'Add User';
    return FormDialog(
      title: title,
      submitLabel: _isApprove ? 'Grant Access' : 'Save',
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
                enabled: _isCreate,
                helper: _isCreate ? null : 'Email cannot be changed.',
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
              if (_isCreate)
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
      if (_isCreate) {
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
      } else if (_isApprove) {
        await widget.repo.approveAccessRequest(
          _request!,
          loginId: _loginId.text.trim(),
          name: _name.text.trim(),
          role: _role,
          assignedBusinessIds: _assigned.toList(),
          grantedPermissions: _granted,
          revokedPermissions: _revoked,
        );
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

/// What the owner chose to do from the read-only view modal.
enum _UserViewAction { edit }

/// Read-only detail modal for a user. Rendered only on the owner-only Users
/// screen, so the viewer always sees the full profile — identity, role/status,
/// assigned businesses, effective permissions (role defaults ± overrides) and
/// the audit trail — with a copy button on every value. Mirrors the approved
/// `ContactViewDialog` pattern: pure presentation, pops a [_UserViewAction] (or
/// null) rather than doing any persistence itself.
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
  String _accessValue() {
    if (user.isOwner) return 'All businesses';
    if (user.assignedBusinessIds.isEmpty) return 'None';
    return user.assignedBusinessIds
        .map((id) =>
            businesses.where((b) => b.id == id).map((b) => b.name).firstOrNull ??
            id)
        .join(', ');
  }

  /// Turns a `Permission` enum name into a human label, e.g.
  /// `deleteProduct` → "Delete product".
  static String _permissionLabel(Permission p) {
    // Split camelCase into words, lowercase, then capitalise the first letter.
    final words = p.name
        .replaceAllMapped(RegExp(r'(?<=[a-z])(?=[A-Z])'), (_) => ' ')
        .toLowerCase();
    if (words.isEmpty) return words;
    return '${words[0].toUpperCase()}${words.substring(1)}';
  }

  @override
  Widget build(BuildContext context) {
    final name = user.name.trim().isEmpty ? 'Unnamed user' : user.name;

    // Effective capabilities = role defaults + granted − revoked.
    final effective = Permissions.resolve(
      user.role,
      granted: user.grantedPermissions,
      revoked: user.revokedPermissions,
    );
    final sortedPerms = effective.toList()
      ..sort((a, b) => a.index.compareTo(b.index));

    final profileFields = <DetailField>[
      DetailField('Name', user.name, Icons.person_outline),
      DetailField('Login ID', user.loginId, Icons.badge_outlined),
      DetailField('Email', user.email, Icons.mail_outline),
      DetailField('User ID', user.uid, Icons.tag),
      DetailField('Role', user.role.label, Icons.shield_outlined),
      DetailField('Account status', user.status.label, Icons.toggle_on_outlined),
      DetailField('Assigned businesses', _accessValue(), Icons.business_outlined),
      DetailField('Last login', AppDate.format(user.lastLoginAt), Icons.login),
    ];

    final auditFields = <DetailField>[
      DetailField('Created', AppDate.format(user.audit.createdAt), Icons.schedule),
      DetailField('Created by', user.audit.createdBy ?? '', Icons.person_add_alt),
      DetailField('Updated', AppDate.format(user.audit.updatedAt), Icons.update),
      DetailField('Updated by', user.audit.updatedBy ?? '', Icons.manage_accounts_outlined),
    ];

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header: avatar + name + role/status badges + close.
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl, AppSpacing.lg, AppSpacing.md, AppSpacing.lg),
          child: Row(
            children: [
              InitialsAvatar(name: name, size: 52),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(name,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
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
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // Body: every field with a copy button, then permissions + audit.
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < profileFields.length; i++) ...[
                  if (i > 0) const SizedBox(height: AppSpacing.lg),
                  DetailFieldTile(field: profileFields[i]),
                ],
                const SizedBox(height: AppSpacing.xl),
                _SectionLabel('Effective permissions (${sortedPerms.length})'),
                const SizedBox(height: AppSpacing.sm),
                if (sortedPerms.isEmpty)
                  const Text('No permissions.',
                      style: TextStyle(
                          fontSize: 13, color: AppColors.textTertiary))
                else
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      for (final p in sortedPerms)
                        _PermissionChip(
                          label: _permissionLabel(p),
                          isOverride: user.grantedPermissions.contains(p),
                        ),
                    ],
                  ),
                if (user.revokedPermissions.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  _SectionLabel(
                      'Revoked from role default (${user.revokedPermissions.length})'),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      for (final p in (user.revokedPermissions.toList()
                        ..sort((a, b) => a.index.compareTo(b.index))))
                        _PermissionChip(
                            label: _permissionLabel(p), isRevoked: true),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
                _SectionLabel('Audit'),
                const SizedBox(height: AppSpacing.md),
                for (var i = 0; i < auditFields.length; i++) ...[
                  if (i > 0) const SizedBox(height: AppSpacing.lg),
                  DetailFieldTile(field: auditFields[i]),
                ],
              ],
            ),
          ),
        ),
        // The owner account is not editable from this screen; every other
        // account offers a jump straight into the edit form.
        if (!user.isOwner) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ElevatedButton.icon(
                  onPressed: () =>
                      Navigator.of(context).pop(_UserViewAction.edit),
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
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 540,
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
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
        color: AppColors.textSecondary,
      ),
    );
  }
}

/// A read-only permission pill. [isOverride] flags a capability granted on top
/// of the role default; [isRevoked] flags one removed from it.
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
    final Color bg;
    final Color fg;
    if (isRevoked) {
      bg = AppColors.errorSurface;
      fg = AppColors.error;
    } else if (isOverride) {
      bg = AppColors.primarySurface;
      fg = AppColors.primary;
    } else {
      bg = AppColors.surfaceAlt;
      fg = AppColors.textSecondary;
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
          Text(label,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
        ],
      ),
    );
  }
}
