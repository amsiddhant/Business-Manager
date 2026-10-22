import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/app_exception.dart';
import '../../core/app_info.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_x.dart';
import '../../core/validators.dart';
import '../../data/demo_seed.dart';
import '../../state/app_state.dart';
import '../../state/org_settings.dart';
import '../../state/user_prefs.dart';
import '../../widgets/common/org_logo.dart';
import '../../widgets/common/responsive.dart';
import '../../widgets/forms/form_fields.dart';
import '../../widgets/layout/theme_toggle_button.dart';

/// The sign-in screen: a brand panel beside the form on desktop, and the form
/// on its own (with the brand mark above it) on smaller screens.
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
  final _passwordFocus = FocusNode();

  bool _obscure = true;
  bool _submitting = false;
  bool _googleSubmitting = false;
  bool _remember = true;
  bool _capsLock = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final last = context.read<UserPrefs>().lastLoginId;
    if (last != null && last.isNotEmpty) _loginController.text = last;
    _capsLock = _capsOn();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _loginController.dispose();
    _passwordController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  static bool _capsOn() => HardwareKeyboard.instance.lockModesEnabled
      .contains(KeyboardLockMode.capsLock);

  /// Keeps the Caps Lock hint current; never consumes the key.
  bool _onKey(KeyEvent _) {
    final on = _capsOn();
    if (on != _capsLock && mounted) setState(() => _capsLock = on);
    return false;
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);
    final appState = context.read<AppState>();
    final prefs = context.read<UserPrefs>();
    final login = _loginController.text.trim();
    try {
      await appState.signIn(login, _passwordController.text);
      await prefs.setLastLoginId(_remember ? login : null);
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
    final t = context.tokens;
    final isDesktop = Responsive.isDesktop(context);
    final appState = context.watch<AppState>();
    final appName = appState.appName;

    final card = _LoginCard(
      formKey: _formKey,
      loginController: _loginController,
      passwordController: _passwordController,
      passwordFocus: _passwordFocus,
      obscure: _obscure,
      onToggleObscure: () => setState(() => _obscure = !_obscure),
      capsLock: _capsLock,
      remember: _remember,
      onRemember: (v) => setState(() => _remember = v),
      submitting: _submitting,
      googleSubmitting: _googleSubmitting,
      error: _error ?? appState.authError,
      onSubmit: _submit,
      onGoogle: _signInWithGoogle,
      onForgot: () => context.push(Routes.forgotPassword),
      isDemoMode: !appState.isFirebaseMode,
      onFillDemo: _fillDemo,
      appName: appName,
      showMark: !isDesktop,
    );

    final form = Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(isDesktop ? AppSpacing.xxl : AppSpacing.lg),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: isDesktop ? 400 : 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isDesktop)
                card
              else
                Container(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  decoration: BoxDecoration(
                    color: t.card,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                    border: Border.all(color: t.border),
                    boxShadow: t.cardShadow,
                  ),
                  child: card,
                ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                'Version $kAppVersion',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: t.textTertiary),
              ),
            ],
          ),
        ),
      ),
    );

    return Scaffold(
      backgroundColor: t.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (isDesktop)
            Row(
              children: [
                Expanded(flex: 5, child: _BrandPanel(appName: appName)),
                Expanded(flex: 4, child: form),
              ],
            )
          else
            form,
          const Positioned(
            top: AppSpacing.sm,
            right: AppSpacing.sm,
            child: SafeArea(child: ThemeToggleButton()),
          ),
        ],
      ),
    );
  }
}

/// The app's mark: a rounded square in the brand gradient.
class _BrandMark extends StatelessWidget {
  const _BrandMark({this.size = 44, this.onBrand = false});

  final double size;

  /// Drawn on the brand panel (a translucent tile instead of the gradient).
  final bool onBrand;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // The organisation's own logo, when it has one and shows it here.
    final showLogo = context.orgSettings((s) => s.branding.showLogoOnLogin) &&
        OrgLogo.has(context);
    if (showLogo) {
      return Container(
        height: size,
        constraints: BoxConstraints(maxWidth: size * 3),
        padding: onBrand ? const EdgeInsets.all(4) : EdgeInsets.zero,
        decoration: onBrand
            ? BoxDecoration(
                color: Colors.white.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(size * 0.28),
              )
            : null,
        child: OrgLogo(size: onBrand ? size - 8 : size, maxWidth: size * 3),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: onBrand ? t.textOnPrimary.withValues(alpha: 0.16) : null,
        gradient: onBrand
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [t.primary, t.primaryDark],
              ),
        borderRadius: BorderRadius.circular(size * 0.28),
        border: onBrand
            ? Border.all(color: t.textOnPrimary.withValues(alpha: 0.22))
            : null,
      ),
      child: Icon(Icons.insights, color: t.textOnPrimary, size: size * 0.56),
    );
  }
}

/// The brand panel shown on the left on desktop.
class _BrandPanel extends StatelessWidget {
  const _BrandPanel({required this.appName});

  final String appName;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final on = t.textOnPrimary;
    final tagline = context.orgSettings((s) => s.branding.tagline.trim());
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [t.primary, t.primaryDark],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: CustomPaint(painter: _BrandPattern(color: on)),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xxl * 1.5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const _BrandMark(onBrand: true),
                    const SizedBox(width: AppSpacing.md),
                    Flexible(
                      child: Text(
                        appName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: on,
                            fontSize: 18,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                if (tagline.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    tagline,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: on.withValues(alpha: 0.85), fontSize: 14),
                  ),
                ],
                const Spacer(),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Track profitability\nacross every business.',
                        style: TextStyle(
                            color: on,
                            fontSize: 38,
                            height: 1.15,
                            letterSpacing: -0.5,
                            fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        'Revenue, costs, marketing spend and net profit — '
                        'calculated in real time, by financial year, for all '
                        'your products.',
                        style: TextStyle(
                            color: on.withValues(alpha: 0.85),
                            fontSize: 16,
                            height: 1.5),
                      ),
                      const SizedBox(height: AppSpacing.xxl),
                      const _FeatureRow(
                          icon: Icons.trending_up,
                          text: 'Live profit & margin analytics'),
                      const SizedBox(height: AppSpacing.sm),
                      const _FeatureRow(
                          icon: Icons.pie_chart_outline,
                          text: 'Expense breakdown & recurring cost proration'),
                      const SizedBox(height: AppSpacing.sm),
                      const _FeatureRow(
                          icon: Icons.verified_user_outlined,
                          text: 'Role-based access for your whole team'),
                    ],
                  ),
                ),
                const Spacer(),
                Text(
                  'Secure sign-in · your data stays in your workspace',
                  style: TextStyle(color: on.withValues(alpha: 0.7), fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A quiet dot grid with two soft rings, fading towards the top left.
class _BrandPattern extends CustomPainter {
  const _BrandPattern({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const gap = 26.0;
    final dot = Paint()..style = PaintingStyle.fill;
    for (var y = gap / 2; y < size.height; y += gap) {
      for (var x = gap / 2; x < size.width; x += gap) {
        // Stronger towards the bottom right, so text stays clean.
        final f = ((x / size.width) + (y / size.height)) / 2;
        if (f < 0.35) continue;
        dot.color = color.withValues(alpha: 0.10 * (f - 0.35) / 0.65);
        canvas.drawCircle(Offset(x, y), 1.2, dot);
      }
    }
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final c = Offset(size.width * 0.95, size.height * 0.1);
    ring.color = color.withValues(alpha: 0.10);
    canvas.drawCircle(c, size.shortestSide * 0.32, ring);
    ring.color = color.withValues(alpha: 0.06);
    canvas.drawCircle(c, size.shortestSide * 0.5, ring);
  }

  @override
  bool shouldRepaint(_BrandPattern old) => old.color != color;
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final on = context.tokens.textOnPrimary;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
      decoration: BoxDecoration(
        color: on.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        border: Border.all(color: on.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: [
          Icon(icon, color: on, size: 20),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    color: on.withValues(alpha: 0.92), fontSize: 14.5)),
          ),
        ],
      ),
    );
  }
}

class _LoginCard extends StatelessWidget {
  const _LoginCard({
    required this.formKey,
    required this.loginController,
    required this.passwordController,
    required this.passwordFocus,
    required this.obscure,
    required this.onToggleObscure,
    required this.capsLock,
    required this.remember,
    required this.onRemember,
    required this.submitting,
    required this.googleSubmitting,
    required this.error,
    required this.onSubmit,
    required this.onGoogle,
    required this.onForgot,
    required this.isDemoMode,
    required this.onFillDemo,
    required this.appName,
    required this.showMark,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController loginController;
  final TextEditingController passwordController;
  final FocusNode passwordFocus;
  final bool obscure;
  final VoidCallback onToggleObscure;
  final bool capsLock;
  final bool remember;
  final ValueChanged<bool> onRemember;
  final bool submitting;
  final bool googleSubmitting;
  final String? error;
  final VoidCallback onSubmit;
  final VoidCallback onGoogle;
  final VoidCallback onForgot;
  final bool isDemoMode;
  final ValueChanged<String> onFillDemo;
  final String appName;
  final bool showMark;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final busy = submitting || googleSubmitting;
    return Form(
      key: formKey,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showMark) ...[
              Row(
                children: [
                  const _BrandMark(size: 40),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      appName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: t.textPrimary),
                    ),
                  ),
                ],
              ),
              if (context.orgSettings((s) => s.branding.tagline.trim()) case final tag
                  when tag.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(tag,
                    style: TextStyle(fontSize: 13, color: t.textSecondary)),
              ],
              const SizedBox(height: AppSpacing.xl),
            ],
            Text('Welcome back',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3)),
            const SizedBox(height: 6),
            Text('Sign in to your account to continue.',
                style: TextStyle(color: t.textSecondary)),
            const SizedBox(height: AppSpacing.xl),
            AnimatedSize(
              duration: context.motion.base,
              curve: AppMotion.standard,
              alignment: Alignment.topCenter,
              child: error == null
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                      child: _ErrorBanner(message: error!),
                    ),
            ),
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
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.username],
                prefixIcon: const Icon(Icons.person_outline, size: 20),
                onFieldSubmitted: (_) => passwordFocus.requestFocus(),
                validator: (v) =>
                    Validators.required(v, field: 'Username or email'),
                onChanged: (_) {},
              ),
              const SizedBox(height: AppSpacing.lg),
              AppTextField(
                label: 'Password',
                controller: passwordController,
                focusNode: passwordFocus,
                isRequired: true,
                obscureText: obscure,
                hintText: '••••••••',
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                prefixIcon: const Icon(Icons.lock_outline, size: 20),
                suffixIcon: IconButton(
                  tooltip: obscure ? 'Show password' : 'Hide password',
                  onPressed: onToggleObscure,
                  icon: Icon(
                    obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 20,
                  ),
                ),
                onFieldSubmitted: (_) => onSubmit(),
                validator: (v) => Validators.required(v, field: 'Password'),
              ),
              if (capsLock)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Row(
                    children: [
                      Icon(Icons.keyboard_capslock, size: 16, color: t.warning),
                      const SizedBox(width: 6),
                      Text('Caps Lock is on',
                          style: TextStyle(
                              fontSize: 12.5,
                              color: t.warning,
                              fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                      onTap: () => onRemember(!remember),
                      child: Row(
                        children: [
                          Checkbox(
                            value: remember,
                            onChanged: (v) => onRemember(v ?? false),
                          ),
                          Flexible(
                            child: Text('Remember my username',
                                style: TextStyle(
                                    fontSize: 13, color: t.textSecondary)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: onForgot,
                    child: const Text('Forgot password?'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: busy ? null : onSubmit,
                  child: submitting
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: t.textOnPrimary),
                        )
                      : const Text('Sign in'),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              _DemoCredentials(onFill: onFillDemo),
            ] else ...[
              const SizedBox(height: AppSpacing.lg),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: t.surfaceAlt,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  border: Border.all(color: t.border),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 18, color: t.textTertiary),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Access is managed by your organization. The first '
                        'person to sign in sets up the workspace as Owner; '
                        'everyone else is invited by the Owner from the Users '
                        'screen.',
                        style: TextStyle(
                            color: t.textSecondary, fontSize: 12.5, height: 1.5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
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
          foregroundColor: context.tokens.textPrimary,
          backgroundColor: context.tokens.card,
          side: BorderSide(color: context.tokens.borderStrong),
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
                          color: context.tokens.textPrimary)),
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
        Expanded(child: Divider(color: context.tokens.border)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Text('or',
              style: TextStyle(
                  color: context.tokens.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500)),
        ),
        Expanded(child: Divider(color: context.tokens.border)),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
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

/// Shows the three demo logins with one-tap fill (local demo mode only).
class _DemoCredentials extends StatelessWidget {
  const _DemoCredentials({required this.onFill});

  final ValueChanged<String> onFill;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: t.surfaceAlt,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.science_outlined, size: 18, color: t.textSecondary),
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
            style: TextStyle(color: t.textSecondary, fontSize: 12.5),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final (label, login) in const [
                ('Owner', DemoSeed.ownerLogin),
                ('Admin', DemoSeed.adminLogin),
                ('User', DemoSeed.userLogin),
              ])
                ActionChip(
                  avatar: const Icon(Icons.person_outline, size: 16),
                  label: Text('$label · $login'),
                  onPressed: () => onFill(login),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
