import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_exception.dart';
import '../../core/validators.dart';
import '../../state/app_state.dart';
import '../../widgets/forms/form_dialog.dart';
import '../../widgets/forms/form_fields.dart';

/// A dialog to change the signed-in user's password. Returns true on success.
class ChangePasswordDialog extends StatefulWidget {
  const ChangePasswordDialog({super.key});

  /// Shows the dialog and returns true if the password was changed.
  static Future<bool?> show(BuildContext context) =>
      showDialog<bool>(
        context: context,
        builder: (_) => const ChangePasswordDialog(),
      );

  @override
  State<ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FormDialog(
      title: 'Change password',
      submitLabel: 'Update password',
      width: 460,
      onSubmit: _submit,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(
              label: 'Current password',
              controller: _currentController,
              isRequired: true,
              obscureText: true,
              validator: (v) =>
                  Validators.required(v, field: 'Current password'),
            ),
            const FormGap(),
            AppTextField(
              label: 'New password',
              controller: _newController,
              isRequired: true,
              obscureText: true,
              helper: 'At least 6 characters.',
              validator: Validators.password,
            ),
            const FormGap(),
            AppTextField(
              label: 'Confirm new password',
              controller: _confirmController,
              isRequired: true,
              obscureText: true,
              validator: (v) {
                if (v == null || v.isEmpty) return 'Please confirm the password';
                if (v != _newController.text) return 'Passwords do not match';
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _submit() async {
    if (!_formKey.currentState!.validate()) return false;
    final appState = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await appState.changePassword(
        _currentController.text,
        _newController.text,
      );
      messenger.showSnackBar(
        const SnackBar(content: Text('Password updated successfully.')),
      );
      return true;
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(ErrorMapper.friendly(e))),
      );
      return false;
    }
  }
}
