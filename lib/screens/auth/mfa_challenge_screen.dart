import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../l10n/app_localizations.dart';
import '../../services/auth_service.dart';
import '../../services/two_factor_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/auth/auth_primary_button.dart';
import '../../widgets/auth/auth_scaffold.dart';
import '../../widgets/auth/otp_input.dart';
import '../../widgets/dashboard/fade_slide_in.dart';
import 'auth_flow.dart';

/// Post-password MFA gate. Shown when the session is `aal1` and a verified
/// TOTP factor exists. Completing the code promotes the session to `aal2` and
/// continues [routeAfterAuth]. Back signs out so an aal1 session cannot linger.
class MfaChallengeScreen extends StatefulWidget {
  const MfaChallengeScreen({
    super.key,
    required this.authUserId,
    required this.fullName,
    required this.email,
  });

  final String authUserId;
  final String fullName;
  final String email;

  @override
  State<MfaChallengeScreen> createState() => _MfaChallengeScreenState();
}

class _MfaChallengeScreenState extends State<MfaChallengeScreen> {
  String _code = '';
  bool _busy = false;
  bool _signingOut = false;

  Future<void> _abort() async {
    if (_signingOut) return;
    setState(() => _signingOut = true);
    try {
      await AuthService.instance.signOut();
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  Future<void> _verify() async {
    final l10n = AppLocalizations.of(context);
    if (_code.length != 6 || _busy) return;
    setState(() => _busy = true);
    try {
      await TwoFactorService.instance.challengeAndVerifyCurrentSession(_code);
      if (!mounted) return;
      await routeAfterAuth(
        authUserId: widget.authUserId,
        fullName: widget.fullName,
        email: widget.email,
        mfaSatisfied: true,
      );
    } on AuthException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.t('codeIncorrectExpired')),
          backgroundColor: AppColors.critical,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.t('couldNotVerifyCode')),
          backgroundColor: AppColors.critical,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AuthScaffold(
      showBack: true,
      onBack: _signingOut ? null : () { _abort(); },
      child: Column(
        children: [
          const SizedBox(height: 12),
          FadeSlideIn(
            child: Text(
              l10n.t('mfaChallengeTitle'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: AppColors.textDark,
              ),
            ),
          ),
          const SizedBox(height: 10),
          FadeSlideIn(
            delay: const Duration(milliseconds: 80),
            child: Text(
              l10n.t('mfaChallengeBody'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                height: 1.5,
                color: AppColors.textMuted,
              ),
            ),
          ),
          const SizedBox(height: 34),
          FadeSlideIn(
            delay: const Duration(milliseconds: 160),
            child: OtpInput(
              length: 6,
              enabled: !_busy && !_signingOut,
              onChanged: (v) => setState(() => _code = v),
              onCompleted: (_) => _verify(),
            ),
          ),
          const SizedBox(height: 30),
          FadeSlideIn(
            delay: const Duration(milliseconds: 210),
            child: AuthPrimaryButton(
              label: l10n.t('verify'),
              busy: _busy,
              onPressed: (_busy || _signingOut) ? null : _verify,
            ),
          ),
        ],
      ),
    );
  }
}
