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
import 'otp_verification_screen.dart';
import 'phone_login_screen.dart';
import 'signup_screen.dart';

enum AuthMode {
  signIn,
  signUp,
}

/// Which identifier a new account verifies - and therefore the ONE it can log
/// in with afterwards.
///
/// Signup confirms exactly one channel. The other is kept on the profile as
/// contact detail, never as a credential: an identifier nobody proved they own
/// would let whoever claims that address or number into the account.
enum VerificationChannel {
  email,
  phone;

  String get label => switch (this) {
        VerificationChannel.email => 'Email',
        VerificationChannel.phone => 'Mobile number',
      };
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

  // Login - one field that takes either an email or a mobile number.
  final _signInIdentifierController = TextEditingController();
  CountryCode _signInCountry = kCountryCodes.first;

  /// True while the identifier reads as an email, so the country-code prefix
  /// hides itself instead of sitting uselessly beside an address.
  bool _identifierLooksLikeEmail = false;

  // Sign up controllers
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  CountryCode _signUpCountry = kCountryCodes.first;
  VerificationChannel _signupChannel = VerificationChannel.phone;
  bool _acceptedTerms = false;

  bool _rememberMe = true;
  bool _busy = false;
  bool _googleBusy = false;
  bool _guestBusy = false;

  @override
  void initState() {
    super.initState();
    _signInIdentifierController.addListener(_onIdentifierChanged);
  }

  @override
  void dispose() {
    _signInIdentifierController.removeListener(_onIdentifierChanged);
    _signInIdentifierController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _onIdentifierChanged() {
    final looksEmail =
        AuthValidators.looksLikeEmail(_signInIdentifierController.text);
    if (looksEmail != _identifierLooksLikeEmail) {
      setState(() => _identifierLooksLikeEmail = looksEmail);
    }
  }

  /// The login identifier as the backend sees it: a trimmed address, or the
  /// selected dial code joined to the typed digits.
  ///
  /// Returns null when the input is not yet a plausible email or number.
  ({String value, bool isEmail})? _readIdentifier() {
    final raw = _signInIdentifierController.text.trim();
    if (raw.isEmpty) return null;
    if (AuthValidators.looksLikeEmail(raw)) {
      return AuthValidators.isValidEmail(raw)
          ? (value: raw, isEmail: true)
          : null;
    }
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 6) return null;
    return (value: '${_signInCountry.dialCode}$digits', isEmail: false);
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
      // Refuse up front if either identifier is already spoken for - otherwise
      // Supabase would fail deep inside the OTP step with a cryptic message,
      // after the user had already waited for a code.
      //
      // identifierTaken, not accountExists: only ONE channel gets verified, so
      // the other lives on the profile without ever reaching auth.users. The
      // login-side check would call it free, and the duplicate would surface as
      // a failed profile INSERT once the code was already verified.
      if (await AuthService.instance.identifierTaken(email)) {
        _showMessage(
          'That email already has an INO account. Please log in instead.',
        );
        return;
      }
      if (await AuthService.instance.identifierTaken(fullPhone)) {
        _showMessage(
          'That mobile number already has an INO account. Please log in instead.',
        );
        return;
      }

      // Only the chosen channel is verified, and it becomes the credential.
      final metadata = {
        'full_name': name,
        'email': email,
        'phone': fullPhone,
        'accepted_terms': true,
        'attestation_18_plus': true,
      };
      if (_signupChannel == VerificationChannel.email) {
        await AuthService.instance.sendEmailOtp(email, data: metadata);
      } else {
        await AuthService.instance.sendPhoneOtp(fullPhone, data: metadata);
      }
      if (!mounted) return;
      _goToNewUserOtpScreen(
        name: name,
        email: email,
        phone: fullPhone,
        channel: _signupChannel,
      );
    } catch (e) {
      _showMessage(AuthService.formatAuthError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Signup verification: one code, to whichever channel the user chose.
  ///
  /// That channel becomes the account's login credential. The other identifier
  /// is written to the profile as contact detail and is deliberately NOT a way
  /// in - nobody proved ownership of it, so accepting it later would hand the
  /// account to whoever claimed that address or number.
  void _goToNewUserOtpScreen({
    required String name,
    required String email,
    required String phone,
    required VerificationChannel channel,
  }) {
    final isEmail = channel == VerificationChannel.email;
    final destination = isEmail ? email : phone;
    final metadata = {
      'full_name': name,
      'email': email,
      'phone': phone,
      'accepted_terms': true,
      'attestation_18_plus': true,
    };
    UserProfile? profile;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OtpVerificationScreen(
          title: isEmail ? 'Verify Your Email' : 'Verify Your Mobile Number',
          destination: destination,
          onResend: () => isEmail
              ? AuthService.instance.sendEmailOtp(email, data: metadata)
              : AuthService.instance.sendPhoneOtp(phone, data: metadata),
          onVerify: (code) async {
            final res = isEmail
                ? await AuthService.instance
                    .verifyEmailOtp(email: email, token: code)
                : await AuthService.instance
                    .verifyPhoneOtp(phone: phone, token: code);
            final user = res.user;
            if (user == null) return false;

            await AuthService.instance.recordTermsConsent(
              version: '1.0',
              attest18Plus: true,
            );

            try {
              profile = await UserRepository.instance.createProfile(
                authUserId: user.id,
                fullName: name,
                email: email,
                phone: phone,
              );
            } catch (_) {
              // A database trigger may already have written the row.
              profile =
                  await UserRepository.instance.getProfileByAuthId(user.id);
            }
            return true;
          },
          onVerified: (ctx) {
            final created = profile;
            if (created != null) {
              goToShell(ctx, created);
            } else {
              final user = AuthService.instance.currentUser;
              if (user != null) {
                routeAfterAuth(
                  authUserId: user.id,
                  fullName: name,
                  email: email,
                  phone: phone,
                );
              }
            }
          },
        ),
      ),
    );
  }

  // --- Existing User: Send OTP & Sign In -------------------------------------

  Future<void> _handleExistingUserSignIn() async {
    FocusScope.of(context).unfocus();

    final id = _readIdentifier();
    if (id == null) {
      _showMessage('Enter a valid email address or mobile number.');
      return;
    }

    setState(() => _busy = true);
    try {
      // The whole point of this pre-flight: an identifier with no account must
      // be told to sign up, NOT handed to signInWithOtp - which, left to its
      // own devices, would happily create a brand new empty account for it.
      if (!await AuthService.instance.accountExists(id.value)) {
        if (!mounted) return;
        // Most often this is someone who signed up with the OTHER identifier
        // and is reaching for the one they never verified, so say so rather
        // than a bare "not found".
        _showMessage(
          'No INO account uses that ${id.isEmail ? "email address" : "mobile number"}. '
          'If you signed up with your ${id.isEmail ? "mobile number" : "email"}, '
          'use that instead - otherwise create an account first.',
        );
        setState(() => _mode = AuthMode.signUp);
        return;
      }

      // shouldCreateUser:false is belt-and-braces behind the check above - the
      // account can have been deleted between the two calls.
      if (id.isEmail) {
        await AuthService.instance.sendEmailOtp(
          id.value,
          shouldCreateUser: false,
        );
      } else {
        await AuthService.instance.sendPhoneOtp(
          id.value,
          shouldCreateUser: false,
        );
      }
      if (!mounted) return;
      _goToExistingUserOtpScreen(destination: id.value, isEmail: id.isEmail);
    } catch (e) {
      _showMessage(AuthService.formatAuthError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
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
          title: 'Login Verification',
          destination: destination,
          onResend: () async {
            if (isEmail) {
              await AuthService.instance
                  .sendEmailOtp(destination, shouldCreateUser: false);
            } else {
              await AuthService.instance
                  .sendPhoneOtp(destination, shouldCreateUser: false);
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
            loadedProfile =
                await UserRepository.instance.getProfileByAuthId(user.id);
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
                phone: user.phone ?? (isEmail ? null : destination),
              );
            }
          },
        ),
      ),
    );
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

            // Which identifier to verify. Exactly one gets confirmed, and it
            // becomes the only way into the account - so the choice is made
            // here, explicitly, and spelled out below rather than discovered at
            // the next login.
            Text(
              'Send my code to',
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
                  child: _ChannelCard(
                    icon: Icons.sms_outlined,
                    title: 'Mobile OTP',
                    subtitle: 'Code by SMS',
                    selected: _signupChannel == VerificationChannel.phone,
                    onTap: busy
                        ? null
                        : () => setState(
                            () => _signupChannel = VerificationChannel.phone),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ChannelCard(
                    icon: Icons.mark_email_read_outlined,
                    title: 'Email OTP',
                    subtitle: 'Code by email',
                    selected: _signupChannel == VerificationChannel.email,
                    onTap: busy
                        ? null
                        : () => setState(
                            () => _signupChannel = VerificationChannel.email),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // The consequence of that choice, stated before they commit to it.
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.tealPale.withValues(alpha: 0.30),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: palette.border.withValues(alpha: 0.6)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 18, color: AppColors.primaryGreen),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'You will log in with your '
                      '${_signupChannel.label.toLowerCase()} from now on. '
                      'Signing in with the other one will not find this '
                      'account.',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: palette.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
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
    // The country prefix only makes sense while the field holds a number; the
    // moment an "@" appears it would just be noise beside an address.
    final showDialCode = !_identifierLooksLikeEmail;

    return FadeSlideIn(
      delay: const Duration(milliseconds: 160),
      child: Form(
        key: _signInFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AuthTextField(
              key: const ValueKey('login_identifier_field'),
              controller: _signInIdentifierController,
              label: l10n.t('emailOrMobile'),
              hint: 'you@example.com or 9876543210',
              icon: showDialCode ? null : Icons.alternate_email_rounded,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _handleExistingUserSignIn(),
              prefixWidget: showDialCode
                  ? InkWell(
                      onTap: busy ? null : _pickSignInCountry,
                      borderRadius: const BorderRadius.horizontal(
                          left: Radius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.only(left: 14, right: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_signInCountry.flag,
                                style: const TextStyle(fontSize: 18)),
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
                            Icon(Icons.arrow_drop_down,
                                size: 18, color: palette.textSecondary),
                          ],
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: 10),
            Text(
              'Enter the email or mobile number on your INO account - either '
              'one opens the same account.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: palette.textSecondary,
              ),
            ),

            const SizedBox(height: 12),
            Row(
              children: [
                SizedBox(
                  width: 22,
                  height: 22,
                  child: Checkbox(
                    value: _rememberMe,
                    onChanged: (v) => setState(() => _rememberMe = v ?? true),
                    activeColor: AppColors.primaryGreen,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(5)),
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: GestureDetector(
                    onTap: () => setState(() => _rememberMe = !_rememberMe),
                    child: Text(
                      l10n.t('rememberMe'),
                      style: TextStyle(
                          color: palette.textSecondary, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 18),
            AuthPrimaryButton(
              label: 'Send OTP',
              busy: busy,
              onPressed: busy ? null : _handleExistingUserSignIn,
            ),
          ],
        ),
      ),
    );
  }
}

/// One option in the signup "send my code to" picker.
class _ChannelCard extends StatelessWidget {
  const _ChannelCard({
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
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primaryGreen.withValues(alpha: 0.10)
              : palette.surfaceVariant.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? AppColors.primaryGreen
                : palette.border.withValues(alpha: 0.7),
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon,
                    size: 18,
                    color: selected
                        ? AppColors.primaryGreen
                        : palette.textSecondary),
                const Spacer(),
                if (selected)
                  Icon(Icons.check_circle_rounded,
                      size: 16, color: AppColors.primaryGreen),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(fontSize: 11.5, color: palette.textSecondary),
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

