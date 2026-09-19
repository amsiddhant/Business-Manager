import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:universal_html/html.dart' as html;

import '../../core/permissions.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/validators.dart';
import '../../models/firebase_config.dart';
import '../../state/app_state.dart';
import '../../state/data_controller.dart';
import '../../widgets/common/app_card.dart';
import '../../widgets/common/confirm_dialog.dart';
import '../../widgets/common/page_header.dart';
import '../../widgets/common/status_badge.dart';
import '../../widgets/forms/form_dialog.dart';
import '../../widgets/forms/form_fields.dart';

/// Application settings: general preferences, the Firebase setup wizard,
/// connection status, profile/password management and demo-data reset.
///
/// Firebase configuration handled here is limited to *public* client
/// configuration values (apiKey/authDomain/projectId/…). Service-account keys,
/// admin credentials and other secrets are never entered or stored.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final user = appState.currentUser;
    final canConfigureFirebase = user?.can(Permission.configureFirebase) ?? false;
    final canManageSettings = user?.can(Permission.manageSettings) ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeader(
          title: 'Settings',
          subtitle: 'Preferences, Firebase configuration and your profile',
        ),
        const SizedBox(height: AppSpacing.lg),
        if (canManageSettings) ...[
          _GeneralSettingsCard(appState: appState),
          const SizedBox(height: AppSpacing.lg),
        ],
        if (canConfigureFirebase) ...[
          _FirebaseCard(appState: appState),
          const SizedBox(height: AppSpacing.lg),
        ],
        const _ProfileCard(),
        if (canManageSettings) ...[
          const SizedBox(height: AppSpacing.lg),
          _DangerZoneCard(appState: appState),
        ],
      ],
    );
  }
}

// ---- General ----------------------------------------------------------------

class _GeneralSettingsCard extends StatefulWidget {
  const _GeneralSettingsCard({required this.appState});
  final AppState appState;

  @override
  State<_GeneralSettingsCard> createState() => _GeneralSettingsCardState();
}

class _GeneralSettingsCardState extends State<_GeneralSettingsCard> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _appName;
  late String _dateFormat;
  bool _saving = false;

  static const _dateFormats = [
    'dd-MMM-yyyy',
    'dd/MM/yyyy',
    'MM/dd/yyyy',
    'yyyy-MM-dd',
  ];

  @override
  void initState() {
    super.initState();
    _appName = TextEditingController(text: widget.appState.appName);
    _dateFormat = widget.appState.dateFormat;
    if (!_dateFormats.contains(_dateFormat)) _dateFormat = _dateFormats.first;
  }

  @override
  void dispose() {
    _appName.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      await widget.appState.setAppName(_appName.text);
      await widget.appState.setDateFormat(_dateFormat);
      if (mounted) showSuccessSnack(context, 'Preferences saved');
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'General',
      subtitle: 'Application name and formatting preferences',
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FormRow([
              AppTextField(
                label: 'Application Name',
                controller: _appName,
                isRequired: true,
                validator: (v) =>
                    Validators.required(v, field: 'Application name'),
              ),
              AppDropdown<String>(
                label: 'Date Format',
                value: _dateFormat,
                items: _dateFormats,
                itemLabel: (f) => f,
                onChanged: (v) => setState(() => _dateFormat = v ?? _dateFormat),
              ),
            ]),
            const SizedBox(height: AppSpacing.lg),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined, size: 18),
                label: const Text('Save Preferences'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---- Firebase ---------------------------------------------------------------

class _FirebaseCard extends StatelessWidget {
  const _FirebaseCard({required this.appState});
  final AppState appState;

  @override
  Widget build(BuildContext context) {
    final isFirebase = appState.isFirebaseMode;
    return SectionCard(
      title: 'Firebase',
      subtitle: 'Connect your own Firebase project',
      trailing: StatusBadge(
        label: isFirebase ? 'Connected' : 'Demo mode',
        tone: isFirebase ? BadgeTone.success : BadgeTone.warning,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: isFirebase
                  ? AppColors.successSurface
                  : AppColors.warningSurface,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Row(
              children: [
                Icon(
                  isFirebase ? Icons.cloud_done : Icons.cloud_off,
                  size: 20,
                  color: isFirebase ? AppColors.success : AppColors.warning,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    isFirebase
                        ? 'The app is running against your configured Firebase '
                            'project. Data is stored in Firestore.'
                        : 'The app is running on built-in demo data stored in '
                            'this browser. Configure Firebase to go live.',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          const Text(
            'Only public client configuration values are stored (apiKey, '
            'authDomain, projectId, …). Never enter service-account keys or '
            'other secrets here.',
            style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: () => _openWizard(context),
                icon: const Icon(Icons.settings_suggest_outlined, size: 18),
                label: Text(isFirebase ? 'Reconfigure' : 'Set up Firebase'),
              ),
              const SizedBox(width: AppSpacing.sm),
              if (isFirebase)
                OutlinedButton.icon(
                  onPressed: () => _deactivate(context),
                  icon: const Icon(Icons.link_off, size: 18),
                  label: const Text('Switch to demo'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openWizard(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _FirebaseWizardDialog(appState: appState),
    );
  }

  Future<void> _deactivate(BuildContext context) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Switch to demo mode?',
      message: 'This clears your saved Firebase configuration and reverts to '
          'local demo data. You will be signed out.',
      confirmLabel: 'Switch',
      destructive: true,
    );
    if (ok != true) return;
    try {
      await appState.deactivateFirebase();
      if (context.mounted) showSuccessSnack(context, 'Reverted to demo mode');
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e);
    }
  }
}

/// Multi-step Firebase setup wizard. Steps 1–4 are guidance; step 5 collects
/// the public config, tests the connection, then activates it.
class _FirebaseWizardDialog extends StatefulWidget {
  const _FirebaseWizardDialog({required this.appState});
  final AppState appState;

  @override
  State<_FirebaseWizardDialog> createState() => _FirebaseWizardDialogState();
}

class _FirebaseWizardDialogState extends State<_FirebaseWizardDialog> {
  static const _console = 'https://console.firebase.google.com/';

  int _step = 0;
  bool _busy = false;
  String? _testResult; // null = untested; '' = ok; else error text
  bool _testOk = false;

  final _formKey = GlobalKey<FormState>();
  final _apiKey = TextEditingController();
  final _authDomain = TextEditingController();
  final _projectId = TextEditingController();
  final _storageBucket = TextEditingController();
  final _messagingSenderId = TextEditingController();
  final _appId = TextEditingController();
  final _measurementId = TextEditingController();
  final _databaseURL = TextEditingController();

  @override
  void initState() {
    super.initState();
    final existing = widget.appState.configStore.firebaseConfig;
    if (existing != null) {
      _apiKey.text = existing.apiKey;
      _authDomain.text = existing.authDomain;
      _projectId.text = existing.projectId;
      _storageBucket.text = existing.storageBucket;
      _messagingSenderId.text = existing.messagingSenderId;
      _appId.text = existing.appId;
      _measurementId.text = existing.measurementId;
      _databaseURL.text = existing.databaseURL;
    }
  }

  @override
  void dispose() {
    _apiKey.dispose();
    _authDomain.dispose();
    _projectId.dispose();
    _storageBucket.dispose();
    _messagingSenderId.dispose();
    _appId.dispose();
    _measurementId.dispose();
    _databaseURL.dispose();
    super.dispose();
  }

  FirebaseConfig _buildConfig() => FirebaseConfig(
        apiKey: _apiKey.text.trim(),
        authDomain: _authDomain.text.trim(),
        projectId: _projectId.text.trim(),
        storageBucket: _storageBucket.text.trim(),
        messagingSenderId: _messagingSenderId.text.trim(),
        appId: _appId.text.trim(),
        measurementId: _measurementId.text.trim(),
        databaseURL: _databaseURL.text.trim(),
      );

  static const _steps = [
    _WizardStepInfo(
      title: 'Create a Firebase project',
      icon: Icons.add_box_outlined,
      points: [
        'Open the Firebase Console.',
        'Click "Add project" and give it a name.',
        'Continue through the setup steps to finish.',
      ],
    ),
    _WizardStepInfo(
      title: 'Enable Authentication',
      icon: Icons.lock_outline,
      points: [
        'In the console, open Build → Authentication.',
        'Click "Get started".',
        'Enable the Email/Password sign-in provider and save.',
      ],
    ),
    _WizardStepInfo(
      title: 'Create the Firestore database',
      icon: Icons.storage_outlined,
      points: [
        'Open Build → Firestore Database.',
        'Click "Create database" and pick a region.',
        'Start in production mode, then deploy the security rules from the '
            'README.',
      ],
    ),
    _WizardStepInfo(
      title: 'Register a Web App',
      icon: Icons.web_outlined,
      points: [
        'Open Project settings → your apps.',
        'Add a Web app (</> icon) and register it.',
        'Copy the firebaseConfig object shown — you will paste the values '
            'in the next step.',
      ],
    ),
  ];

  bool get _isFinalStep => _step == _steps.length; // step index 4 == form

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radius)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.local_fire_department,
                      color: AppColors.primary),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Firebase Setup — Step ${_step + 1} of ${_steps.length + 1}',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed:
                        _busy ? null : () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              _StepProgress(current: _step, total: _steps.length + 1),
              const SizedBox(height: AppSpacing.lg),
              Flexible(
                child: SingleChildScrollView(
                  child: _isFinalStep ? _buildForm() : _buildInfoStep(),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              _buildActions(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoStep() {
    final info = _steps[_step];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(info.icon, color: AppColors.primary, size: 22),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(info.title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        for (var i = 0; i < info.points.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: AppColors.primarySurface,
                    shape: BoxShape.circle,
                  ),
                  child: Text('${i + 1}',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary)),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(info.points[i])),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          onPressed: () => html.window.open(_console, '_blank'),
          icon: const Icon(Icons.open_in_new, size: 18),
          label: const Text('Open Firebase Console'),
        ),
      ],
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Configure Application',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'Paste the values from your Web app\'s firebaseConfig.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const FormGap(),
          AppTextField(
            label: 'API Key',
            controller: _apiKey,
            isRequired: true,
            validator: (v) => Validators.required(v, field: 'API key'),
          ),
          const FormGap(),
          FormRow([
            AppTextField(
              label: 'Auth Domain',
              controller: _authDomain,
              isRequired: true,
              hintText: 'my-app.firebaseapp.com',
              validator: (v) => Validators.required(v, field: 'Auth domain'),
            ),
            AppTextField(
              label: 'Project ID',
              controller: _projectId,
              isRequired: true,
              validator: (v) => Validators.required(v, field: 'Project ID'),
            ),
          ]),
          const FormGap(),
          FormRow([
            AppTextField(
              label: 'Storage Bucket',
              controller: _storageBucket,
              hintText: 'my-app.appspot.com',
            ),
            AppTextField(
              label: 'Messaging Sender ID',
              controller: _messagingSenderId,
              isRequired: true,
              validator: (v) =>
                  Validators.required(v, field: 'Messaging sender ID'),
            ),
          ]),
          const FormGap(),
          FormRow([
            AppTextField(
              label: 'App ID',
              controller: _appId,
              isRequired: true,
              validator: (v) => Validators.required(v, field: 'App ID'),
            ),
            AppTextField(
              label: 'Measurement ID',
              controller: _measurementId,
              hintText: 'Optional',
            ),
          ]),
          const FormGap(),
          AppTextField(
            label: 'Realtime Database URL',
            controller: _databaseURL,
            hintText: 'Optional — https://<project>-default-rtdb.firebaseio.com',
          ),
          if (_testResult != null) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color:
                    _testOk ? AppColors.successSurface : AppColors.errorSurface,
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: Row(
                children: [
                  Icon(
                    _testOk ? Icons.check_circle : Icons.error_outline,
                    size: 18,
                    color: _testOk ? AppColors.success : AppColors.error,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      _testOk
                          ? 'Connection successful. You can save now.'
                          : 'Connection failed: $_testResult',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    return Row(
      children: [
        if (_step > 0)
          TextButton(
            onPressed: _busy ? null : () => setState(() => _step--),
            child: const Text('Back'),
          ),
        const Spacer(),
        if (!_isFinalStep)
          ElevatedButton(
            onPressed: () => setState(() => _step++),
            child: const Text('Next'),
          )
        else ...[
          OutlinedButton.icon(
            onPressed: _busy ? null : _test,
            icon: _busy && !_testOk
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.wifi_tethering, size: 18),
            label: const Text('Test Connection'),
          ),
          const SizedBox(width: AppSpacing.sm),
          ElevatedButton.icon(
            onPressed: (_busy || !_testOk) ? null : _saveAndActivate,
            icon: const Icon(Icons.save, size: 18),
            label: const Text('Save & Activate'),
          ),
        ],
      ],
    );
  }

  Future<void> _test() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _testResult = null;
      _testOk = false;
    });
    try {
      await widget.appState.testFirebaseConfig(_buildConfig());
      setState(() {
        _testOk = true;
        _testResult = '';
      });
    } catch (e) {
      setState(() {
        _testOk = false;
        _testResult = e.toString();
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveAndActivate() async {
    setState(() => _busy = true);
    try {
      await widget.appState.activateFirebase(_buildConfig());
      if (mounted) {
        Navigator.of(context).pop();
        showSuccessSnack(context,
            'Firebase connected. Please sign in with your Firebase account.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showErrorSnack(context, e);
      }
    }
  }
}

class _WizardStepInfo {
  const _WizardStepInfo(
      {required this.title, required this.icon, required this.points});
  final String title;
  final IconData icon;
  final List<String> points;
}

class _StepProgress extends StatelessWidget {
  const _StepProgress({required this.current, required this.total});
  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < total; i++) ...[
          Expanded(
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                color: i <= current ? AppColors.primary : AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          if (i < total - 1) const SizedBox(width: 4),
        ],
      ],
    );
  }
}

// ---- Profile ----------------------------------------------------------------

class _ProfileCard extends StatelessWidget {
  const _ProfileCard();

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final user = appState.currentUser;
    if (user == null) return const SizedBox.shrink();

    return SectionCard(
      title: 'Profile',
      subtitle: 'Your account details',
      trailing: StatusBadge.role(user.role),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ProfileRow(label: 'Name', value: user.name),
          _ProfileRow(label: 'Login ID', value: user.loginId),
          _ProfileRow(label: 'Email', value: user.email),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: () => _changePassword(context, appState),
            icon: const Icon(Icons.password, size: 18),
            label: const Text('Change Password'),
          ),
        ],
      ),
    );
  }

  Future<void> _changePassword(
      BuildContext context, AppState appState) async {
    await showDialog<bool>(
      context: context,
      builder: (_) => _ChangePasswordDialog(appState: appState),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
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

// ---- Danger zone ------------------------------------------------------------

class _DangerZoneCard extends StatelessWidget {
  const _DangerZoneCard({required this.appState});
  final AppState appState;

  @override
  Widget build(BuildContext context) {
    // Demo reset only makes sense while running on the local demo backend.
    if (appState.isFirebaseMode) return const SizedBox.shrink();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: AppColors.warning, size: 20),
              SizedBox(width: AppSpacing.sm),
              Text('Demo Data',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'Reset all demo data back to the original seed. This clears any '
            'changes you have made in demo mode.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
            onPressed: () => _reset(context),
            icon: const Icon(Icons.restart_alt, size: 18),
            label: const Text('Reset Demo Data'),
          ),
        ],
      ),
    );
  }

  Future<void> _reset(BuildContext context) async {
    final data = context.read<DataController>();
    final ok = await showConfirmDialog(
      context,
      title: 'Reset demo data?',
      message: 'This restores the original demo dataset and signs you out. '
          'Any changes made in demo mode will be lost.',
      confirmLabel: 'Reset',
      destructive: true,
    );
    if (ok != true) return;
    try {
      await appState.resetDemoData();
      data.clear();
      if (context.mounted) showSuccessSnack(context, 'Demo data reset');
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e);
    }
  }
}
