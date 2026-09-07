import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/auth/auth_primary_button.dart';
import '../../widgets/auth/auth_scaffold.dart';
import '../../widgets/auth/otp_input.dart';
import '../../widgets/dashboard/fade_slide_in.dart';

/// Screen 5 - OTP Verification.
///
/// Backend-agnostic: it renders the 6-box code UI, a resend countdown and the
/// Verify CTA, delegating the actual work to callbacks so it can front any
/// provider (Supabase email OTP is wired by the signup flow today).
///
///   • [onVerify]   - validates the code; return true on success.
///   • [onResend]   - re-requests a code; restarts the countdown.
///   • [onVerified] - called with a live [BuildContext] after a successful
///                    verify, so the caller can continue the flow.
class OtpVerificationScreen extends StatefulWidget {
  const OtpVerificationScreen({
    super.key,
    required this.destination,
    required this.onVerify,
    required this.onVerified,
    this.onResend,
    this.onChangeDestination,
    this.title,
    this.length = 6,
    this.resendSeconds = 30,
  });

  /// Where the code was sent (email/number) - shown in the subtitle.
  final String destination;

  final Future<bool> Function(String code) onVerify;
  final void Function(BuildContext context) onVerified;
  final Future<void> Function()? onResend;
  final VoidCallback? onChangeDestination;

  /// Heading. Defaults to the localized "Verification Code" when omitted -
  /// it can't be a const default because it has to follow the active language.
  final String? title;
  final int length;
  final int resendSeconds;

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  String _code = '';
  bool _busy = false;
  bool _resending = false;
  String? _errorMessage;

  Timer? _timer;
  int _secondsLeft = 0;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _secondsLeft = widget.resendSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_secondsLeft <= 1) {
        t.cancel();
        setState(() => _secondsLeft = 0);
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  void _showMessage(String message, {bool isError = true}) {
    if (!mounted) return;
    setState(() {
      _errorMessage = isError ? message : null;
    });
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

  Future<void> _verify() async {
    final l10n = AppLocalizations.of(context);
    if (_code.length != widget.length) {
      _showMessage(
        l10n.t('otpEnterFull').replaceAll('{n}', '${widget.length}'),
      );
      return;
    }
    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    try {
      final ok = await widget.onVerify(_code);
      if (!mounted) return;
      if (ok) {
        widget.onVerified(context);
      } else {
        _showMessage(l10n.t('otpIncorrect'));
      }
    } catch (e) {
      _showMessage(AuthService.formatAuthError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    if (_secondsLeft > 0 || widget.onResend == null) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _resending = true;
      _errorMessage = null;
    });
    try {
      await widget.onResend!();
      if (!mounted) return;
      _showMessage(l10n.t('otpResent'), isError: false);
      _startCountdown();
    } catch (e) {
      _showMessage(AuthService.formatAuthError(e));
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final canResend = _secondsLeft == 0 && !_resending;
    final isEmail = widget.destination.contains('@');
    final changeLabel = isEmail ? 'Change Email' : 'Change Mobile Number';

    return AuthScaffold(
      showBack: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          FadeSlideIn(
            child: const _OtpBadge(),
          ),
          const SizedBox(height: 18),
          FadeSlideIn(
            delay: const Duration(milliseconds: 60),
            child: AuthPageTitle(widget.title ?? l10n.t('verificationCode')),
          ),
          const SizedBox(height: 8),
          FadeSlideIn(
            delay: const Duration(milliseconds: 110),
            child: Column(
              children: [
                Text.rich(
                  TextSpan(
                    text:
                        '${l10n.t('otpSentTo').replaceAll('{n}', '${widget.length}')}\n',
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textMuted,
                      height: 1.4,
                    ),
                    children: [
                      TextSpan(
                        text: widget.destination,
                        style: const TextStyle(
                          color: AppColors.textDark,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                TextButton.icon(
                  onPressed: () {
                    if (widget.onChangeDestination != null) {
                      widget.onChangeDestination!();
                    } else {
                      Navigator.of(context).pop();
                    }
                  },
                  icon: Icon(Icons.edit_outlined, size: 14, color: AppColors.primaryGreen),
                  label: Text(
                    changeLabel,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryGreen,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          if (_errorMessage != null) ...[
            FadeSlideIn(
              delay: const Duration(milliseconds: 130),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.critical.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.critical.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, color: AppColors.critical, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(
                          color: AppColors.critical,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          FadeSlideIn(
            delay: const Duration(milliseconds: 160),
            child: OtpInput(
              length: widget.length,
              enabled: !_busy,
              onChanged: (v) {
                setState(() {
                  _code = v;
                  _errorMessage = null;
                });
              },
              onCompleted: (_) => _verify(),
            ),
          ),
          const SizedBox(height: 22),

          FadeSlideIn(
            delay: const Duration(milliseconds: 210),
            child: AuthPrimaryButton(
              label: l10n.t('verify'),
              busy: _busy,
              onPressed: _busy ? null : _verify,
            ),
          ),
          const SizedBox(height: 14),

          if (widget.onResend != null)
            FadeSlideIn(
              delay: const Duration(milliseconds: 250),
              child: Center(
                child: canResend
                    ? TextButton(
                        onPressed: _resend,
                        child: Text(
                          l10n.t('resendCode'),
                          style: TextStyle(
                            color: AppColors.primaryGreen,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      )
                    : Text(
                        _resending
                            ? l10n.t('sending')
                            : l10n.t('resendCodeIn').replaceAll(
                                '{t}',
                                '0:${_secondsLeft.toString().padLeft(2, '0')}',
                              ),
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
              ),
            ),
          const SizedBox(height: 20),

          // Decorative trust badge from the Divine Glass mockup footer.
          FadeSlideIn(
            delay: const Duration(milliseconds: 300),
            child: const Center(child: _SecuredFooterChip()),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

/// The "Secured by INO Vault Encryption" glass pill from the mockup footer -
/// purely decorative reassurance.
class _SecuredFooterChip extends StatelessWidget {
  const _SecuredFooterChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.tealPale, width: 1),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_rounded, size: 14, color: AppColors.textMuted),
          SizedBox(width: 8),
          Flexible(
            child: Text(
              'SECURED BY INO VAULT ENCRYPTION',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
                color: AppColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The gradient shield-with-code badge shown at the top of the OTP screen.
class _OtpBadge extends StatelessWidget {
  const _OtpBadge();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          gradient: AppColors.brandGradient,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryGreen.withValues(alpha: 0.35),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: const Icon(
          Icons.mark_email_read_rounded,
          color: Colors.white,
          size: 32,
        ),
      ),
    );
  }
}
