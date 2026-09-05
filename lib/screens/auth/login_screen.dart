import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/demo_account.dart';
import '../../l10n/app_localizations.dart';
import '../../main.dart';
import '../../services/auth_service.dart';
import '../../theme/app_dimens.dart';
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
import 'otp_verification_screen.dart';
import 'phone_login_screen.dart';
import 'signup_screen.dart';
import '../../widgets/common/ino_loader.dart';

/// Screen 3 - Login.
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
  bool _guestBusy = false;

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // Apple is available on every platform for now — Sign in with Apple is still
  // a "coming soon" stub, and hiding it on web/Android made the icon invisible
  // during Chrome testing.
  bool get _showApple => true;

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
    // Captured up-front: the awaits below can outlive this widget, and the
    // error paths still need to speak the user's language.
    final l10n = AppLocalizations.of(context);

    // Only email sign-in is wired to Supabase today; guide mobile users kindly.
    if (!AuthValidators.looksLikeEmail(identifier)) {
      _showMessage(l10n.t('mobileSignInSoon'));
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
        _showMessage(l10n.t('signInFailed'));
        return;
      }
      developer.log(
        'Email sign-in OK: user=${user.id} - routing',
        name: 'auth',
      );
      // Same resilient, completeness-aware routing as the Google path.
      await routeAfterAuth(
        authUserId: user.id,
        fullName: (user.userMetadata?['full_name'] as String?) ?? 'INO User',
        email: user.email ?? identifier,
      );
    } on AuthException catch (e) {
      // An account that was created but never verified cannot sign in, and
      // Supabase answers every attempt with the same error forever. Showing it
      // as a red snackbar left the user permanently locked out of an account
      // they had already made - "sign in with email just doesn't work". Send
      // them to the same 6-digit verification signup uses, with a fresh code,
      // so the account can actually be finished.
      if (_isUnverifiedEmail(e)) {
        await _verifyThenSignIn(identifier);
        return;
      }
      _showMessage(e.message);
    } on PostgrestException catch (e) {
      _showMessage(e.message);
    } on TimeoutException {
      // Distinguished from a generic failure on purpose: "check your
      // connection" is actionable, "something went wrong" is not.
      _showMessage(l10n.t('checkConnection'));
    } catch (_) {
      _showMessage(l10n.t('somethingWentWrong'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Whether [e] is Supabase's "this email was never confirmed" refusal.
  ///
  /// Matched on the stable error code first; the message check is the fallback
  /// for older gotrue responses that carry no code.
  static bool _isUnverifiedEmail(AuthException e) {
    if (e.code == 'email_not_confirmed') return true;
    final message = e.message.toLowerCase();
    return message.contains('not confirmed') ||
        message.contains('email confirmation');
  }

  /// Finishes a half-created account: resend the sign-up code, verify it, then
  /// route on exactly as a successful sign-in would.
  ///
  /// The password the user just typed is already correct (Supabase rejected
  /// the attempt for verification, not credentials), so once the account is
  /// confirmed the OTP response carries a live session and nothing else needs
  /// re-entering.
  Future<void> _verifyThenSignIn(String email) async {
    final l10n = AppLocalizations.of(context);
    try {
      await AuthService.instance.resendSignupOtp(email);
    } catch (_) {
      // A resend failure is not fatal - the original code may still be valid,
      // and the screen offers its own resend button.
    }
    if (!mounted) return;

    _showMessage(l10n.t('verifyEmailToContinue'), isError: false);
    User? verifiedUser;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OtpVerificationScreen(
          title: l10n.t('verificationCode'),
          destination: email,
          onResend: () => AuthService.instance.resendSignupOtp(email),
          onVerify: (code) async {
            final res = await AuthService.instance.verifySignupOtp(
              email: email,
              token: code,
            );
            verifiedUser = res.user;
            return verifiedUser != null;
          },
          onVerified: (_) {
            final user = verifiedUser;
            if (user == null) return;
            // The shared post-auth router decides where they land - it fills
            // in a missing profile row, which is exactly the state an account
            // abandoned at verification is in.
            unawaited(
              routeAfterAuth(
                authUserId: user.id,
                fullName:
                    (user.userMetadata?['full_name'] as String?) ?? 'INO User',
                email: user.email ?? email,
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _continueWithGoogle() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _googleBusy = true);
    try {
      final res = await AuthService.instance.signInWithGoogle();
      if (res == null) {
        developer.log(
          'Google sign-in returned null',
          name: 'auth',
        );
        _showMessage('Google sign-in was cancelled or no account selected.', isError: false);
        return;
      }

      final user = res.user;
      if (user == null) {
        developer.log('Google sign-in: null user in response', name: 'auth');
        _showMessage(l10n.t('googleSignInFailed'));
        return;
      }
      developer.log(
        'Google sign-in OK: user=${user.id} (${user.email}) - routing via shared auth_flow',
        name: 'auth',
      );

      await routeAfterAuth(
        authUserId: user.id,
        fullName:
            (user.userMetadata?['full_name'] as String?) ??
            (user.userMetadata?['name'] as String?) ??
            'INO User',
        email: user.email ?? '',
      );
    } on GoogleSignInException catch (e) {
      final msg = 'Google Sign-In Error: ${e.code.name}${e.description != null ? ' - ${e.description}' : ''}';
      developer.log(msg, name: 'auth', error: e);
      debugPrint('[GoogleSignInException] $msg details=${e.details}');
      _showMessage(msg);
    } on AuthException catch (e) {
      final msg = 'Auth Error: ${e.message} (code: ${e.code})';
      developer.log(msg, name: 'auth', error: e);
      debugPrint('[AuthException] $msg');
      _showMessage(e.message);
    } on PostgrestException catch (e) {
      final msg = 'Database Error: ${e.message}';
      developer.log(msg, name: 'auth', error: e);
      debugPrint('[PostgrestException] $msg');
      _showMessage(e.message);
    } catch (e, stack) {
      developer.log(
        'Unexpected Google sign-in error: $e',
        name: 'auth',
        error: e,
        stackTrace: stack,
      );
      debugPrint('[Unexpected Error] $e\n$stack');
      _showMessage('Sign-In Error: $e');
    } finally {
      if (mounted) setState(() => _googleBusy = false);
    }
  }

  void _continueWithApple() {
    _showMessage(
      AppLocalizations.of(context).t('appleSignInSoon'),
      isError: false,
    );
  }

  /// Demo-only: fill the email + password fields with the shared demo account
  /// (typed in with a light animation) and then trigger the normal [_signIn]
  /// flow - no auth is bypassed, this just automates the same tap a tester
  /// would make. Guarded by [isDemoBuild] at the call site.
  Future<void> _loginAsGuest() async {
    if (_busy || _googleBusy || _guestBusy) return;
    if (demoPassword.isEmpty) return;
    setState(() => _guestBusy = true);
    try {
      await _typeInto(_identifierController, demoEmail);
      await _typeInto(_passwordController, demoPassword);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      await _signIn();
    } finally {
      if (mounted) setState(() => _guestBusy = false);
    }
  }

  /// Types [text] into [controller] one character at a time for a smooth
  /// auto-fill effect. Keeps the caret at the end so the field scrolls with it.
  Future<void> _typeInto(TextEditingController controller, String text) async {
    controller.clear();
    for (var i = 0; i < text.length; i++) {
      if (!mounted) return;
      controller
        ..text = text.substring(0, i + 1)
        ..selection = TextSelection.collapsed(offset: i + 1);
      await Future<void>.delayed(const Duration(milliseconds: 24));
    }
  }

  void _continueWithPhone() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PhoneLoginScreen()),
    );
  }

  void _goToSignup() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const SignupScreen()),
    );
  }

  void _goToForgotPassword() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ForgotPasswordScreen(
          initialIdentifier: _identifierController.text.trim(),
        ),
      ),
    );
  }

  // --- Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final validate = AuthValidators.of(context);
    final busy = _busy || _googleBusy || _guestBusy;
    final screenH = MediaQuery.sizeOf(context).height;
    // Tighten vertical rhythm on short phones so the form fits without
    // endless scrolling; keep a little breathing room on taller screens.
    final compact = screenH < 740;
    final gapXs = compact ? 6.0 : 8.0;
    final gapSm = compact ? 10.0 : 12.0;
    final gapMd = compact ? 14.0 : 16.0;
    final gapLg = compact ? 16.0 : 20.0;
    final logoSize = compact ? 56.0 : 64.0;
    final titleStyle = AppText.display.copyWith(
      color: Colors.white,
      fontSize: compact ? 28 : 32,
    );

    return AuthScaffold(
      // Login is sometimes pushed (guest-mode "Sign In") and sometimes a
      // stack-cleared root (after sign-out); the back button hides itself
      // whenever the route can't pop.
      showBack: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // --- Brand identity header (Stitch hero treatment) ---------------
          FadeSlideIn(child: Center(child: InoLogo(size: logoSize))),
          SizedBox(height: gapMd),
          FadeSlideIn(
            delay: const Duration(milliseconds: 60),
            child: ShaderMask(
              shaderCallback: (bounds) =>
                  AppColors.brandGradient.createShader(bounds),
              blendMode: BlendMode.srcIn,
              child: Text(
                l10n.t('authWelcomeBack'),
                textAlign: TextAlign.center,
                style: titleStyle,
              ),
            ),
          ),
          SizedBox(height: gapXs),
          FadeSlideIn(
            delay: const Duration(milliseconds: 110),
            child: Text(
              l10n.t('authSignInSubtitle'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: compact ? 13.5 : 14.5,
                color: palette.textSecondary,
              ),
            ),
          ),
          SizedBox(height: gapLg),

          // Email / password first, then federated options.
          FadeSlideIn(
            delay: const Duration(milliseconds: 160),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Form(
                  key: _formKey,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  child: Column(
                    children: [
                      AuthTextField(
                        controller: _identifierController,
                        label: l10n.t('emailOrMobile'),
                        hint: 'you@example.com',
                        icon: Icons.alternate_email_rounded,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.username],
                        validator: validate.emailOrPhone,
                      ),
                      SizedBox(height: gapMd),
                      AuthTextField(
                        controller: _passwordController,
                        label: l10n.t('password'),
                        hint: '••••••••',
                        icon: Icons.lock_outline_rounded,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.password],
                        validator: validate.password,
                        onSubmitted: (_) => _signIn(),
                        suffix: _VisibilityToggle(
                          obscured: _obscurePassword,
                          onTap: () => setState(
                              () => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: gapXs),

                Row(
                  children: [
                    Flexible(
                      child: _RememberMe(
                        label: l10n.t('rememberMe'),
                        value: _rememberMe,
                        onChanged: (v) => setState(() => _rememberMe = v),
                      ),
                    ),
                    Flexible(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: busy ? null : _goToForgotPassword,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              l10n.t('forgotPasswordQ'),
                              maxLines: 1,
                              style: TextStyle(
                                color: AppColors.primaryGreen,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: gapSm),

                AuthPrimaryButton(
                  label: l10n.t('signIn'),
                  busy: _busy,
                  onPressed: busy ? null : _signIn,
                ),
                SizedBox(height: gapSm),
                SizedBox(
                  width: double.infinity,
                  height: compact ? 48 : 52,
                  child: OutlinedButton(
                    onPressed: busy ? null : () => enterGuestExplore(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primaryGreen,
                      side: BorderSide(
                        color: AppColors.primaryGreen.withValues(alpha: 0.45),
                        width: 1.4,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      l10n.t('continueAsGuest'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15.5,
                      ),
                    ),
                  ),
                ),

                if (isDemoBuild && demoPassword.isNotEmpty) ...[
                  SizedBox(height: gapSm),
                  _GuestLoginButton(
                    label: l10n.t('loginAsGuest'),
                    busy: _guestBusy,
                    onPressed: busy ? null : _loginAsGuest,
                  ),
                ],

                SizedBox(height: gapLg),
                _OrDivider(label: l10n.t('orDivider')),
                SizedBox(height: gapLg),

                // Icon-only federated row: Google · Phone · Apple.
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SocialAuthIconButton(
                      tooltip: l10n.t('continueWithGoogle'),
                      brand: const GoogleGlyph(size: 24),
                      busy: _googleBusy,
                      onPressed: busy ? null : _continueWithGoogle,
                    ),
                    const SizedBox(width: 18),
                    SocialAuthIconButton(
                      tooltip: l10n.t('continueWithPhone'),
                      brand: Icon(
                        Icons.smartphone_rounded,
                        color: AppColors.primaryGreen,
                        size: 24,
                      ),
                      onPressed: busy ? null : _continueWithPhone,
                    ),
                    if (_showApple) ...[
                      const SizedBox(width: 18),
                      SocialAuthIconButton(
                        tooltip: l10n.t('continueWithApple'),
                        brand: const AppleGlyph(size: 26),
                        onPressed: busy ? null : _continueWithApple,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          SizedBox(height: gapLg),

          FadeSlideIn(
            delay: const Duration(milliseconds: 320),
            child: _AuthSwitchRow(
              prompt: l10n.t('noAccountPrompt'),
              action: l10n.t('createAccount'),
              onTap: busy ? null : _goToSignup,
            ),
          ),
        ],
      ),
    );
  }
}

/// Demo-only "Login as Guest" button - an outlined, full-width control with a
/// light Rama-blue (brand teal) border and a white surface, matching the width
/// of the primary Sign In button above it.
class _GuestLoginButton extends StatelessWidget {
  const _GuestLoginButton({
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: AppColors.primaryGreen,
          side: BorderSide(color: AppColors.tealPale, width: 1.4),
          shape: RoundedRectangleBorder(
            // Pill outline, mirroring the gradient CTA above it.
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
        ),
        child: busy
            ? InoLoader(size: 20, color: AppColors.primaryGreen)
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.person_outline_rounded, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
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
  const _RememberMe({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
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
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: value ? AppColors.primaryGreen : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: value ? AppColors.primaryGreen : AppColors.tealPale,
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
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w500,
                ),
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
  const _OrDivider({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final line = Expanded(
      child: Divider(color: AppColors.tealMist, height: 1),
    );
    return Row(
      children: [
        line,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            label,
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
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textMuted),
            maxLines: 1,
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
            style: TextStyle(
              color: AppColors.primaryGreen,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
