import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/country_code.dart';
import '../../models/user_profile.dart';
import '../../screens/auth/auth_validators.dart';
import '../../screens/auth/login_screen.dart'; // VerificationChannel
import '../../services/account_security_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../auth/auth_primary_button.dart';
import '../auth/auth_text_field.dart';
import '../auth/country_code_sheet.dart';
import '../auth/otp_input.dart';
import '../pressable_scale.dart';

/// Opens a bottom sheet that leads the user through adding and verifying their
/// second entity (email or mobile number) to attach it to their existing account.
Future<UserProfile?> showLinkEntitySheet(
  BuildContext context, {
  required UserProfile profile,
  required VerificationChannel channel,
}) {
  return showModalBottomSheet<UserProfile>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => LinkEntitySheet(
      profile: profile,
      channel: channel,
    ),
  );
}

class LinkEntitySheet extends StatefulWidget {
  const LinkEntitySheet({
    super.key,
    required this.profile,
    required this.channel,
  });

  final UserProfile profile;
  final VerificationChannel channel;

  @override
  State<LinkEntitySheet> createState() => _LinkEntitySheetState();
}

class _LinkEntitySheetState extends State<LinkEntitySheet> {
  int _step = 0; // 0 = input, 1 = otp
  bool _busy = false;
  String? _errorMessage;

  // Form controllers
  late final TextEditingController _inputController;
  CountryCode _countryCode = kCountryCodes.first;

  // OTP state
  String _otpCode = '';
  int _resendSeconds = 30;
  Timer? _resendTimer;
  String _targetDestination = '';

  bool get _isEmail => widget.channel == VerificationChannel.email;

  @override
  void initState() {
    super.initState();
    final initialText = _isEmail
        ? widget.profile.email
        : (widget.profile.phone ?? '');
    _inputController = TextEditingController(
      text: _isEmail
          ? (initialText.contains('@') ? initialText : '')
          : (initialText.replaceAll(RegExp(r'[^0-9]'), '')),
    );
  }

  @override
  void dispose() {
    _inputController.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _resendTimer?.cancel();
    setState(() => _resendSeconds = 30);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_resendSeconds <= 1) {
        t.cancel();
        setState(() => _resendSeconds = 0);
      } else {
        setState(() => _resendSeconds--);
      }
    });
  }

  Future<void> _sendCode() async {
    FocusScope.of(context).unfocus();
    final raw = _inputController.text.trim();
    if (_isEmail) {
      if (!AuthValidators.isValidEmail(raw)) {
        setState(() => _errorMessage = 'Please enter a valid email address.');
        return;
      }
    } else {
      final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.length < 6 || digits.length > 14) {
        setState(() => _errorMessage = 'Please enter a valid mobile number.');
        return;
      }
    }

    final destination = _isEmail
        ? raw
        : '${_countryCode.dialCode}${raw.replaceAll(RegExp(r'[^0-9]'), '')}';

    setState(() {
      _busy = true;
      _errorMessage = null;
      _targetDestination = destination;
    });

    try {
      if (_isEmail) {
        await AccountSecurityService.instance.sendEmailLinkOtp(destination);
      } else {
        await AccountSecurityService.instance.sendPhoneLinkOtp(destination);
      }

      if (!mounted) return;
      _startCountdown();
      setState(() {
        _step = 1;
        _busy = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _errorMessage = AuthService.formatAuthError(e);
        });
      }
    }
  }

  Future<void> _resendCode() async {
    if (_resendSeconds > 0 || _busy) return;
    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    try {
      if (_isEmail) {
        await AccountSecurityService.instance.sendEmailLinkOtp(_targetDestination);
      } else {
        await AccountSecurityService.instance.sendPhoneLinkOtp(_targetDestination);
      }
      if (!mounted) return;
      _startCountdown();
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Verification code resent to $_targetDestination'),
          backgroundColor: AppColors.primaryGreen,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _errorMessage = AuthService.formatAuthError(e);
        });
      }
    }
  }

  Future<void> _verifyCode() async {
    if (_otpCode.length < 6) {
      setState(() => _errorMessage = 'Please enter the complete 6-digit code.');
      return;
    }

    setState(() {
      _busy = true;
      _errorMessage = null;
    });

    try {
      final UserProfile updated;
      if (_isEmail) {
        updated = await AccountSecurityService.instance.verifyAndSaveEmailLink(
          email: _targetDestination,
          token: _otpCode,
          currentProfile: widget.profile,
        );
      } else {
        updated = await AccountSecurityService.instance.verifyAndSavePhoneLink(
          phone: _targetDestination,
          token: _otpCode,
          currentProfile: widget.profile,
        );
      }

      if (!mounted) return;
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop(updated);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _errorMessage = AuthService.formatAuthError(e);
        });
      }
    }
  }

  Future<void> _pickCountry() async {
    final picked = await showCountryCodePicker(context, initial: _countryCode);
    if (picked != null && mounted) {
      setState(() => _countryCode = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return AnimatedPadding(
      padding: EdgeInsets.only(bottom: bottomInset),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: Container(
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppRadius.large),
          ),
          border: Border.all(color: palette.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 28,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screen,
              AppSpacing.sm,
              AppSpacing.screen,
              AppSpacing.lg,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Grip handle
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: palette.textFaint.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // Header Badge + Title
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primaryGreen.withValues(alpha: 0.12),
                          border: Border.all(
                            color: AppColors.primaryGreen.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Icon(
                          _isEmail
                              ? Icons.mail_lock_rounded
                              : Icons.phone_android_rounded,
                          color: AppColors.primaryGreen,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _step == 0
                                  ? (_isEmail
                                      ? 'Verify Email Address'
                                      : 'Verify Mobile Number')
                                  : 'Enter Verification Code',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: palette.textPrimary,
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _step == 0
                                  ? (_isEmail
                                      ? 'Secure your account & enable email sign-in'
                                      : 'Secure your account & enable SMS sign-in')
                                  : 'Code sent to $_targetDestination',
                              style: TextStyle(
                                fontSize: 13,
                                color: palette.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icon(
                          Icons.close_rounded,
                          color: palette.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  if (_errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.critical.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.critical.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            color: AppColors.critical,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.critical,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],

                  if (_step == 0) ...[
                    // Input step
                    if (_isEmail)
                      AuthTextField(
                        controller: _inputController,
                        label: 'Email Address',
                        hint: 'name@example.com',
                        icon: Icons.mail_outline_rounded,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _sendCode(),
                      )
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Mobile Number',
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              GestureDetector(
                                onTap: _pickCountry,
                                child: Container(
                                  height: 52,
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  decoration: BoxDecoration(
                                    color: palette.isDark
                                        ? palette.surfaceVariant
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: palette.border, width: 1.2),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        _countryCode.flag,
                                        style: const TextStyle(fontSize: 20),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        _countryCode.dialCode,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 15,
                                          color: palette.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Icon(
                                        Icons.arrow_drop_down_rounded,
                                        color: palette.textSecondary,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextFormField(
                                  controller: _inputController,
                                  keyboardType: TextInputType.phone,
                                  textInputAction: TextInputAction.done,
                                  onFieldSubmitted: (_) => _sendCode(),
                                  style: TextStyle(
                                    color: palette.textPrimary,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: '98765 43210',
                                    floatingLabelBehavior: FloatingLabelBehavior.never,
                                    isDense: true,
                                    filled: true,
                                    fillColor: palette.isDark
                                        ? palette.surfaceVariant
                                        : Colors.white,
                                    prefixIcon: Icon(
                                      Icons.phone_outlined,
                                      color: AppColors.primaryGreen.withValues(alpha: 0.65),
                                    ),
                                    hintStyle: TextStyle(
                                      color: palette.textFaint,
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 16,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: BorderSide(color: palette.border, width: 1.2),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: BorderSide(color: palette.border, width: 1.2),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: BorderSide(color: AppColors.primaryGreen, width: 1.6),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    const SizedBox(height: AppSpacing.lg),
                    AuthPrimaryButton(
                      label: 'Send Verification Code',
                      busy: _busy,
                      onPressed: _busy ? null : _sendCode,
                    ),
                  ] else ...[
                    // OTP step
                    Center(
                      child: OtpInput(
                        length: 6,
                        enabled: !_busy,
                        onChanged: (code) => _otpCode = code,
                        onCompleted: (code) {
                          _otpCode = code;
                          _verifyCode();
                        },
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () {
                                  setState(() {
                                    _step = 0;
                                    _errorMessage = null;
                                  });
                                },
                          child: Text(
                            'Change ${_isEmail ? "Email" : "Number"}',
                            style: TextStyle(
                              fontSize: 13,
                              color: palette.textSecondary,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: (_resendSeconds == 0 && !_busy)
                              ? _resendCode
                              : null,
                          child: PressableScale(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              child: Text(
                                _resendSeconds > 0
                                    ? 'Resend in ${_resendSeconds}s'
                                    : 'Resend Code',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _resendSeconds > 0
                                      ? palette.textFaint
                                      : AppColors.primaryGreen,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    AuthPrimaryButton(
                      label: 'Verify & Link Account',
                      busy: _busy,
                      onPressed: _busy ? null : _verifyCode,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
