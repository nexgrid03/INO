import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../l10n/app_localizations.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/auth/auth_primary_button.dart';
import '../../widgets/auth/auth_scaffold.dart';
import '../../widgets/auth/auth_text_field.dart';
import '../../widgets/dashboard/fade_slide_in.dart';
import 'auth_validators.dart';

/// Screen 6 - Forgot Password.
///
/// A single-purpose reset request: enter the registered email (mobile coming
/// later) and we send the reset instructions via Supabase. On success it shows
/// a calm confirmation state rather than bouncing the user around.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialIdentifier});

  /// Pre-fills the field (e.g. an email already typed on the login screen).
  final String? initialIdentifier;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialIdentifier ?? '');

  bool _busy = false;
  bool _sent = false;
  String _sentTo = '';

  @override
  void dispose() {
    _controller.dispose();
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

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context);
    final identifier = _controller.text.trim();

    if (!AuthValidators.looksLikeEmail(identifier)) {
      _showMessage(l10n.t('mobileResetSoon'));
      return;
    }

    setState(() => _busy = true);
    try {
      await AuthService.instance.sendPasswordReset(identifier);
      if (!mounted) return;
      setState(() {
        _sent = true;
        _sentTo = identifier;
      });
    } on AuthException catch (e) {
      _showMessage(e.message);
    } catch (_) {
      _showMessage(l10n.t('resetCodeError'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      showBack: true,
      child: _sent ? _buildSent() : _buildForm(),
    );
  }

  Widget _buildForm() {
    final l10n = AppLocalizations.of(context);
    final validate = AuthValidators.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        FadeSlideIn(child: const _LockBadge()),
        const SizedBox(height: 26),
        FadeSlideIn(
          delay: const Duration(milliseconds: 60),
          child: AuthPageTitle(l10n.t('resetPassword')),
        ),
        const SizedBox(height: 10),
        FadeSlideIn(
          delay: const Duration(milliseconds: 110),
          child: Text(
            l10n.t('resetPasswordSubtitle'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14.5,
              color: AppColors.textMuted,
              height: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 30),
        Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: FadeSlideIn(
            delay: const Duration(milliseconds: 160),
            child: AuthTextField(
              controller: _controller,
              label: l10n.t('emailOrMobile'),
              hint: 'you@example.com',
              icon: Icons.alternate_email_rounded,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.username],
              validator: validate.emailOrPhone,
              onSubmitted: (_) => _send(),
            ),
          ),
        ),
        const SizedBox(height: 26),
        FadeSlideIn(
          delay: const Duration(milliseconds: 210),
          child: AuthPrimaryButton(
            label: l10n.t('sendVerificationCode'),
            busy: _busy,
            onPressed: _busy ? null : _send,
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildSent() {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 40),
        FadeSlideIn(
          child: Center(
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: AppColors.primaryGreen.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.mark_email_read_rounded,
                color: AppColors.primaryGreen,
                size: 46,
              ),
            ),
          ),
        ),
        const SizedBox(height: 28),
        FadeSlideIn(
          delay: const Duration(milliseconds: 60),
          child: Text(
            l10n.t('checkYourInbox'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
        ),
        const SizedBox(height: 12),
        FadeSlideIn(
          delay: const Duration(milliseconds: 110),
          child: Text.rich(
            TextSpan(
              text: '${l10n.t('resetInstructionsSentTo')}\n',
              style: const TextStyle(
                fontSize: 14.5,
                color: AppColors.textMuted,
                height: 1.5,
              ),
              children: [
                TextSpan(
                  text: _sentTo,
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 34),
        FadeSlideIn(
          delay: const Duration(milliseconds: 160),
          child: AuthPrimaryButton(
            label: l10n.t('backToSignIn'),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        const SizedBox(height: 14),
        FadeSlideIn(
          delay: const Duration(milliseconds: 200),
          child: Center(
            child: TextButton(
              onPressed: _busy ? null : () => setState(() => _sent = false),
              child: Text(
                l10n.t('useDifferentEmail'),
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The gradient lock badge shown atop the reset form.
class _LockBadge extends StatelessWidget {
  const _LockBadge();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 84,
        height: 84,
        decoration: BoxDecoration(
          gradient: AppColors.brandGradient,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryGreen.withValues(alpha: 0.35),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: const Icon(
          Icons.lock_reset_rounded,
          color: Colors.white,
          size: 40,
        ),
      ),
    );
  }
}
