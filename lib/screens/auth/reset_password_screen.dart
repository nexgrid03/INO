import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../l10n/app_localizations.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/auth/auth_primary_button.dart';
import '../../widgets/auth/auth_scaffold.dart';
import '../../widgets/auth/auth_text_field.dart';
import '../../widgets/dashboard/fade_slide_in.dart';
import 'auth_flow.dart';
import 'auth_validators.dart';

/// Screen for entering and confirming a new password after verifying recovery OTP.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({
    super.key,
    required this.email,
  });

  final String email;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _busy = false;
  bool _obscured = true;
  bool _confirmObscured = true;

  @override
  void dispose() {
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context);
    final newPassword = _passwordController.text.trim();

    setState(() => _busy = true);
    try {
      final res = await AuthService.instance.updatePassword(newPassword);
      final user = res.user;
      if (!mounted) return;
      _showMessage(l10n.t('passwordUpdated'), isError: false);

      if (user != null) {
        await routeAfterAuth(
          authUserId: user.id,
          fullName: (user.userMetadata?['full_name'] as String?) ?? 'INO User',
          email: user.email ?? widget.email,
        );
      } else {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on AuthException catch (e) {
      _showMessage(e.message);
    } catch (e) {
      _showMessage('Failed to update password: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final validate = AuthValidators.of(context);

    return AuthScaffold(
      showBack: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          FadeSlideIn(
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.tealMist,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.tealPale, width: 1.5),
              ),
              child: Icon(
                Icons.lock_reset_rounded,
                color: AppColors.primaryGreen,
                size: 28,
              ),
            ),
          ),
          const SizedBox(height: 26),
          FadeSlideIn(
            delay: const Duration(milliseconds: 60),
            child: AuthPageTitle(l10n.t('setNewPassword')),
          ),
          const SizedBox(height: 10),
          FadeSlideIn(
            delay: const Duration(milliseconds: 110),
            child: Text(
              l10n.t('setNewPasswordSubtitle'),
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
            child: Column(
              children: [
                FadeSlideIn(
                  delay: const Duration(milliseconds: 160),
                  child: AuthTextField(
                    controller: _passwordController,
                    label: l10n.t('newPassword'),
                    hint: '••••••••',
                    icon: Icons.lock_outline_rounded,
                    obscureText: _obscured,
                    textInputAction: TextInputAction.next,
                    suffix: IconButton(
                      onPressed: () => setState(() => _obscured = !_obscured),
                      icon: Icon(
                        _obscured
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: AppColors.textMuted,
                      ),
                    ),
                    validator: validate.password,
                  ),
                ),
                const SizedBox(height: 18),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 210),
                  child: AuthTextField(
                    controller: _confirmController,
                    label: l10n.t('confirmPassword'),
                    hint: '••••••••',
                    icon: Icons.lock_outline_rounded,
                    obscureText: _confirmObscured,
                    textInputAction: TextInputAction.done,
                    suffix: IconButton(
                      onPressed: () =>
                          setState(() => _confirmObscured = !_confirmObscured),
                      icon: Icon(
                        _confirmObscured
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: AppColors.textMuted,
                      ),
                    ),
                    validator: (val) {
                      if (val == null || val.isEmpty) {
                        return l10n.t('confirmPasswordRequired');
                      }
                      if (val != _passwordController.text) {
                        return l10n.t('passwordsDoNotMatch');
                      }
                      return null;
                    },
                    onSubmitted: (_) => _submit(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          FadeSlideIn(
            delay: const Duration(milliseconds: 260),
            child: AuthPrimaryButton(
              label: l10n.t('savePassword'),
              busy: _busy,
              onPressed: _busy ? null : _submit,
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
