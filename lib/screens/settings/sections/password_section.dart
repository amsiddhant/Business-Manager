import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/validators.dart';
import '../../../state/app_state.dart';
import '../../../widgets/common/confirm_dialog.dart';
import '../../../widgets/forms/form_dialog.dart';
import '../../../widgets/forms/form_fields.dart';
import '../settings_widgets.dart';

/// Change your own password.
class PasswordSection extends StatelessWidget {
  const PasswordSection({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    return SettingsPanel(
      title: 'Password',
      subtitle: 'Keep your account safe',
      children: [
        SettingsCard(
          title: 'Change password',
          subtitle: 'You will need your current password.',
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => showDialog<bool>(
                  context: context,
                  builder: (_) => _ChangePasswordDialog(appState: appState),
                ),
                icon: const Icon(Icons.password, size: 18),
                label: const Text('Change Password'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog({required this.appState});
  final AppState appState;

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FormDialog(
      title: 'Change Password',
      submitLabel: 'Update',
      onSubmit: _submit,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppTextField(
              label: 'Current Password',
              controller: _current,
              isRequired: true,
              obscureText: true,
              validator: (v) => Validators.required(v, field: 'Current password'),
            ),
            const FormGap(),
            AppTextField(
              label: 'New Password',
              controller: _next,
              isRequired: true,
              obscureText: true,
              validator: Validators.password,
            ),
            const FormGap(),
            AppTextField(
              label: 'Confirm New Password',
              controller: _confirm,
              isRequired: true,
              obscureText: true,
              validator: (v) =>
                  v != _next.text ? 'Passwords do not match' : null,
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return false;
    try {
      await widget.appState.changePassword(_current.text, _next.text);
      if (mounted) showSuccessSnack(context, 'Password updated');
      return true;
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
      return false;
    }
  }
}
