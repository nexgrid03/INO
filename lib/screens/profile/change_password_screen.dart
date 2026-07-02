import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/account_service.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/auth/auth_text_field.dart';
import '../../widgets/profile/settings_scaffold.dart';
import '../../widgets/security/biometric_ux.dart';

/// Change Password — verifies the current password against Supabase Auth, checks
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
    final v = value ?? '';
    if (v.isEmpty) return 'Enter a new password';
    if (v.length < 8) return 'Use at least 8 characters';
    if (AccountService.scorePassword(v) == PasswordStrength.weak) {
      return 'Add letters, numbers or symbols to strengthen it';
    }
    if (v == _current.text) return 'New password must differ from the current one';
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await AccountService.instance.changePassword(
        email: widget.email,
        currentPassword: _current.text,
        newPassword: _next.text,
      );
      if (!mounted) return;
      BiometricUx.successSnack(context, 'Password updated successfully.');
      Navigator.of(context).pop(true);
    } on AuthException catch (e) {
      developer.log('changePassword auth error: ${e.message}',
          name: 'account', error: e);
      if (!mounted) return;
      final wrong = e.message.toLowerCase().contains('invalid') ||
          e.message.toLowerCase().contains('credential');
      BiometricUx.errorSnack(
        context,
        wrong ? 'Your current password is incorrect.' : e.message,
      );
    } catch (e) {
      developer.log('changePassword error: $e', name: 'account', error: e);
      if (!mounted) return;
      BiometricUx.errorSnack(
          context, 'Could not change your password. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SettingsScaffold(
      title: 'Change Password',
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.sm,
              AppSpacing.screen, AppSpacing.xl),
          children: [
            Text(
              'For your security, confirm your current password before setting a new one.',
              style: AppText.body
                  .copyWith(color: palette.textSecondary, height: 1.5),
            ),
            const SizedBox(height: AppSpacing.lg),
            AuthTextField(
              controller: _current,
              label: 'Current password',
              icon: Icons.lock_outline_rounded,
              obscureText: _obscureCurrent,
              textInputAction: TextInputAction.next,
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'Enter your current password' : null,
              suffix: _eye(_obscureCurrent,
                  () => setState(() => _obscureCurrent = !_obscureCurrent)),
            ),
            const SizedBox(height: AppSpacing.md),
            AuthTextField(
              controller: _next,
              label: 'New password',
              icon: Icons.lock_reset_rounded,
              obscureText: _obscureNext,
              textInputAction: TextInputAction.next,
              validator: _validateNew,
              suffix: _eye(_obscureNext,
                  () => setState(() => _obscureNext = !_obscureNext)),
            ),
            const SizedBox(height: AppSpacing.sm),
            _StrengthMeter(strength: _strength, show: _next.text.isNotEmpty),
            const SizedBox(height: AppSpacing.md),
            AuthTextField(
              controller: _confirm,
              label: 'Confirm new password',
              icon: Icons.check_circle_outline_rounded,
              obscureText: _obscureNext,
              textInputAction: TextInputAction.done,
              validator: (v) =>
                  v != _next.text ? 'Passwords do not match' : null,
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: AppSpacing.xl),
            SettingsPrimaryButton(
              label: 'Update Password',
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
          Text(strength.label,
              style: AppText.caption
                  .copyWith(color: _color, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
