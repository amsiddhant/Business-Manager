import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/app_exception.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_x.dart';
import '../../core/validators.dart';
import '../../state/app_state.dart';
import '../../state/user_prefs.dart';
import '../../widgets/forms/form_fields.dart';
import '../../widgets/layout/theme_toggle_button.dart';

/// Password reset request screen. Sends a reset email for the resolved account.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();

  bool _submitting = false;
  bool _sent = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller.text = context.read<UserPrefs>().lastLoginId ?? '';
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _back() =>
      context.canPop() ? context.pop() : context.go(Routes.login);

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);
    try {
      await context.read<AppState>().sendPasswordReset(_controller.text.trim());
      if (mounted) setState(() => _sent = true);
    } catch (e) {
      if (mounted) setState(() => _error = ErrorMapper.friendly(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final motion = context.motion;
    return Scaffold(
      backgroundColor: t.background,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Container(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    decoration: BoxDecoration(
                      color: t.card,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                      border: Border.all(color: t.border),
                      boxShadow: t.cardShadow,
                    ),
                    child: AnimatedSwitcher(
                      duration: motion.base,
                      child: _sent ? _buildSent(context) : _buildForm(context),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: AppSpacing.sm,
              left: AppSpacing.sm,
              child: TextButton.icon(
                onPressed: _back,
                icon: const Icon(Icons.arrow_back, size: 18),
                label: const Text('Back to sign in'),
              ),
            ),
            const Positioned(
              top: AppSpacing.sm,
              right: AppSpacing.sm,
              child: ThemeToggleButton(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _icon(IconData icon, Color fg, Color bg) => Center(
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
          child: Icon(icon, color: fg, size: 26),
        ),
      );

  Widget _buildForm(BuildContext context) {
    final t = context.tokens;
    return Form(
      key: _formKey,
      child: Column(
        key: const ValueKey('form'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _icon(Icons.lock_reset, t.primary, t.primaryLight),
          const SizedBox(height: AppSpacing.lg),
          Text('Reset your password',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3)),
          const SizedBox(height: 6),
          Text(
            'Enter your username or email and we’ll send you a link to reset '
            'your password.',
            textAlign: TextAlign.center,
            style: TextStyle(color: t.textSecondary, height: 1.45),
          ),
          const SizedBox(height: AppSpacing.xl),
          if (_error != null) ...[
            _InlineError(message: _error!),
            const SizedBox(height: AppSpacing.lg),
          ],
          AppTextField(
            label: 'Username or Email',
            controller: _controller,
            isRequired: true,
            autofocus: true,
            textInputAction: TextInputAction.send,
            autofillHints: const [AutofillHints.username],
            prefixIcon: const Icon(Icons.person_outline, size: 20),
            onFieldSubmitted: (_) => _submit(),
            validator: (v) =>
                Validators.required(v, field: 'Username or email'),
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            height: 48,
            child: FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: t.textOnPrimary),
                    )
                  : const Text('Send reset link'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSent(BuildContext context) {
    final t = context.tokens;
    return Column(
      key: const ValueKey('sent'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _icon(Icons.mark_email_read_outlined, t.success, t.successSurface),
        const SizedBox(height: AppSpacing.lg),
        Text('Check your email',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'If an account exists for that identifier, a password reset link is '
          'on its way. Follow the link in the email to set a new password.',
          textAlign: TextAlign.center,
          style: TextStyle(color: t.textSecondary, height: 1.45),
        ),
        const SizedBox(height: AppSpacing.xl),
        SizedBox(
          height: 48,
          child: FilledButton(
            onPressed: _back,
            child: const Text('Back to sign in'),
          ),
        ),
      ],
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: context.tokens.errorSurface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          border:
              Border.all(color: context.tokens.error.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: context.tokens.error, size: 20),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(message,
                  style: TextStyle(color: context.tokens.error, fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }
}
