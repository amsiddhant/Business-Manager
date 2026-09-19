import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/app_exception.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/validators.dart';
import '../../data/demo_seed.dart';
import '../../state/app_state.dart';
import '../../widgets/common/responsive.dart';
import '../../widgets/forms/form_fields.dart';

/// The sign-in screen. Presents a branded split layout on desktop and a single
/// centered card on smaller screens.
///
/// Google Sign-In is the primary authentication method. In demo mode the
/// classic username/password form and one-tap demo credentials remain available
/// so the product is immediately explorable without a Google account.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _loginController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscure = true;
  bool _submitting = false;
  bool _googleSubmitting = false;
  String? _error;

  @override
  void dispose() {
    _loginController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);
    final appState = context.read<AppState>();
    try {
      await appState.signIn(
        _loginController.text.trim(),
        _passwordController.text,
      );
      // Navigation is handled by the router's auth redirect.
    } catch (e) {
      if (mounted) {
        setState(() => _error = ErrorMapper.friendly(e));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    if (_googleSubmitting) return;
    setState(() {
      _error = null;
      _googleSubmitting = true;
    });
    final appState = context.read<AppState>();
    try {
      await appState.signInWithGoogle();
      // Navigation is handled by the router's auth redirect.
    } catch (e) {
      if (mounted) setState(() => _error = ErrorMapper.friendly(e));
    } finally {
      if (mounted) setState(() => _googleSubmitting = false);
    }
  }

  void _fillDemo(String login) {
    _loginController.text = login;
    _passwordController.text = DemoSeed.password;
    setState(() => _error = null);
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);
    final appState = context.watch<AppState>();

    final card = _LoginCard(
      formKey: _formKey,
      loginController: _loginController,
      passwordController: _passwordController,
      obscure: _obscure,
      onToggleObscure: () => setState(() => _obscure = !_obscure),
      submitting: _submitting,
      googleSubmitting: _googleSubmitting,
      error: _error ?? appState.authError,
      onSubmit: _submit,
      onGoogle: _signInWithGoogle,
      onForgot: () => context.push(Routes.forgotPassword),
      isDemoMode: !appState.isFirebaseMode,
      onFillDemo: _fillDemo,
      appName: appState.appName,
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      body: isDesktop
          ? Row(
              children: [
                const Expanded(flex: 5, child: _BrandPanel()),
                Expanded(
                  flex: 4,
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(AppSpacing.xxl),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 400),
                        child: card,
                      ),
                    ),
                  ),
                ),
              ],
            )
          : Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: card,
                ),
              ),
            ),
    );
  }
}

/// The marketing/brand panel shown on the left on desktop.
class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.primaryDark],
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.xxl * 1.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: const Icon(Icons.insights, color: Colors.white, size: 26),
              ),
              const SizedBox(width: AppSpacing.md),
              const Text(
                'Salesforce Business Manager',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxl * 1.5),
          const Text(
            'Track profitability\nacross every business.',
            style: TextStyle(
                color: Colors.white,
                fontSize: 34,
                height: 1.2,
                fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Revenue, costs, marketing spend and net profit — '
            'calculated in real time, by financial year, for all your products.',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 16,
                height: 1.5),
          ),
          const SizedBox(height: AppSpacing.xxl),
          const _FeatureRow(
              icon: Icons.trending_up, text: 'Live profit & margin analytics'),
          const SizedBox(height: AppSpacing.md),
          const _FeatureRow(
              icon: Icons.pie_chart_outline,
              text: 'Expense breakdown & recurring cost proration'),
          const SizedBox(height: AppSpacing.md),
          const _FeatureRow(
              icon: Icons.verified_user_outlined,
              text: 'Role-based access for your whole team'),
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Colors.white, size: 20),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(text,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9), fontSize: 14.5)),
        ),
      ],
    );
  }
}

class _LoginCard extends StatelessWidget {
  const _LoginCard({
    required this.formKey,
    required this.loginController,
    required this.passwordController,
    required this.obscure,
    required this.onToggleObscure,
    required this.submitting,
    required this.googleSubmitting,
    required this.error,
    required this.onSubmit,
    required this.onGoogle,
    required this.onForgot,
    required this.isDemoMode,
    required this.onFillDemo,
    required this.appName,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController loginController;
  final TextEditingController passwordController;
  final bool obscure;
  final VoidCallback onToggleObscure;
  final bool submitting;
  final bool googleSubmitting;
  final String? error;
  final VoidCallback onSubmit;
  final VoidCallback onGoogle;
  final VoidCallback onForgot;
  final bool isDemoMode;
  final ValueChanged<String> onFillDemo;
  final String appName;

  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);
    final busy = submitting || googleSubmitting;
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!isDesktop) ...[
            Center(
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.primaryDark],
                  ),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child:
                    const Icon(Icons.insights, color: Colors.white, size: 26),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          Text('Welcome back',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text('Sign in to your account to continue.',
              style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: AppSpacing.xl),
          if (error != null) ...[
            _ErrorBanner(message: error!),
            const SizedBox(height: AppSpacing.lg),
          ],
          // Primary sign-in: Google.
          _GoogleButton(
            loading: googleSubmitting,
            onPressed: busy ? null : onGoogle,
          ),
          if (isDemoMode) ...[
            const SizedBox(height: AppSpacing.lg),
            const _OrDivider(),
            const SizedBox(height: AppSpacing.lg),
            AppTextField(
              label: 'Username or Email',
              controller: loginController,
              isRequired: true,
              hintText: 'e.g. owner',
              keyboardType: TextInputType.text,
              validator: (v) =>
                  Validators.required(v, field: 'Username or email'),
              onChanged: (_) {},
            ),
            const SizedBox(height: AppSpacing.lg),
            AppTextField(
              label: 'Password',
              controller: passwordController,
              isRequired: true,
              obscureText: obscure,
              hintText: '••••••••',
              validator: (v) => Validators.required(v, field: 'Password'),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onForgot,
                child: const Text('Forgot password?'),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: busy ? null : onSubmit,
                child: submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.white),
                      )
                    : const Text('Sign in'),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            const _DemoCredentials(),
          ] else ...[
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Access is managed by your organization. The first person to sign '
              'in sets up the workspace as Owner; everyone else is invited by '
              'the Owner from the Users screen.',
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 12.5, height: 1.5),
            ),
          ],
        ],
      ),
    );
  }
}

/// A branded "Continue with Google" button (Google's multicolour "G" glyph).
class _GoogleButton extends StatelessWidget {
  const _GoogleButton({required this.loading, required this.onPressed});
  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          backgroundColor: Colors.white,
          side: const BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
        ),
        child: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const _GoogleGlyph(),
                  const SizedBox(width: AppSpacing.md),
                  Text('Continue with Google',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                ],
              ),
      ),
    );
  }
}

/// Google's four-colour "G" rendered with painters so no image asset is needed.
class _GoogleGlyph extends StatelessWidget {
  const _GoogleGlyph();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 18,
      height: 18,
      child: CustomPaint(painter: _GoogleGPainter()),
    );
  }
}

class _GoogleGPainter extends CustomPainter {
  const _GoogleGPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final stroke = size.width * 0.22;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;
    final arcRect = rect.deflate(stroke / 2);

    // Four coloured arcs approximating the Google "G".
    void arc(double startDeg, double sweepDeg, Color color) {
      paint.color = color;
      canvas.drawArc(arcRect, startDeg * 3.1415926 / 180,
          sweepDeg * 3.1415926 / 180, false, paint);
    }

    arc(-30, -120, const Color(0xFF4285F4)); // blue (right)
    arc(-150, -60, const Color(0xFFFBBC05)); // yellow (bottom-left)
    arc(150, -60, const Color(0xFF34A853)); // green (bottom-right)
    arc(90, 60, const Color(0xFFEA4335)); // red (top-left)

    // The horizontal bar of the "G".
    final barPaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.fill;
    canvas.drawRect(
      Rect.fromLTWH(size.width * 0.5, size.height * 0.42, size.width * 0.5 - stroke / 2,
          stroke),
      barPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider(color: AppColors.border)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Text('or',
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500)),
        ),
        const Expanded(child: Divider(color: AppColors.border)),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.errorSurface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(message,
                style: const TextStyle(color: AppColors.error, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

/// Shows the three demo logins with one-tap fill (local demo mode only).
class _DemoCredentials extends StatelessWidget {
  const _DemoCredentials();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.science_outlined,
                  size: 18, color: AppColors.textSecondary),
              const SizedBox(width: AppSpacing.sm),
              Text('Demo mode',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Tap a role to fill credentials (password: ${DemoSeed.password}).',
            style:
                const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: const [
              _DemoChip(label: 'Owner', login: DemoSeed.ownerLogin),
              _DemoChip(label: 'Admin', login: DemoSeed.adminLogin),
              _DemoChip(label: 'User', login: DemoSeed.userLogin),
            ],
          ),
        ],
      ),
    );
  }
}

class _DemoChip extends StatelessWidget {
  const _DemoChip({required this.label, required this.login});
  final String label;
  final String login;

  @override
  Widget build(BuildContext context) {
    final state = context.findAncestorStateOfType<_LoginScreenState>();
    return ActionChip(
      avatar: const Icon(Icons.person_outline, size: 16),
      label: Text('$label · $login'),
      onPressed: () => state?._fillDemo(login),
    );
  }
}
