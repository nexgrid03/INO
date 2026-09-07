import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/demo_account.dart';
import '../../l10n/app_localizations.dart';
import '../../main.dart';
import '../../models/country_code.dart';
import '../../models/user_profile.dart';
import '../../repositories/user_repository.dart';
import '../../services/auth_service.dart';
import '../../services/guest_mode.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/auth/auth_primary_button.dart';
import '../../widgets/auth/auth_scaffold.dart';
import '../../widgets/auth/auth_text_field.dart';
import '../../widgets/auth/country_code_sheet.dart';
import '../../widgets/auth/social_auth_button.dart';
import '../../widgets/dashboard/fade_slide_in.dart';
import '../../widgets/ino_logo.dart';
import '../../widgets/pressable_scale.dart';
import '../legal/legal_document_screen.dart';
import 'auth_flow.dart';
import 'auth_validators.dart';
import 'biometric_setup_screen.dart';
import 'forgot_password_screen.dart';
import 'otp_verification_screen.dart';
import 'phone_login_screen.dart';
import 'signup_screen.dart';

enum AuthMode {
  signIn,
  signUp,
}

enum VerificationChannel {
  email,
  phone,
}

/// Redesigned INO Authentication Screen: Supports seamless switching between
/// New User (Create Account + Email/Mobile OTP) and Existing User (Phone/Email OTP / password).
class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    this.initialMode = AuthMode.signIn,
  });

  final AuthMode initialMode;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late AuthMode _mode = widget.initialMode;

  // Form keys
  final _signInFormKey = GlobalKey<FormState>();
  final _signUpFormKey = GlobalKey<FormState>();

  // Sign in controllers
  final _signInIdentifierController = TextEditingController();
  final _signInPasswordController = TextEditingController();
  bool _signInWithPassword = false;
  VerificationChannel _signInChannel = VerificationChannel.phone;
  CountryCode _signInCountry = kCountryCodes.first;

  // Sign up controllers
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  CountryCode _signUpCountry = kCountryCodes.first;
  VerificationChannel _signupVerificationMethod = VerificationChannel.email;
  bool _acceptedTerms = false;

  bool _obscurePassword = true;
  bool _rememberMe = true;
  bool _busy = false;
  bool _googleBusy = false;
  bool _guestBusy = false;

  @override
  void dispose() {
    _signInIdentifierController.dispose();
    _signInPasswordController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _showMessage(String message, {bool isError = true}) {
    final snackBar = SnackBar(
      content: Text(message),
      backgroundColor: isError ? AppColors.critical : AppColors.primaryGreen,
      behavior: SnackBarBehavior.floating,
    );
    final messenger = mounted
        ? ScaffoldMessenger.of(context)
        : InoApp.messengerKey.currentState;
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(snackBar);
  }

  // --- New User: Send OTP & Create Account ----------------------------------

  Future<void> _handleNewUserSignup() async {
    if (!(_signUpFormKey.currentState?.validate() ?? false)) return;
    if (!_acceptedTerms) {
      _showMessage('Please accept the Terms of Service & Privacy Policy to continue.');
      return;
    }

    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final nationalPhone = _phoneController.text.replaceAll(RegExp(r'[^0-9]'), '');
    final fullPhone = '${_signUpCountry.dialCode}$nationalPhone';

    if (name.isEmpty) {
      _showMessage('Please enter your full name.');
      return;
    }
    if (!AuthValidators.looksLikeEmail(email)) {
      _showMessage('Please enter a valid email address.');
      return;
    }
    if (nationalPhone.length < 6) {
      _showMessage('Please enter a valid mobile number.');
      return;
    }

    setState(() => _busy = true);
    FocusScope.of(context).unfocus();

    try {
      if (_signupVerificationMethod == VerificationChannel.email) {
        // Send OTP to Email
        await AuthService.instance.sendEmailOtp(
          email,
          data: {
            'full_name': name,
            'phone': fullPhone,
            'accepted_terms': true,
            'attestation_18_plus': true,
          },
        );
        if (!mounted) return;
        _goToNewUserOtpScreen(
          destination: email,
          name: name,
          email: email,
          phone: fullPhone,
          isEmail: true,
        );
      } else {
        // Send OTP to Mobile (Twilio provider via Supabase)
        await AuthService.instance.sendPhoneOtp(
          fullPhone,
          data: {
            'full_name': name,
            'email': email,
            'accepted_terms': true,
            'attestation_18_plus': true,
          },
        );
        if (!mounted) return;
        _goToNewUserOtpScreen(
          destination: fullPhone,
          name: name,
          email: email,
          phone: fullPhone,
          isEmail: false,
        );
      }
    } catch (e) {
      _showMessage(AuthService.formatAuthError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _goToNewUserOtpScreen({
    required String destination,
    required String name,
    required String email,
    required String phone,
    required bool isEmail,
  }) {
    User? verifiedUser;
    UserProfile? createdProfile;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OtpVerificationScreen(
          title: 'Verify Your ${isEmail ? "Email" : "Mobile Number"}',
          destination: destination,
          onResend: () async {
            if (isEmail) {
              await AuthService.instance.sendEmailOtp(
                email,
                data: {
                  'full_name': name,
                  'phone': phone,
                  'accepted_terms': true,
                  'attestation_18_plus': true,
                },
              );
            } else {
              await AuthService.instance.sendPhoneOtp(
                phone,
                data: {
                  'full_name': name,
                  'email': email,
                  'accepted_terms': true,
                  'attestation_18_plus': true,
                },
              );
            }
          },
          onVerify: (code) async {
            final AuthResponse res;
            if (isEmail) {
              res = await AuthService.instance.verifyEmailOtp(
                email: email,
                token: code,
              );
            } else {
              res = await AuthService.instance.verifyPhoneOtp(
                phone: phone,
                token: code,
              );
            }
            final user = res.user;
            if (user == null) return false;
            verifiedUser = user;

            // Record terms consent in metadata & audit table
            await AuthService.instance.recordTermsConsent(
              version: '1.0',
              attest18Plus: true,
            );

            // Create/Upsert User Profile in public.users
            try {
              createdProfile = await UserRepository.instance.createProfile(
                authUserId: user.id,
                fullName: name,
                email: email,
                phone: phone,
              );
            } catch (_) {
              // Fallback to fetch existing if already created by trigger
              createdProfile = await UserRepository.instance.getProfileByAuthId(user.id);
            }
            return true;
          },
          onVerified: (navCtx) {
            final profile = createdProfile;
            final user = verifiedUser;
            if (profile != null) {
              goToShell(navCtx, profile);
            } else if (user != null) {
              routeAfterAuth(
                authUserId: user.id,
                fullName: name,
                email: email,
                phone: phone,
              );
            }
          },
        ),
      ),
    );
  }

  // --- Existing User: Send OTP & Sign In -------------------------------------

  Future<void> _handleExistingUserSignIn() async {
    if (_signInWithPassword) {
      await _signInWithEmailPassword();
      return;
    }

    FocusScope.of(context).unfocus();
    final l10n = AppLocalizations.of(context);

    if (_signInChannel == VerificationChannel.phone) {
      final nationalPhone =
          _signInIdentifierController.text.replaceAll(RegExp(r'[^0-9]'), '');
      if (nationalPhone.length < 6) {
        _showMessage(l10n.t('valInvalidMobile'));
        return;
      }
      final fullPhone = '${_signInCountry.dialCode}$nationalPhone';

      setState(() => _busy = true);
      try {
        await AuthService.instance.sendPhoneOtp(fullPhone);
        if (!mounted) return;
        _goToExistingUserOtpScreen(destination: fullPhone, isEmail: false);
      } catch (e) {
        _showMessage(AuthService.formatAuthError(e));
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    } else {
      final email = _signInIdentifierController.text.trim();
      if (!AuthValidators.looksLikeEmail(email)) {
        _showMessage('Please enter a valid email address.');
        return;
      }

      setState(() => _busy = true);
      try {
        await AuthService.instance.sendEmailOtp(email);
        if (!mounted) return;
        _goToExistingUserOtpScreen(destination: email, isEmail: true);
      } catch (e) {
        _showMessage(AuthService.formatAuthError(e));
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
  }

  void _goToExistingUserOtpScreen({
    required String destination,
    required bool isEmail,
  }) {
    User? verifiedUser;
    UserProfile? loadedProfile;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OtpVerificationScreen(
          title: 'Sign In Verification',
          destination: destination,
          onResend: () async {
            if (isEmail) {
              await AuthService.instance.sendEmailOtp(destination);
            } else {
              await AuthService.instance.sendPhoneOtp(destination);
            }
          },
          onVerify: (code) async {
            final AuthResponse res;
            if (isEmail) {
              res = await AuthService.instance.verifyEmailOtp(
                email: destination,
                token: code,
              );
            } else {
              res = await AuthService.instance.verifyPhoneOtp(
                phone: destination,
                token: code,
              );
            }
            final user = res.user;
            if (user == null) return false;
            verifiedUser = user;

            // Load existing profile
            loadedProfile = await UserRepository.instance.getProfileByAuthId(user.id);
            return true;
          },
          onVerified: (navCtx) {
            final profile = loadedProfile;
            final user = verifiedUser;
            if (profile != null) {
              goToShell(navCtx, profile);
            } else if (user != null) {
              routeAfterAuth(
                authUserId: user.id,
                fullName: (user.userMetadata?['full_name'] as String?) ??
                    (user.userMetadata?['name'] as String?) ??
                    'INO User',
                email: user.email ?? (isEmail ? destination : ''),
                phone: isEmail ? null : destination,
              );
            }
          },
        ),
      ),
    );
  }

  Future<void> _signInWithEmailPassword() async {
    if (!(_signInFormKey.currentState?.validate() ?? false)) return;
    final identifier = _signInIdentifierController.text.trim();
    if (!AuthValidators.looksLikeEmail(identifier)) {
      _showMessage('Password login requires a valid email address.');
      return;
    }

    setState(() => _busy = true);
    try {
      final res = await AuthService.instance.signInWithEmail(
        email: identifier,
        password: _signInPasswordController.text,
      );
      final user = res.user;
      if (user == null) {
        _showMessage('Sign in failed. Please try again.');
        return;
      }
      await routeAfterAuth(
        authUserId: user.id,
        fullName: (user.userMetadata?['full_name'] as String?) ?? 'INO User',
        email: user.email ?? identifier,
      );
    } catch (e) {
      _showMessage(AuthService.formatAuthError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // --- Google & Social Auth -------------------------------------------------

  Future<void> _continueWithGoogle() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _googleBusy = true);
    try {
      final res = await AuthService.instance.signInWithGoogle();
      if (res == null) {
        return;
      }
      final user = res.user;
      if (user == null) {
        _showMessage(l10n.t('googleSignInFailed'));
        return;
      }
      final fullName = (user.userMetadata?['full_name'] as String?) ??
          (user.userMetadata?['name'] as String?) ??
          'INO User';
      final email = user.email ?? '';
      await routeAfterAuth(
        authUserId: user.id,
        fullName: fullName,
        email: email,
      );
    } catch (e) {
      _showMessage(AuthService.formatAuthError(e));
    } finally {
      if (mounted) setState(() => _googleBusy = false);
    }
  }

  void _continueWithApple() {
    _showMessage('Sign in with Apple is coming soon.', isError: false);
  }

  void _continueWithPhone() {
    setState(() {
      _mode = AuthMode.signIn;
      _signInChannel = VerificationChannel.phone;
      _signInWithPassword = false;
    });
  }

  void _goToForgotPassword() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ForgotPasswordScreen(
          initialIdentifier: _signInIdentifierController.text.trim(),
        ),
      ),
    );
  }

  void _openTerms() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => LegalDocumentScreen.terms()),
    );
  }

  void _openPrivacy() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => LegalDocumentScreen.privacy()),
    );
  }

  // --- Country Code Pickers -------------------------------------------------

  Future<void> _pickSignUpCountry() async {
    final picked = await showCountryCodePicker(context, initial: _signUpCountry);
    if (picked != null && mounted) {
      setState(() => _signUpCountry = picked);
    }
  }

  Future<void> _pickSignInCountry() async {
    final picked = await showCountryCodePicker(context, initial: _signInCountry);
    if (picked != null && mounted) {
      setState(() => _signInCountry = picked);
    }
  }

  // --- Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final busy = _busy || _googleBusy || _guestBusy;
    final isSignUp = _mode == AuthMode.signUp;

    return AuthScaffold(
      showBack: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          // Brand Logo
          FadeSlideIn(
            child: const Center(child: InoLogo(size: 60)),
          ),
          const SizedBox(height: 14),

          // Header Title
          FadeSlideIn(
            delay: const Duration(milliseconds: 60),
            child: ShaderMask(
              shaderCallback: (bounds) =>
                  AppColors.brandGradient.createShader(bounds),
              blendMode: BlendMode.srcIn,
              child: Text(
                isSignUp ? l10n.t('joinTheVault') : l10n.t('authWelcomeBack'),
                textAlign: TextAlign.center,
                style: AppText.display.copyWith(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),

          // Subtitle
          FadeSlideIn(
            delay: const Duration(milliseconds: 100),
            child: Text(
              isSignUp
                  ? 'Create your secure INO digital vault'
                  : 'Sign in to access your vaults and documents',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: palette.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Mode Toggle Pills (Create Account vs Sign In)
          FadeSlideIn(
            delay: const Duration(milliseconds: 120),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: palette.isDark ? palette.surfaceVariant : AppColors.tealPale.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: palette.border.withValues(alpha: 0.5),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _ModeTabButton(
                      label: l10n.t('createAccount'),
                      active: isSignUp,
                      onTap: busy
                          ? null
                          : () {
                              FocusScope.of(context).unfocus();
                              setState(() => _mode = AuthMode.signUp);
                            },
                    ),
                  ),
                  Expanded(
                    child: _ModeTabButton(
                      label: l10n.t('signIn'),
                      active: !isSignUp,
                      onTap: busy
                          ? null
                          : () {
                              FocusScope.of(context).unfocus();
                              setState(() => _mode = AuthMode.signIn);
                            },
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Form Body
          if (isSignUp) _buildSignUpForm(palette, l10n, busy) else _buildSignInForm(palette, l10n, busy),

          const SizedBox(height: 12),
        ],
      ),
    );
  }

  // --- Sign Up Form (New User) -----------------------------------------------

  Widget _buildSignUpForm(AppPalette palette, AppLocalizations l10n, bool busy) {
    return FadeSlideIn(
      delay: const Duration(milliseconds: 160),
      child: Form(
        key: _signUpFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Full Name
            AuthTextField(
              controller: _nameController,
              label: l10n.t('fullName'),
              hint: 'John Doe',
              icon: Icons.person_outline_rounded,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter your full name' : null,
            ),
            const SizedBox(height: 14),

            // Email Address
            AuthTextField(
              controller: _emailController,
              label: l10n.t('emailAddress'),
              hint: 'you@example.com',
              icon: Icons.alternate_email_rounded,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              validator: (v) => !AuthValidators.looksLikeEmail(v ?? '') ? 'Enter a valid email' : null,
            ),
            const SizedBox(height: 14),

            // Mobile Number with Country Code
            AuthTextField(
              controller: _phoneController,
              label: l10n.t('mobileNumber'),
              hint: '9876543210',
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              prefixWidget: InkWell(
                onTap: busy ? null : _pickSignUpCountry,
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.only(left: 14, right: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_signUpCountry.flag, style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 4),
                      Text(
                        _signUpCountry.dialCode,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: palette.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(Icons.arrow_drop_down, size: 18, color: palette.textSecondary),
                    ],
                  ),
                ),
              ),
              validator: (v) {
                final digits = (v ?? '').replaceAll(RegExp(r'[^0-9]'), '');
                if (digits.length < 6) return 'Enter a valid mobile number';
                return null;
              },
            ),
            const SizedBox(height: 18),

            // Verification Method Selector
            Text(
              'Verification Method',
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _MethodCard(
                    icon: Icons.mark_email_read_outlined,
                    title: 'Email OTP',
                    subtitle: 'Code sent to email',
                    selected: _signupVerificationMethod == VerificationChannel.email,
                    onTap: () => setState(() => _signupVerificationMethod = VerificationChannel.email),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MethodCard(
                    icon: Icons.sms_outlined,
                    title: 'Mobile OTP',
                    subtitle: 'Code sent to mobile',
                    selected: _signupVerificationMethod == VerificationChannel.phone,
                    onTap: () => setState(() => _signupVerificationMethod = VerificationChannel.phone),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Terms & Privacy Acceptance
            InkWell(
              onTap: () => setState(() => _acceptedTerms = !_acceptedTerms),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: Checkbox(
                        value: _acceptedTerms,
                        onChanged: (v) => setState(() => _acceptedTerms = v ?? false),
                        activeColor: AppColors.primaryGreen,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          text: 'I agree to the ',
                          style: TextStyle(fontSize: 12.5, color: palette.textSecondary, height: 1.35),
                          children: [
                            WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: InkWell(
                                onTap: _openTerms,
                                child: Text(
                                  'Terms of Service',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: AppColors.primaryGreen,
                                    fontWeight: FontWeight.w700,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),
                            ),
                            const TextSpan(text: ' & '),
                            WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: InkWell(
                                onTap: _openPrivacy,
                                child: Text(
                                  'Privacy Policy',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: AppColors.primaryGreen,
                                    fontWeight: FontWeight.w700,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),
                            ),
                            const TextSpan(text: ' (18+ attestation)'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Primary CTA
            AuthPrimaryButton(
              label: 'Send Verification Code',
              busy: busy,
              onPressed: busy ? null : _handleNewUserSignup,
            ),
          ],
        ),
      ),
    );
  }

  // --- Sign In Form (Existing User) ------------------------------------------

  Widget _buildSignInForm(AppPalette palette, AppLocalizations l10n, bool busy) {
    return FadeSlideIn(
      delay: const Duration(milliseconds: 160),
      child: Form(
        key: _signInFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // OTP Channel Selector (Phone OTP vs Email OTP)
            if (!_signInWithPassword) ...[
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: palette.isDark ? palette.surfaceVariant : AppColors.tealPale.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: palette.border.withValues(alpha: 0.5),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _ChannelTabButton(
                        icon: Icons.phone_android_rounded,
                        label: 'Mobile OTP',
                        active: _signInChannel == VerificationChannel.phone,
                        onTap: () {
                          FocusScope.of(context).unfocus();
                          setState(() {
                            _signInChannel = VerificationChannel.phone;
                            _signInIdentifierController.clear();
                          });
                        },
                      ),
                    ),
                    Expanded(
                      child: _ChannelTabButton(
                        icon: Icons.email_outlined,
                        label: 'Email OTP',
                        active: _signInChannel == VerificationChannel.email,
                        onTap: () {
                          FocusScope.of(context).unfocus();
                          setState(() {
                            _signInChannel = VerificationChannel.email;
                            _signInIdentifierController.clear();
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            if (!_signInWithPassword && _signInChannel == VerificationChannel.phone) ...[
              AuthTextField(
                key: const ValueKey('signin_phone_field'),
                controller: _signInIdentifierController,
                label: l10n.t('mobileNumber'),
                hint: '9876543210',
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _handleExistingUserSignIn(),
                prefixWidget: InkWell(
                  onTap: busy ? null : _pickSignInCountry,
                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 14, right: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_signInCountry.flag, style: const TextStyle(fontSize: 18)),
                        const SizedBox(width: 4),
                        Text(
                          _signInCountry.dialCode,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: palette.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(Icons.arrow_drop_down, size: 18, color: palette.textSecondary),
                      ],
                    ),
                  ),
                ),
              ),
            ] else ...[
              AuthTextField(
                key: ValueKey(_signInWithPassword ? 'signin_password_user_field' : 'signin_email_field'),
                controller: _signInIdentifierController,
                label: _signInWithPassword ? l10n.t('emailOrMobile') : l10n.t('emailAddress'),
                hint: 'you@example.com',
                icon: Icons.alternate_email_rounded,
                keyboardType: TextInputType.emailAddress,
                textInputAction: _signInWithPassword ? TextInputAction.next : TextInputAction.done,
                onSubmitted: (_) => _handleExistingUserSignIn(),
              ),
            ],

            if (_signInWithPassword) ...[
              const SizedBox(height: 14),
              AuthTextField(
                controller: _signInPasswordController,
                label: l10n.t('password'),
                hint: '••••••••',
                icon: Icons.lock_outline_rounded,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                validator: (v) => (v == null || v.isEmpty) ? 'Enter password' : null,
                onSubmitted: (_) => _handleExistingUserSignIn(),
                suffix: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    color: palette.textSecondary,
                  ),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
            ],

            const SizedBox(height: 8),
            Row(
              children: [
                Flexible(
                  child: InkWell(
                    onTap: () => setState(() => _rememberMe = !_rememberMe),
                    borderRadius: BorderRadius.circular(6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 22,
                          height: 22,
                          child: Checkbox(
                            value: _rememberMe,
                            onChanged: (v) => setState(() => _rememberMe = v ?? true),
                            activeColor: AppColors.primaryGreen,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            l10n.t('rememberMe'),
                            style: TextStyle(color: palette.textSecondary, fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                TextButton(
                  onPressed: busy ? null : _goToForgotPassword,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    l10n.t('forgotPasswordQ'),
                    style: TextStyle(color: AppColors.primaryGreen, fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 18),

            // CTA
            AuthPrimaryButton(
              label: _signInWithPassword ? l10n.t('signIn') : 'Send OTP',
              busy: busy,
              onPressed: busy ? null : _handleExistingUserSignIn,
            ),

            const SizedBox(height: 12),
            Center(
              child: TextButton(
                onPressed: () => setState(() => _signInWithPassword = !_signInWithPassword),
                child: Text(
                  _signInWithPassword ? 'Use Passwordless OTP instead' : 'Sign in with Password instead',
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Mode Toggle Button (Create Account / Sign In) ---------------------------

class _ModeTabButton extends StatelessWidget {
  const _ModeTabButton({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: active ? AppColors.primaryGreen : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: AppColors.primaryGreen.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: active ? Colors.white : palette.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

// --- Channel Tab Button (Mobile OTP / Email OTP) -----------------------------

class _ChannelTabButton extends StatelessWidget {
  const _ChannelTabButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: active ? AppColors.primaryGreen : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: AppColors.primaryGreen.withValues(alpha: 0.25),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: active ? Colors.white : palette.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: active ? Colors.white : palette.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Verification Method Card ------------------------------------------------

class _MethodCard extends StatelessWidget {
  const _MethodCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primaryGreen.withValues(alpha: 0.08)
              : (palette.isDark ? palette.surfaceVariant : Colors.white),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.primaryGreen : palette.border,
            width: selected ? 1.6 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: selected ? AppColors.primaryGreen : palette.textSecondary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                      color: selected ? AppColors.primaryGreen : palette.textPrimary,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: palette.textFaint,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(
                Icons.check_circle_rounded,
                size: 16,
                color: AppColors.primaryGreen,
              ),
          ],
        ),
      ),
    );
  }
}
