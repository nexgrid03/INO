import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../l10n/app_localizations.dart';
import '../../services/account_service.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/auth/auth_text_field.dart';
import '../../widgets/profile/settings_scaffold.dart';
import '../../widgets/security/biometric_ux.dart';

/// Change Password - verifies the current password against Supabase Auth, checks
/// the new password's strength, then updates the credential in the backend.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key, required this.email});

  /// The signed-in user's email, used to re-authenticate the current password.
  final String email;

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();

  bool _obscureCurrent = true;
  bool _obscureNext = true;
  bool _busy = false;
  PasswordStrength _strength = PasswordStrength.weak;

  @override
  void initState() {
    super.initState();
    _next.addListener(() {
      final s = AccountService.scorePassword(_next.text);
      if (s != _strength) setState(() => _strength = s);
    });
  }

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String? _validateNew(String? value) {
    final l10n = AppLocalizations.of(context);
    final v = value ?? '';
    if (v.isEmpty) return l10n.t('enterNewPassword');
    if (v.length < 8) return l10n.t('useAtLeast8Chars');
    if (AccountService.scorePassword(v) == PasswordStrength.weak) {
      return l10n.t('strengthenPassword');
    }
    if (v == _current.text) return l10n.t('newMustDiffer');
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await AccountService.instance.changePassword(
        email: widget.email,
        currentPassword: _current.text,
        newPassword: _next.text,
      );
      if (!mounted) return;
      BiometricUx.successSnack(context, l10n.t('passwordUpdated'));
      Navigator.of(context).pop(true);
    } on AuthException catch (e) {
      developer.log('changePassword auth error: ${e.message}',
          name: 'account', error: e);
      if (!mounted) return;
      final wrong = e.message.toLowerCase().contains('invalid') ||
          e.message.toLowerCase().contains('credential');
      BiometricUx.errorSnack(
        context,
        wrong ? l10n.t('currentPasswordIncorrect') : e.message,
      );
    } catch (e) {
      developer.log('changePassword error: $e', name: 'account', error: e);
      if (!mounted) return;
      BiometricUx.errorSnack(context, l10n.t('couldNotChangePassword'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return SettingsScaffold(
      title: l10n.t('changePassword'),
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.sm,
              AppSpacing.screen, AppSpacing.xl),
          children: [
            SettingsCard(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.t('confirmCurrentPasswordIntro'),
                    style: AppText.body.copyWith(
                      color: palette.textPrimary,
                      height: 1.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AuthTextField(
                    controller: _current,
                    label: l10n.t('currentPassword'),
                    icon: Icons.lock_outline_rounded,
                    obscureText: _obscureCurrent,
                    textInputAction: TextInputAction.next,
                    validator: (v) => (v == null || v.isEmpty)
                        ? l10n.t('enterCurrentPassword')
                        : null,
                    suffix: _eye(
                        _obscureCurrent,
                        () => setState(
                            () => _obscureCurrent = !_obscureCurrent)),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AuthTextField(
                    controller: _next,
                    label: l10n.t('newPassword'),
                    icon: Icons.lock_reset_rounded,
                    obscureText: _obscureNext,
                    textInputAction: TextInputAction.next,
                    validator: _validateNew,
                    suffix: _eye(_obscureNext,
                        () => setState(() => _obscureNext = !_obscureNext)),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _StrengthMeter(
                      strength: _strength, show: _next.text.isNotEmpty),
                  const SizedBox(height: AppSpacing.md),
                  AuthTextField(
                    controller: _confirm,
                    label: l10n.t('confirmNewPassword'),
                    icon: Icons.check_circle_outline_rounded,
                    obscureText: _obscureNext,
                    textInputAction: TextInputAction.done,
                    validator: (v) =>
                        v != _next.text ? l10n.t('passwordsDoNotMatch') : null,
                    onSubmitted: (_) => _submit(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            SettingsPrimaryButton(
              label: l10n.t('updatePassword'),
              icon: Icons.shield_rounded,
              busy: _busy,
              onPressed: _busy ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }

  Widget _eye(bool obscured, VoidCallback onTap) => IconButton(
        icon: Icon(
          obscured ? Icons.visibility_off_rounded : Icons.visibility_rounded,
          color: AppColors.textMuted,
          size: 20,
        ),
        onPressed: onTap,
      );
}

class _StrengthMeter extends StatelessWidget {
  const _StrengthMeter({required this.strength, required this.show});

  final PasswordStrength strength;
  final bool show;

  Color get _color => switch (strength) {
        PasswordStrength.weak => AppColors.critical,
        PasswordStrength.fair => AppColors.warning,
        PasswordStrength.good => AppColors.lightBlue,
        PasswordStrength.strong => AppColors.primaryGreen,
      };

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return AnimatedOpacity(
      opacity: show ? 1 : 0,
      duration: const Duration(milliseconds: 200),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: SizedBox(
                height: 6,
                child: Stack(
                  children: [
                    Container(color: palette.surfaceVariant),
                    FractionallySizedBox(
                      widthFactor: strength.fraction,
                      child: DecoratedBox(
                          decoration: BoxDecoration(color: _color)),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(strength.label(AppLocalizations.of(context)),
              style: AppText.caption
                  .copyWith(color: _color, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
