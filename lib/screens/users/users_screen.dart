import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/enums.dart';
import '../../core/permissions.dart';
import '../../core/routing/app_routes.dart';
import '../../core/routing/create_requests.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_x.dart';
import '../../core/utils/date_utils.dart';
import '../../models/access_request.dart';
import '../../models/app_user.dart';
import '../../models/business.dart';
import '../../state/app_state.dart';
import '../../state/data_controller.dart';
import '../../widgets/common/app_card.dart';
import '../../widgets/common/confirm_dialog.dart';
import '../../widgets/common/initials_avatar.dart';
import '../../widgets/common/page_header.dart';
import '../../widgets/common/state_views.dart';
import '../../widgets/common/status_badge.dart';
import '../../widgets/data/app_data_grid.dart';
import '../../widgets/forms/app_form.dart';
import '../../widgets/layout/app_page.dart';
import '../../widgets/layout/kpi_strip.dart';
import 'user_form_dialog.dart';
import 'user_view_dialog.dart';

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
  _UsersData? _data;
  Object? _error;

  /// Bumped per load, so a slow older load never overwrites a newer one.
  int _loadId = 0;

  @override
  void initState() {
    super.initState();
    _load();
    // "New user" from the top bar / palette / N key lands here.
    CreateRequests.instance.addListener(_onCreateRequest);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onCreateRequest());
  }

  @override
  void dispose() {
    CreateRequests.instance.removeListener(_onCreateRequest);
    super.dispose();
  }

  void _onCreateRequest() {
    if (!mounted || !CreateRequests.instance.take(Routes.users)) return;
    _openForm(null, context.read<DataController>().selectableBusinesses);
  }

  Future<void> _load() async {
    final id = ++_loadId;
    final repo = context.read<AppState>().repository;
    try {
      final users = await repo.fetchUsers();
      // Access requests are best-effort: a backend or ruleset without the
      // collection should not break the whole screen.
      var requests = const <AccessRequest>[];
      try {
        requests = await repo.fetchAccessRequests();
      } catch (_) {
        requests = const [];
      }
      if (!mounted || id != _loadId) return;
      setState(() {
        _data = _UsersData(users: users, requests: requests);
        _error = null;
      });
    } catch (e) {
      if (!mounted || id != _loadId) return;
      setState(() => _error = e);
    }
  }

  /// Reloads in the background: the current list stays on screen meanwhile.
  void _reload() {
    setState(() => _error = null);
    _load();
  }

  bool _rebuildingIndex = false;

  Future<void> _rebuildSignInIndex() async {
    final repo = context.read<AppState>().repository;
    setState(() => _rebuildingIndex = true);
    try {
      final count = await repo.rebuildLoginIndex();
      if (mounted) {
        showSuccessSnack(context,
            'Sign-in index rebuilt: $count login ${count == 1 ? 'ID' : 'IDs'}');
      }
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _rebuildingIndex = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final data = context.watch<DataController>();
    final user = appState.currentUser;
    final canManage = user?.can(Permission.manageUsers) ?? false;

    if (!canManage) {
      return const AppPage(children: [
        PageHeader(title: 'Users', icon: Icons.group_outlined),
        SizedBox(height: 48),
        EmptyView(
          title: 'Restricted',
          message: 'Only the owner can manage users.',
          icon: Icons.lock_outline,
        ),
      ]);
    }

    final loaded = _data;
    final addButton = FilledButton.icon(
      onPressed: () => _openForm(null, data.selectableBusinesses),
      icon: const Icon(Icons.person_add_alt, size: 18),
      label: const Text('Add User'),
    );
    final header = PageHeader(
      title: 'Users',
      icon: Icons.group_outlined,
      count: loaded?.users.length,
      subtitle: 'Manage team members, roles and access',
      actions: [
        if (appState.isFirebaseMode)
          Tooltip(
            message: 'Lets everyone sign in with their login ID. Run it '
                'once after deploying the latest security rules.',
            child: OutlinedButton.icon(
              onPressed: _rebuildingIndex ? null : _rebuildSignInIndex,
              icon: const Icon(Icons.manage_search, size: 18),
              label: const Text('Rebuild sign-in index'),
            ),
          ),
        addButton,
      ],
    );

    if (loaded == null) {
      return AppPage(children: [
        header,
        const SizedBox(height: AppSpacing.lg),
        if (_error != null)
          ErrorView(message: _error.toString(), onRetry: _reload)
        else
          const Padding(
            padding: EdgeInsets.only(top: 32),
            child: LoadingView(),
          ),
      ]);
    }

    final users = loaded.users;
    final requests = loaded.requests;
    final currentUid = user?.uid;
    final businesses = data.businesses;

    return AppPage.slivers(
      slivers: [
        SliverToBoxAdapter(child: header),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
        if (_error != null) ...[
          SliverToBoxAdapter(
            child: ErrorView(message: _error.toString(), onRetry: _reload),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
        ],
        SliverToBoxAdapter(
            child: KpiStrip(items: _kpis(context, users, requests))),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
        if (requests.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: _AccessRequestsSection(
              requests: requests,
              onApprove: (r) => _approveRequest(r, data.selectableBusinesses),
              onDeny: _denyRequest,
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
        ],
        SliverAppDataGrid<AppUser>(
          gridId: 'users',
          rows: users,
          rowKey: (u) => u.uid,
          exportName: 'users',
          searchHint: 'Search by name, login ID, email, role, status or '
              'business…',
          searchText: (u) => '${u.name} ${u.email} ${u.loginId} '
              '${u.role.label} ${u.status.label} '
              '${_accessNames(u, businesses).join(' ')}',
          onRowTap: (u) => _openView(u, businesses),
          initialSort: const [GridSort('name')],
          quickFilters: [
            GridQuickFilter<AppUser>(
              id: 'active',
              label: 'Active',
              icon: Icons.check_circle_outline,
              test: (u) => u.isActive,
            ),
            GridQuickFilter<AppUser>(
              id: 'disabled',
              label: 'Disabled',
              icon: Icons.block,
              test: (u) => !u.isActive,
            ),
            GridQuickFilter<AppUser>(
              id: 'admins',
              label: 'Admins',
              test: (u) => u.role == UserRole.admin,
            ),
            GridQuickFilter<AppUser>(
              id: 'users',
              label: 'Users',
              test: (u) => u.role == UserRole.user,
            ),
          ],
          bulkActions: [
            GridBulkAction<AppUser>(
              label: 'Disable',
              icon: Icons.block,
              allowed: (u) => _mayChange(u, currentUid) && u.isActive,
              onRun: (context, rows) => _bulkStatus(context, rows, false),
            ),
            GridBulkAction<AppUser>(
              label: 'Enable',
              icon: Icons.check_circle_outline,
              allowed: (u) => _mayChange(u, currentUid) && !u.isActive,
              onRun: (context, rows) => _bulkStatus(context, rows, true),
            ),
            GridBulkAction<AppUser>(
              label: 'Delete',
              icon: Icons.delete_outline,
              destructive: true,
              allowed: (u) => _mayChange(u, currentUid),
              onRun: _bulkDelete,
            ),
          ],
          emptyTitle: 'No users found',
          emptyIcon: Icons.group_outlined,
          emptyMessage: 'Add the people who work with you and choose what '
              'they can see.',
          emptyAction: addButton,
          columns: [
            GridColumn<AppUser>(
              id: 'name',
              label: 'User',
              pinned: true,
              flex: 3,
              minWidth: 220,
              cardRole: CardRole.title,
              cell: (u) => _UserCell(user: u),
              sortValue: (u) => u.name.toLowerCase(),
              exportValue: (u) => u.name,
            ),
            GridColumn<AppUser>(
              id: 'email',
              label: 'Email',
              visibleByDefault: false,
              cardRole: CardRole.hidden,
              cell: (u) => Text(u.email),
              sortValue: (u) => u.email.toLowerCase(),
              exportValue: (u) => u.email,
            ),
            GridColumn<AppUser>(
              id: 'loginId',
              label: 'Login ID',
              cardRole: CardRole.meta,
              cell: (u) => Text(u.loginId,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              sortValue: (u) => u.loginId.toLowerCase(),
              exportValue: (u) => u.loginId,
            ),
            GridColumn<AppUser>(
              id: 'role',
              label: 'Role',
              minWidth: 100,
              cardRole: CardRole.meta,
              cell: (u) => StatusBadge.role(u.role),
              sortValue: (u) => u.role.label,
              exportValue: (u) => u.role.label,
              filter: GridFilter.choice((u) => u.role.label,
                  options: [for (final r in UserRole.values) r.label]),
            ),
            GridColumn<AppUser>(
              id: 'access',
              label: 'Businesses',
              flex: 2,
              minWidth: 180,
              cardRole: CardRole.meta,
              cell: (u) => _AccessChips(user: u, businesses: businesses),
              sortValue: (u) => _accessLabel(u, businesses).toLowerCase(),
              exportValue: (u) => _accessLabel(u, businesses),
            ),
            GridColumn<AppUser>(
              id: 'lastLogin',
              label: 'Last Login',
              minWidth: 110,
              cardRole: CardRole.meta,
              cell: (u) => u.lastLoginAt == null
                  ? Text('Never',
                      style: TextStyle(color: context.tokens.textTertiary))
                  : Text(AppDate.format(u.lastLoginAt)),
              sortValue: (u) => u.lastLoginAt?.millisecondsSinceEpoch ?? 0,
              exportValue: (u) =>
                  u.lastLoginAt == null ? '' : AppDate.format(u.lastLoginAt),
              filter: GridFilter.dateRange((u) => u.lastLoginAt),
            ),
            GridColumn<AppUser>(
              id: 'status',
              label: 'Status',
              minWidth: 110,
              cardRole: CardRole.badge,
              cell: (u) => StatusBadge.account(u.status),
              sortValue: (u) => u.status.label,
              exportValue: (u) => u.status.label,
              filter: GridFilter.choice((u) => u.status.label,
                  options: [for (final s in AccountStatus.values) s.label]),
            ),
            GridColumn<AppUser>(
              id: 'actions',
              label: '',
              pinned: true,
              cardRole: CardRole.actions,
              // View/Edit + More (48 px each) plus the cell padding.
              minWidth: 2 * AppSpacing.md + 48 * 3,
              cell: (u) => _RowActions(
                user: u,
                isSelf: u.uid == currentUid,
                onView: () => _openView(u, businesses),
                onEdit: () => _openForm(u, data.selectableBusinesses),
                onToggleStatus: () => _toggleStatus(u),
                onResetPassword: () => _resetPassword(u),
                onDelete: () => _deleteUser(u),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// The owner account and your own account are protected from bulk and
  /// single disable/delete.
  static bool _mayChange(AppUser u, String? currentUid) =>
      !u.isOwner && u.uid != currentUid;

  static List<String> _accessNames(AppUser u, List<Business> businesses) =>
      u.isOwner
          ? const ['All businesses']
          : UserViewDialog.accessNames(u, businesses);

  static String _accessLabel(AppUser u, List<Business> businesses) {
    final names = _accessNames(u, businesses);
    return names.isEmpty ? 'None' : names.join(', ');
  }

  List<KpiItem> _kpis(
      BuildContext context, List<AppUser> users, List<AccessRequest> requests) {
    final t = context.tokens;
    final active = users.where((u) => u.isActive).length;
    final disabled = users.length - active;
    final admins = users.where((u) => u.role == UserRole.admin).length;
    final owners = users.where((u) => u.role == UserRole.owner).length;
    final staff = users.where((u) => u.role == UserRole.user).length;
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    final recent = users
        .where((u) => u.lastLoginAt != null && u.lastLoginAt!.isAfter(cutoff))
        .length;
    return [
      KpiItem(
        label: 'Users',
        value: '${users.length}',
        icon: Icons.group_outlined,
        caption: '$recent signed in this month',
      ),
      KpiItem(
        label: 'Active',
        value: '$active',
        icon: Icons.check_circle_outline,
        tone: t.success,
        tooltip: 'Accounts that can sign in.',
      ),
      KpiItem(
        label: 'Disabled',
        value: '$disabled',
        icon: Icons.block,
        tone: disabled > 0 ? t.warning : null,
        tooltip: 'Accounts blocked from signing in until re-enabled.',
      ),
      KpiItem(
        label: 'Pending requests',
        value: '${requests.length}',
        icon: Icons.how_to_reg_outlined,
        tone: requests.isNotEmpty ? t.primary : null,
        caption: requests.isEmpty ? 'Nothing waiting' : 'Waiting for approval',
        tooltip: 'People who signed in but have no profile yet.',
      ),
      KpiItem(
        label: 'Admins',
        value: '$admins',
        icon: Icons.shield_outlined,
        caption: '$owners owner · $staff users',
      ),
    ];
  }

  Future<void> _openForm(AppUser? existing, List<Business> businesses) async {
    final repo = context.read<AppState>().repository;
    final saved = await showAppForm<bool>(
      context: context,
      builder: (_) => UserFormDialog(
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

  /// Read-only detail dialog. Owner-only screen, so it shows the full
  /// profile; from here the owner can jump straight into editing (except for
  /// the owner account itself, which isn't editable from this screen).
  Future<void> _openView(AppUser u, List<Business> businesses) async {
    final action = await showDialog<UserViewAction>(
      context: context,
      builder: (_) => UserViewDialog(user: u, businesses: businesses),
    );
    if (!mounted) return;
    switch (action) {
      case UserViewAction.edit:
        await _openForm(u, context.read<DataController>().selectableBusinesses);
      case UserViewAction.resetPassword:
        await _resetPassword(u);
      case null:
        break;
    }
  }

  Future<void> _approveRequest(
      AccessRequest request, List<Business> businesses) async {
    final repo = context.read<AppState>().repository;
    final saved = await showAppForm<bool>(
      context: context,
      builder: (_) => UserFormDialog(
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

  Future<void> _bulkStatus(
      BuildContext context, List<AppUser> rows, bool enable) async {
    final repo = this.context.read<AppState>().repository;
    final ok = await showConfirmDialog(
      context,
      title: enable
          ? 'Enable ${rows.length} user${rows.length == 1 ? '' : 's'}?'
          : 'Disable ${rows.length} user${rows.length == 1 ? '' : 's'}?',
      message: enable
          ? 'They will be able to sign in again.'
          : 'They will be signed out and blocked from logging in until '
              're-enabled.',
      confirmLabel: enable ? 'Enable' : 'Disable',
      destructive: !enable,
    );
    if (!ok || !context.mounted) return;
    await runGridBulk<AppUser>(
      context,
      rows: rows,
      verb: enable ? 'Enabling' : 'Disabling',
      noun: 'users',
      describe: (u) => u.name,
      task: (u) => repo.setUserStatus(
          u.uid, enable ? AccountStatus.active : AccountStatus.disabled),
    );
    if (mounted) _reload();
  }

  Future<void> _bulkDelete(BuildContext context, List<AppUser> rows) async {
    final repo = this.context.read<AppState>().repository;
    final ok = await showConfirmDialog(
      context,
      title: 'Delete ${rows.length} user${rows.length == 1 ? '' : 's'}?',
      message: 'Permanently delete the selected profiles? This removes their '
          'access. This action cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (!ok || !context.mounted) return;
    await runGridBulk<AppUser>(
      context,
      rows: rows,
      verb: 'Deleting',
      noun: 'users',
      describe: (u) => u.name,
      task: (u) => repo.deleteUser(u.uid),
    );
    if (mounted) _reload();
  }
}

/// Combined payload for the screen's loads.
class _UsersData {
  const _UsersData({required this.users, required this.requests});
  final List<AppUser> users;
  final List<AccessRequest> requests;
}

/// Avatar, name and email: the user's identity cell.
class _UserCell extends StatelessWidget {
  const _UserCell({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final name = user.name.trim().isEmpty ? 'Unnamed user' : user.name;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        InitialsAvatar(name: name, size: 34),
        const SizedBox(width: AppSpacing.md),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(user.email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: t.textSecondary)),
            ],
          ),
        ),
      ],
    );
  }
}

/// The businesses a user can open, as small chips (the first two, then "+n").
class _AccessChips extends StatelessWidget {
  const _AccessChips({required this.user, required this.businesses});

  final AppUser user;
  final List<Business> businesses;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    if (user.isOwner) {
      return const _MiniChip('All businesses', primary: true);
    }
    final names = UserViewDialog.accessNames(user, businesses);
    if (names.isEmpty) {
      return Text('None', style: TextStyle(color: t.textTertiary));
    }
    const shown = 2;
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        for (final n in names.take(shown)) _MiniChip(n),
        if (names.length > shown)
          Tooltip(
            message: names.skip(shown).join(', '),
            child: _MiniChip('+${names.length - shown}'),
          ),
      ],
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip(this.label, {this.primary = false});

  final String label;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      constraints: const BoxConstraints(maxWidth: 150),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: primary ? t.primarySurface : t.surfaceAlt,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: primary ? Colors.transparent : t.border),
      ),
      child: Text(label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: primary ? t.primary : t.textSecondary)),
    );
  }
}

/// Highlights identities that have signed in but have no profile yet, letting
/// the Owner grant access against the *existing* account (avoiding the
/// "email already in use" collision that blocks re-creating the account).
class _AccessRequestsSection extends StatelessWidget {
  const _AccessRequestsSection({
    required this.requests,
    required this.onApprove,
    required this.onDeny,
  });

  final List<AccessRequest> requests;
  final ValueChanged<AccessRequest> onApprove;
  final ValueChanged<AccessRequest> onDeny;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: t.primarySurface,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Icon(Icons.how_to_reg_outlined,
                    size: 18, color: t.primary),
              ),
              const SizedBox(width: AppSpacing.md),
              Flexible(
                child: Text('Pending access requests',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: AppSpacing.sm),
              StatusBadge(
                  label: '${requests.length}', tone: BadgeTone.primary),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'These people signed in but have no profile yet. Approve to grant '
            'access to their existing account.',
            style: TextStyle(color: t.textSecondary, fontSize: 12.5),
          ),
          const SizedBox(height: AppSpacing.lg),
          LayoutBuilder(builder: (context, c) {
            const gap = AppSpacing.md;
            final columns =
                ((c.maxWidth + gap) / (340 + gap)).floor().clamp(1, 3);
            final width = (c.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final r in requests)
                  SizedBox(
                    width: width,
                    child: _RequestCard(
                      request: r,
                      onApprove: () => onApprove(r),
                      onDeny: () => onDeny(r),
                    ),
                  ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.request,
    required this.onApprove,
    required this.onDeny,
  });

  final AccessRequest request;
  final VoidCallback onApprove;
  final VoidCallback onDeny;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final name = request.displayName.trim().isNotEmpty
        ? request.displayName.trim()
        : request.email;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: t.surfaceAlt,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              InitialsAvatar(name: name, size: 36),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(request.email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            TextStyle(fontSize: 12, color: t.textSecondary)),
                    Text('Requested ${AppDate.format(request.requestedAt)}',
                        style:
                            TextStyle(fontSize: 11.5, color: t.textTertiary)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: onDeny, child: const Text('Deny')),
              const SizedBox(width: AppSpacing.sm),
              FilledButton.icon(
                onPressed: onApprove,
                icon: const Icon(Icons.check, size: 16),
                label: const Text('Approve'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _UserMenuAction { view, resetPassword, toggleStatus, delete }

/// A row's actions: Edit up front, the rest in a menu. The owner account is
/// read-only (view only); you can't disable or delete your own account.
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
    final t = context.tokens;
    // The owner account is not editable/disable-able from this screen, but it
    // can still be viewed.
    if (user.isOwner) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: 'Owner account — read-only',
            child: Icon(Icons.lock_outline, size: 16, color: t.textTertiary),
          ),
          IconButton(
            tooltip: 'View',
            icon: const Icon(Icons.visibility_outlined, size: 18),
            onPressed: onView,
          ),
        ],
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
        PopupMenuButton<_UserMenuAction>(
          tooltip: 'More actions',
          icon: const Icon(Icons.more_vert, size: 18),
          onSelected: (a) {
            switch (a) {
              case _UserMenuAction.view:
                onView();
              case _UserMenuAction.resetPassword:
                onResetPassword();
              case _UserMenuAction.toggleStatus:
                onToggleStatus();
              case _UserMenuAction.delete:
                onDelete();
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: _UserMenuAction.view,
              child: _MenuRow(Icons.visibility_outlined, 'View'),
            ),
            const PopupMenuItem(
              value: _UserMenuAction.resetPassword,
              child: _MenuRow(Icons.lock_reset, 'Send password reset'),
            ),
            // Guard against disabling or deleting yourself.
            PopupMenuItem(
              value: _UserMenuAction.toggleStatus,
              enabled: !isSelf,
              child: _MenuRow(
                user.isActive ? Icons.block : Icons.check_circle_outline,
                user.isActive ? 'Disable' : 'Enable',
                color: user.isActive ? t.error : t.success,
              ),
            ),
            PopupMenuItem(
              value: _UserMenuAction.delete,
              enabled: !isSelf,
              child: _MenuRow(
                Icons.delete_outline,
                isSelf ? 'You cannot delete your own account' : 'Delete',
                color: t.error,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow(this.icon, this.label, {this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color ?? context.tokens.textSecondary),
        const SizedBox(width: AppSpacing.md),
        Flexible(child: Text(label, style: TextStyle(color: color))),
      ],
    );
  }
}
