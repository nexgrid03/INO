import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/account_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/auth/auth_text_field.dart';
import '../../widgets/profile/settings_scaffold.dart';
import '../../widgets/security/biometric_ux.dart';
import '../auth/login_screen.dart';

/// Delete Account — a deliberately high-friction flow: an explicit warning, a
/// type-to-confirm gate, and re-authentication, before permanently removing the
/// user's files, documents and profile.
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key, required this.email});

  final String email;

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final _confirmWord = TextEditingController();
  final _password = TextEditingController();
  bool _wordOk = false;
  bool _busy = false;

  /// Whether this account uses an email/password credential (so we can require
  /// a password re-auth). Social-only accounts re-auth via their live session.
  bool get _hasPassword {
    try {
      final user = AuthService.instance.currentUser;
      final provider = user?.appMetadata['provider'] as String?;
      final providers =
          (user?.appMetadata['providers'] as List?)?.cast<String>() ??
              const [];
      // Default to requiring a password unless we can positively identify a
      // social-only account.
      if (provider == null && providers.isEmpty) return true;
      return provider == 'email' || providers.contains('email');
    } catch (_) {
      return true; // Safer default: ask for the password.
    }
  }

  @override
  void initState() {
    super.initState();
    _confirmWord.addListener(() {
      final ok = _confirmWord.text.trim().toUpperCase() == 'DELETE';
      if (ok != _wordOk) setState(() => _wordOk = ok);
    });
    // Rebuild as the password is typed so the submit button enables correctly.
    _password.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _confirmWord.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _wordOk && (!_hasPassword || _password.text.isNotEmpty) && !_busy;

  Future<void> _delete() async {
    if (!_canSubmit) return;
    setState(() => _busy = true);
    try {
      // Re-authenticate email/password accounts before anything destructive.
      if (_hasPassword) {
        await AccountService.instance
            .reauthenticate(email: widget.email, password: _password.text);
      }
      await AccountService.instance.deleteAccount();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } on AuthException catch (e) {
      developer.log('delete reauth failed: ${e.message}', name: 'account');
      if (!mounted) return;
      BiometricUx.errorSnack(context, 'Your password is incorrect.');
    } catch (e) {
      developer.log('delete error: $e', name: 'account', error: e);
      if (!mounted) return;
      BiometricUx.errorSnack(
          context, 'Could not delete your account. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SettingsScaffold(
      title: 'Delete Account',
      child: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.screen, AppSpacing.md, AppSpacing.screen, AppSpacing.xl),
        children: [
          Center(
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.critical.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.warning_amber_rounded,
                  color: AppColors.critical, size: 36),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text('This can’t be undone',
              textAlign: TextAlign.center,
              style: AppText.headline.copyWith(color: palette.textPrimary)),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Deleting your account permanently removes your documents, uploaded '
            'files, backups and profile. You will be signed out immediately.',
            textAlign: TextAlign.center,
            style:
                AppText.body.copyWith(color: palette.textSecondary, height: 1.5),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text('Type DELETE to confirm',
              style: AppText.subtitle.copyWith(color: palette.textPrimary)),
          const SizedBox(height: AppSpacing.xs),
          AuthTextField(
            controller: _confirmWord,
            label: 'Confirmation',
            hint: 'DELETE',
            icon: Icons.gpp_bad_rounded,
            textCapitalization: TextCapitalization.characters,
          ),
          if (_hasPassword) ...[
            const SizedBox(height: AppSpacing.md),
            Text('Confirm your password',
                style: AppText.subtitle.copyWith(color: palette.textPrimary)),
            const SizedBox(height: AppSpacing.xs),
            AuthTextField(
              controller: _password,
              label: 'Password',
              icon: Icons.lock_outline_rounded,
              obscureText: true,
              onSubmitted: (_) => _delete(),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          SettingsPrimaryButton(
            label: 'Permanently Delete Account',
            icon: Icons.delete_forever_rounded,
            danger: true,
            busy: _busy,
            onPressed: _canSubmit ? _delete : null,
          ),
          const SizedBox(height: AppSpacing.sm),
          Center(
            child: TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
              child: Text('Keep my account',
                  style: TextStyle(
                      color: palette.textSecondary,
                      fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}
