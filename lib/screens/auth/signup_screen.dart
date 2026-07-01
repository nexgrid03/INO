import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/user_profile.dart';
import '../../repositories/user_repository.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/auth/auth_primary_button.dart';
import '../../widgets/auth/auth_scaffold.dart';
import '../../widgets/auth/auth_text_field.dart';
import '../../widgets/dashboard/fade_slide_in.dart';
import 'auth_validators.dart';
import 'biometric_setup_screen.dart';
import 'otp_verification_screen.dart';

/// Screen 4 — Signup.
///
/// Creates an account with the app's Supabase [AuthService]. If the project
/// requires email confirmation the user is routed to the OTP screen to enter
/// the emailed code; otherwise they continue straight to Biometric Setup. Kept
/// deliberately simple — one column of fields and a single CTA.
class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _busy = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _showMessage(String message, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor:
              isError ? AppColors.critical : AppColors.primaryGreen,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _createAccount() async {
    if (!_formKey.currentState!.validate()) return;

    final email = _emailController.text.trim();
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();

    setState(() => _busy = true);
    try {
      final res = await AuthService.instance.signUpWithEmail(
        email: email,
        password: _passwordController.text,
        fullName: name,
      );
      final user = res.user;

      if (res.session != null && user != null) {
        // Auto-confirmed: profile can be created now (session is active).
        final profile = await UserRepository.instance.createProfile(
          authUserId: user.id,
          fullName: name,
          email: email,
          phone: phone,
        );
        if (!mounted) return;
        _goToBiometric(profile);
      } else {
        // Email confirmation required — verify the 6-digit code next.
        if (!mounted) return;
        _goToOtp(email: email, name: name, phone: phone);
      }
    } on AuthException catch (e) {
      _showMessage(e.message);
    } on PostgrestException catch (e) {
      _showMessage(e.message);
    } catch (_) {
      _showMessage('Could not create your account. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _goToOtp({
    required String email,
    required String name,
    required String phone,
  }) {
    UserProfile? verified;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OtpVerificationScreen(
          title: 'Verification Code',
          destination: email,
          onResend: () => AuthService.instance.resendSignupOtp(email),
          onVerify: (code) async {
            final res = await AuthService.instance.verifySignupOtp(
              email: email,
              token: code,
            );
            final user = res.user;
            if (user == null) return false;
            // Session is now active → create the profile row (with the phone
            // the user provided at signup, so it isn't lost).
            verified = await UserRepository.instance.createProfile(
              authUserId: user.id,
              fullName: name,
              email: email,
              phone: phone,
            );
            return true;
          },
          onVerified: (ctx) => _goToBiometric(verified!, navContext: ctx),
        ),
      ),
    );
  }

  void _goToBiometric(UserProfile profile, {BuildContext? navContext}) {
    Navigator.of(navContext ?? context).push(
      MaterialPageRoute(
        builder: (_) => BiometricSetupScreen(profile: profile),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      showBack: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          FadeSlideIn(
            child: const Text(
              'Create Account',
              style: TextStyle(
                fontSize: 27,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
          ),
          const SizedBox(height: 8),
          FadeSlideIn(
            delay: const Duration(milliseconds: 60),
            child: const Text(
              'Start your secure digital life with INO',
              style: TextStyle(fontSize: 14.5, color: AppColors.textMuted),
            ),
          ),
          const SizedBox(height: 30),

          Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              children: [
                FadeSlideIn(
                  delay: const Duration(milliseconds: 110),
                  child: AuthTextField(
                    controller: _nameController,
                    label: 'Full name',
                    icon: Icons.person_outline_rounded,
                    keyboardType: TextInputType.name,
                    textInputAction: TextInputAction.next,
                    textCapitalization: TextCapitalization.words,
                    autofillHints: const [AutofillHints.name],
                    validator: AuthValidators.name,
                  ),
                ),
                const SizedBox(height: 16),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 150),
                  child: AuthTextField(
                    controller: _emailController,
                    label: 'Email address',
                    hint: 'you@example.com',
                    icon: Icons.mail_outline_rounded,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.email],
                    validator: AuthValidators.email,
                  ),
                ),
                const SizedBox(height: 16),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 190),
                  child: AuthTextField(
                    controller: _phoneController,
                    label: 'Mobile number',
                    hint: '+91 98765 43210',
                    icon: Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.telephoneNumber],
                    validator: AuthValidators.phone,
                  ),
                ),
                const SizedBox(height: 16),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 230),
                  child: AuthTextField(
                    controller: _passwordController,
                    label: 'Password',
                    hint: 'At least 6 characters',
                    icon: Icons.lock_outline_rounded,
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.newPassword],
                    validator: AuthValidators.password,
                    suffix: IconButton(
                      onPressed: () => setState(
                        () => _obscurePassword = !_obscurePassword,
                      ),
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 270),
                  child: AuthTextField(
                    controller: _confirmController,
                    label: 'Confirm password',
                    hint: 'Re-enter your password',
                    icon: Icons.lock_outline_rounded,
                    obscureText: _obscureConfirm,
                    textInputAction: TextInputAction.done,
                    validator: (v) => AuthValidators.confirmPassword(
                      v,
                      _passwordController.text,
                    ),
                    onSubmitted: (_) => _createAccount(),
                    suffix: IconButton(
                      onPressed: () => setState(
                        () => _obscureConfirm = !_obscureConfirm,
                      ),
                      icon: Icon(
                        _obscureConfirm
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          FadeSlideIn(
            delay: const Duration(milliseconds: 320),
            child: AuthPrimaryButton(
              label: 'Create Account',
              busy: _busy,
              onPressed: _busy ? null : _createAccount,
            ),
          ),
          const SizedBox(height: 22),

          FadeSlideIn(
            delay: const Duration(milliseconds: 360),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Already have an account?',
                  style: TextStyle(color: AppColors.textMuted),
                ),
                TextButton(
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: const Size(0, 0),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'Sign In',
                    style: TextStyle(
                      color: AppColors.primaryGreen,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
