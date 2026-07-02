import 'dart:developer' as developer;

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../main.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/auth/auth_primary_button.dart';
import '../../widgets/auth/auth_scaffold.dart';
import '../../widgets/auth/auth_text_field.dart';
import '../../widgets/auth/social_auth_button.dart';
import '../../widgets/dashboard/fade_slide_in.dart';
import '../../widgets/ino_logo.dart';
import 'auth_flow.dart';
import 'auth_validators.dart';
import 'forgot_password_screen.dart';
import 'signup_screen.dart';

/// Screen 3 — Login.
///
/// A fast, card-less sign-in: brand mark, email/mobile + password, Remember me
/// / Forgot password, the gradient primary CTA, then federated options and a
/// route to Create Account. Wired to the app's Supabase [AuthService].
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _rememberMe = true;
  bool _busy = false;
  bool _googleBusy = false;

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool get _showApple => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  // --- Actions --------------------------------------------------------------

  void _showMessage(String message, {bool isError = true}) {
    final snackBar = SnackBar(
      content: Text(message),
      backgroundColor: isError ? AppColors.critical : AppColors.primaryGreen,
      behavior: SnackBarBehavior.floating,
    );
    // Prefer this screen's messenger; if it was disposed (e.g. during the
    // Google picker) fall back to the app-root messenger so the error is never
    // swallowed silently.
    final messenger = mounted
        ? ScaffoldMessenger.of(context)
        : InoApp.messengerKey.currentState;
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(snackBar);
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    final identifier = _identifierController.text.trim();

    // Only email sign-in is wired to Supabase today; guide mobile users kindly.
    if (!AuthValidators.looksLikeEmail(identifier)) {
      _showMessage('Mobile sign-in is coming soon — please use your email.');
      return;
    }

    setState(() => _busy = true);
    try {
      final res = await AuthService.instance.signInWithEmail(
        email: identifier,
        password: _passwordController.text,
      );
      final user = res.user;
      if (user == null) {
        _showMessage('Sign in failed. Please try again.');
        return;
      }
      developer.log(
        'Email sign-in OK: user=${user.id} — routing',
        name: 'auth',
      );
      // Same resilient, completeness-aware routing as the Google path.
      await routeAfterAuth(
        authUserId: user.id,
        fullName: (user.userMetadata?['full_name'] as String?) ?? 'INO User',
        email: user.email ?? identifier,
      );
    } on AuthException catch (e) {
      _showMessage(e.message);
    } on PostgrestException catch (e) {
      _showMessage(e.message);
    } catch (_) {
      _showMessage('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _continueWithGoogle() async {
    setState(() => _googleBusy = true);
    try {
      final res = await AuthService.instance.signInWithGoogle();
      if (res == null) {
        developer.log(
          'Google sign-in cancelled — staying on login',
          name: 'auth',
        );
        return; // user cancelled the picker
      }
      final user = res.user;
      if (user == null) {
        developer.log('Google sign-in: null user in response', name: 'auth');
        _showMessage('Google sign-in failed. Please try again.');
        return;
      }
      developer.log(
        'Google sign-in OK: user=${user.id} — routing',
        name: 'auth',
      );
      // Route via the app-root navigator (inside routeAfterAuth) so it works
      // even if THIS widget was disposed while the Google picker (Credential
      // Manager) was open — the previous code used the local context + a
      // `!mounted` guard here, which is exactly why nothing happened after
      // picking an account.
      await routeAfterAuth(
        authUserId: user.id,
        fullName:
            (user.userMetadata?['full_name'] as String?) ??
            (user.userMetadata?['name'] as String?) ??
            'INO User',
        email: user.email ?? '',
      );
    } on GoogleSignInException catch (e) {
      developer.log(
        'Google sign-in exception: ${e.code} ${e.description}',
        name: 'auth',
        error: e,
      );
      _showMessage('Could not sign in with Google. Please try again.');
    } on AuthException catch (e) {
      developer.log(
        'Auth exception during Google sign-in: ${e.message}',
        name: 'auth',
        error: e,
      );
      _showMessage(e.message);
    } on PostgrestException catch (e) {
      developer.log(
        'Profile DB error during Google sign-in: ${e.message}',
        name: 'auth',
        error: e,
      );
      _showMessage(e.message);
    } catch (e) {
      developer.log(
        'Unexpected Google sign-in error: $e',
        name: 'auth',
        error: e,
      );
      _showMessage('Could not sign in with Google. Please try again.');
    } finally {
      if (mounted) setState(() => _googleBusy = false);
    }
  }

  void _continueWithApple() {
    _showMessage('Apple sign-in is coming soon.', isError: false);
  }

  void _goToSignup() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SignupScreen()));
  }

  void _goToForgotPassword() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_l) => ForgotPasswordScreen(
          initialIdentifier: _identifierController.text.trim(),
        ),
      ),
    );
  }

  // --- Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final busy = _busy || _googleBusy;
    return AuthScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 24),
          FadeSlideIn(child: Center(child: InoLogo(size: 72))),
          const SizedBox(height: 24),
          FadeSlideIn(
            delay: const Duration(milliseconds: 60),
            child: const Text(
              'Welcome Back',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 27,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
          ),
          const SizedBox(height: 8),
          FadeSlideIn(
            delay: const Duration(milliseconds: 110),
            child: const Text(
              'Sign in to continue using INO',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14.5, color: AppColors.textMuted),
            ),
          ),
          const SizedBox(height: 34),

          Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              children: [
                FadeSlideIn(
                  delay: const Duration(milliseconds: 160),
                  child: AuthTextField(
                    controller: _identifierController,
                    label: 'Email or mobile number',
                    hint: 'you@example.com',
                    icon: Icons.alternate_email_rounded,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.username],
                    validator: AuthValidators.emailOrPhone,
                  ),
                ),
                const SizedBox(height: 16),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 210),
                  child: AuthTextField(
                    controller: _passwordController,
                    label: 'Password',
                    hint: '••••••••',
                    icon: Icons.lock_outline_rounded,
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.password],
                    validator: AuthValidators.password,
                    onSubmitted: (_) => _signIn(),
                    suffix: _VisibilityToggle(
                      obscured: _obscurePassword,
                      onTap: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),

          FadeSlideIn(
            delay: const Duration(milliseconds: 250),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _RememberMe(
                  value: _rememberMe,
                  onChanged: (v) => setState(() => _rememberMe = v),
                ),
                TextButton(
                  onPressed: busy ? null : _goToForgotPassword,
                  child: const Text(
                    'Forgot password?',
                    style: TextStyle(
                      color: AppColors.primaryGreen,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          FadeSlideIn(
            delay: const Duration(milliseconds: 300),
            child: AuthPrimaryButton(
              label: 'Sign In',
              busy: _busy,
              onPressed: busy ? null : _signIn,
            ),
          ),
          const SizedBox(height: 26),

          FadeSlideIn(
            delay: const Duration(milliseconds: 340),
            child: const _OrDivider(),
          ),
          const SizedBox(height: 22),

          FadeSlideIn(
            delay: const Duration(milliseconds: 380),
            child: SocialAuthButton(
              label: 'Continue with Google',
              brand: const GoogleGlyph(),
              busy: _googleBusy,
              onPressed: busy ? null : _continueWithGoogle,
            ),
          ),
          if (_showApple) ...[
            const SizedBox(height: 12),
            FadeSlideIn(
              delay: const Duration(milliseconds: 420),
              child: SocialAuthButton(
                label: 'Continue with Apple',
                brand: const Icon(Icons.apple, color: Colors.black, size: 20),
                onPressed: busy ? null : _continueWithApple,
              ),
            ),
          ],
          const SizedBox(height: 30),

          FadeSlideIn(
            delay: const Duration(milliseconds: 460),
            child: _AuthSwitchRow(
              prompt: "Don't have an account?",
              action: 'Create Account',
              onTap: busy ? null : _goToSignup,
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// Password visibility eye toggle used by the auth password fields.
class _VisibilityToggle extends StatelessWidget {
  const _VisibilityToggle({required this.obscured, required this.onTap});

  final bool obscured;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(
        obscured ? Icons.visibility_off_outlined : Icons.visibility_outlined,
        color: AppColors.textMuted,
      ),
    );
  }
}

class _RememberMe extends StatelessWidget {
  const _RememberMe({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: value ? AppColors.primaryGreen : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: value
                      ? AppColors.primaryGreen
                      : const Color(0xFFCBD5E1),
                  width: 1.6,
                ),
              ),
              child: value
                  ? const Icon(
                      Icons.check_rounded,
                      size: 14,
                      color: Colors.white,
                    )
                  : null,
            ),
            const SizedBox(width: 8),
            const Text(
              'Remember me',
              style: TextStyle(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "OR" separator between the primary CTA and the social buttons.
class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    const line = Expanded(child: Divider(color: Color(0xFFE2E8F0), height: 1));
    return Row(
      children: [
        line,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            'OR',
            style: TextStyle(
              color: AppColors.textMuted.withValues(alpha: 0.8),
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
        ),
        line,
      ],
    );
  }
}

/// The "Don't have an account? Create Account" / inverse row shared by
/// Login and Signup.
class _AuthSwitchRow extends StatelessWidget {
  const _AuthSwitchRow({
    required this.prompt,
    required this.action,
    required this.onTap,
  });

  final String prompt;
  final String action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: Text(
            prompt,
            style: const TextStyle(color: AppColors.textMuted),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            minimumSize: const Size(0, 0),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            action,
            style: const TextStyle(
              color: AppColors.primaryGreen,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
