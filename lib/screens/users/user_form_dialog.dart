import 'package:flutter/material.dart';

import '../../core/enums.dart';
import '../../core/permissions.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_x.dart';
import '../../core/validators.dart';
import '../../data/repository.dart';
import '../../models/access_request.dart';
import '../../models/app_user.dart';
import '../../models/business.dart';
import '../../widgets/common/confirm_dialog.dart';
import '../../widgets/forms/form_dialog.dart';
import '../../widgets/forms/form_fields.dart';
import '../../widgets/forms/form_section.dart';

/// The Add / Edit / Approve form for a user: account details, role and
/// businesses, then the per-user permission overrides.
///
/// Three modes: editing an [existing] profile, approving a pending [request]
/// (the auth account already exists), or creating a brand-new user (which also
/// creates the auth account). Saving goes through the repository, which keeps
/// the sign-in index in step.
class UserFormDialog extends StatefulWidget {
  const UserFormDialog({
    super.key,
    required this.existing,
    required this.repo,
    required this.businesses,
    this.request,
  });

  final AppUser? existing;

  /// When set (and [existing] is null) the form is in "approve" mode: it
  /// provisions a profile for an already-authenticated identity rather than
  /// creating a fresh auth account.
  final AccessRequest? request;
  final Repository repo;
  final List<Business> businesses;

  @override
  State<UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends State<UserFormDialog> {
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
  /// administration flags, which never apply to Admin/User accounts. Grouped
  /// by area for the form.
  static const _groups = <(String, List<Permission>)>[
    ('Products', [Permission.editProduct, Permission.deleteProduct]),
    ('Campaigns', [Permission.editCampaign, Permission.deleteCampaign]),
    ('Orders', [Permission.editOrder, Permission.deleteOrder]),
    (
      'Expenses',
      [
        Permission.createExpense,
        Permission.editExpense,
        Permission.deleteExpense,
      ]
    ),
    (
      'Dealers',
      [
        Permission.createDealer,
        Permission.editDealer,
        Permission.deleteDealer,
      ]
    ),
    ('Data', [Permission.exportData]),
    ('Organisation', [Permission.manageSettings, Permission.manageGoals]),
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
    Permission.manageSettings: 'Customise settings',
    Permission.manageGoals: 'Set goals',
  };

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // Effective set for preview = role defaults + granted − revoked.
    final effective = Permissions.resolve(
      _role,
      granted: _granted,
      revoked: _revoked,
    );
    final overrides = _granted.length + _revoked.length;
    final title = _isEdit
        ? 'Edit User'
        : _isApprove
            ? 'Approve Access Request'
            : 'Add User';
    return FormDialog(
      title: title,
      subtitle: _isApprove
          ? 'Grants access to ${_request!.email}'
          : _isEdit
              ? _existing!.email
              : 'Creates a sign-in for a new team member',
      icon: Icons.group_outlined,
      submitLabel: _isApprove ? 'Grant Access' : 'Save',
      onSubmit: _submit,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FormSection(
              title: 'Account',
              icon: Icons.badge_outlined,
              description: 'Who this person is and how they sign in.',
              first: true,
              children: [
                AppTextField(
                  label: 'Full Name',
                  controller: _name,
                  isRequired: true,
                  validator: (v) => Validators.required(v, field: 'Name'),
                ),
                FormRow([
                  AppTextField(
                    label: 'Login ID',
                    controller: _loginId,
                    isRequired: true,
                    helper: 'Username the person types to sign in.',
                    validator: (v) =>
                        Validators.required(v, field: 'Login ID'),
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
                if (_isCreate)
                  AppTextField(
                    label: 'Temporary Password',
                    controller: _password,
                    isRequired: true,
                    obscureText: true,
                    helper: 'They can change it after signing in.',
                    validator: Validators.password,
                  ),
              ],
            ),
            FormSection(
              title: 'Role & businesses',
              icon: Icons.business_outlined,
              description:
                  'The role sets the defaults; businesses limit what they see.',
              children: [
                AppDropdown<UserRole>(
                  label: 'Role',
                  isRequired: true,
                  value: _role,
                  // Owner is never assignable from this screen.
                  items: const [UserRole.admin, UserRole.user],
                  itemLabel: (r) => r.label,
                  helper: 'Admins can do more by default than Users.',
                  onChanged: (v) => setState(() => _role = v ?? _role),
                ),
                LabeledField(
                  label: 'Assigned Businesses',
                  helper: 'Which businesses this user can access.',
                  child: widget.businesses.isEmpty
                      ? Text('No businesses available.',
                          style: TextStyle(
                              fontSize: 12, color: t.textTertiary))
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
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
                            const SizedBox(height: AppSpacing.xs),
                            Row(
                              children: [
                                TextButton(
                                  onPressed: () => setState(() => _assigned = {
                                        for (final b in widget.businesses)
                                          b.id,
                                      }),
                                  child: const Text('Select all'),
                                ),
                                TextButton(
                                  onPressed: _assigned.isEmpty
                                      ? null
                                      : () =>
                                          setState(() => _assigned = <String>{}),
                                  child: const Text('Clear'),
                                ),
                              ],
                            ),
                          ],
                        ),
                ),
              ],
            ),
            FormSection(
              title: 'Permissions',
              icon: Icons.tune,
              description: 'Switch capabilities on or off on top of the role '
                  'defaults. ${effective.length} in effect'
                  '${overrides == 0 ? '' : ' · $overrides overridden'}.',
              children: [
                for (final (name, perms) in _groups)
                  LabeledField(
                    label: name,
                    child: Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        for (final p in perms)
                          FilterChip(
                            label: Text(_permLabels[p] ?? p.name),
                            selected: effective.contains(p),
                            onSelected: (sel) =>
                                setState(() => _togglePermission(p, sel)),
                          ),
                      ],
                    ),
                  ),
                if (overrides > 0)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => setState(() {
                        _granted.clear();
                        _revoked.clear();
                      }),
                      icon: const Icon(Icons.restart_alt, size: 18),
                      label: const Text('Reset to role defaults'),
                    ),
                  ),
              ],
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
          await widget.repo.saveUserProfile(
            created.copyWith(
              grantedPermissions: _granted,
              revokedPermissions: _revoked,
            ),
            previous: created,
          );
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
        await widget.repo.saveUserProfile(
          _existing!.copyWith(
            loginId: _loginId.text.trim(),
            name: _name.text.trim(),
            role: _role,
            assignedBusinessIds: _assigned.toList(),
            grantedPermissions: _granted,
            revokedPermissions: _revoked,
          ),
          previous: _existing,
        );
      }
      return true;
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
      return false;
    }
  }
}
