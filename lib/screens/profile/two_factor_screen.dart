import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../l10n/app_localizations.dart';
import '../../services/security_alert_service.dart';
import '../../services/two_factor_service.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/auth/auth_text_field.dart';
import '../../widgets/profile/settings_scaffold.dart';
import '../../widgets/security/biometric_ux.dart';

enum _Stage { loading, disabled, enrolling, enabled }

/// Two-Factor Authentication - a full TOTP flow backed by Supabase MFA.
///
/// Disabled → Enable starts enrollment and shows the secret/URI to add to an
/// authenticator app → entering a valid 6-digit code verifies it and turns 2FA
/// on. Enabled shows recovery guidance and a Disable action.
class TwoFactorScreen extends StatefulWidget {
  const TwoFactorScreen({super.key});

  @override
  State<TwoFactorScreen> createState() => _TwoFactorScreenState();
}

class _TwoFactorScreenState extends State<TwoFactorScreen> {
  _Stage _stage = _Stage.loading;
  TotpSetup? _setup;
  final _code = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final enabled = await TwoFactorService.instance.isEnabled();
    if (!mounted) return;
    setState(() => _stage = enabled ? _Stage.enabled : _Stage.disabled);
  }

  Future<void> _startEnrollment() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      final setup = await TwoFactorService.instance.startEnrollment();
      if (!mounted) return;
      setState(() {
        _setup = setup;
        _stage = _Stage.enrolling;
      });
    } on AuthException catch (e) {
      if (mounted) BiometricUx.errorSnack(context, e.message);
    } catch (e) {
      developer.log('2FA enroll error: $e', name: '2fa', error: e);
      if (mounted) {
        BiometricUx.errorSnack(context, l10n.t('couldNotStart2fa'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    final l10n = AppLocalizations.of(context);
    final setup = _setup;
    if (setup == null) return;
    if (_code.text.trim().length < 6) {
      BiometricUx.errorSnack(context, l10n.t('enterSixDigitCode'));
      return;
    }
    setState(() => _busy = true);
    try {
      await TwoFactorService.instance
          .confirm(factorId: setup.factorId, code: _code.text);
      // Warn the user's other devices. Fire-and-forget: a failed alert must
      // never make a successful 2FA enrolment look like it failed.
      unawaited(SecurityAlertService.instance.twoFactorChanged(enabled: true));
      if (!mounted) return;
      _code.clear();
      BiometricUx.successSnack(context, l10n.t('twoFactorOn'));
      setState(() => _stage = _Stage.enabled);
    } on AuthException catch (e) {
      if (mounted) {
        BiometricUx.errorSnack(context, l10n.t('codeIncorrectExpired'));
      }
      developer.log('2FA verify auth error: ${e.message}', name: '2fa');
    } catch (e) {
      developer.log('2FA verify error: $e', name: '2fa', error: e);
      if (mounted) {
        BiometricUx.errorSnack(context, l10n.t('couldNotVerifyCode'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disable() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await _confirmDisable();
    if (!mounted || !confirmed) return;
    setState(() => _busy = true);
    try {
      await TwoFactorService.instance.disable();
      // Turning 2FA OFF is the higher-risk direction — it is exactly what an
      // account thief does first — so this alert matters more than the one above.
      unawaited(SecurityAlertService.instance.twoFactorChanged(enabled: false));
      if (!mounted) return;
      BiometricUx.successSnack(context, l10n.t('twoFactorDisabled'));
      setState(() => _stage = _Stage.disabled);
    } catch (e) {
      developer.log('2FA disable error: $e', name: '2fa', error: e);
      if (mounted) {
        BiometricUx.errorSnack(context, l10n.t('couldNotDisable2fa'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirmDisable() async {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: palette.surface,
        title: Text(l10n.t('disable2faTitle'),
            style: AppText.title.copyWith(color: palette.textPrimary)),
        content: Text(
          l10n.t('disable2faBody'),
          style: AppText.body.copyWith(color: palette.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.t('cancel'),
                style: TextStyle(color: palette.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.t('disable'),
                style: const TextStyle(
                    color: AppColors.critical, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      title: AppLocalizations.of(context).t('twoFactorAuthTitle'),
      child: switch (_stage) {
        _Stage.loading =>
          const Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
        _Stage.disabled => _buildDisabled(),
        _Stage.enrolling => _buildEnrolling(),
        _Stage.enabled => _buildEnabled(),
      },
    );
  }

  Widget _buildDisabled() {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.md,
          AppSpacing.screen, AppSpacing.xl),
      children: [
        _Hero(
          icon: Icons.verified_user_rounded,
          color: AppColors.lightBlue,
          title: l10n.t('extraLayerSecurity'),
          message: l10n.t('twoFactorIntro'),
        ),
        const SizedBox(height: AppSpacing.lg),
        _StepTile(n: '1', text: l10n.t('twoFactorStep1')),
        _StepTile(n: '2', text: l10n.t('twoFactorStep2')),
        _StepTile(n: '3', text: l10n.t('twoFactorStep3')),
        const SizedBox(height: AppSpacing.xl),
        SettingsPrimaryButton(
          label: l10n.t('enable2fa'),
          icon: Icons.lock_rounded,
          busy: _busy,
          onPressed: _busy ? null : _startEnrollment,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          l10n.t('canTurnOffAnyTime'),
          textAlign: TextAlign.center,
          style: AppText.caption.copyWith(color: palette.textFaint),
        ),
      ],
    );
  }

  Widget _buildEnrolling() {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final setup = _setup!;
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.md,
          AppSpacing.screen, AppSpacing.xl),
      children: [
        Text(l10n.t('addInoToAuthenticator'),
            style: AppText.headline.copyWith(color: palette.textPrimary)),
        const SizedBox(height: AppSpacing.xs),
        Text(
          l10n.t('enterSetupKeyHint'),
          style: AppText.body.copyWith(
            color: palette.textPrimary,
            height: 1.5,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _CopyField(label: l10n.t('setupKey'), value: setup.secret),
        const SizedBox(height: AppSpacing.sm),
        _CopyField(
            label: l10n.t('setupUriAdvanced'), value: setup.uri, mono: true),
        const SizedBox(height: AppSpacing.lg),
        AuthTextField(
          controller: _code,
          label: l10n.t('sixDigitCode'),
          icon: Icons.pin_rounded,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          onSubmitted: (_) => _verify(),
        ),
        const SizedBox(height: AppSpacing.xl),
        SettingsPrimaryButton(
          label: l10n.t('verifyAndTurnOn'),
          icon: Icons.check_rounded,
          busy: _busy,
          onPressed: _busy ? null : _verify,
        ),
      ],
    );
  }

  Widget _buildEnabled() {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.md,
          AppSpacing.screen, AppSpacing.xl),
      children: [
        _Hero(
          icon: Icons.gpp_good_rounded,
          color: AppColors.primaryGreen,
          title: l10n.t('twoFactorIsOn'),
          message: l10n.t('twoFactorOnBody'),
        ),
        const SizedBox(height: AppSpacing.lg),
        SettingsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                   Icon(Icons.info_outline_rounded,
                      color: AppColors.lightBlue, size: 20),
                  const SizedBox(width: 8),
                  Text(l10n.t('recovery'),
                      style:
                          AppText.subtitle.copyWith(color: palette.textPrimary)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                l10n.t('twoFactorRecoveryBody'),
                style: AppText.body
                    .copyWith(color: palette.textSecondary, height: 1.5),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        SettingsPrimaryButton(
          label: l10n.t('disable2fa'),
          icon: Icons.gpp_bad_rounded,
          danger: true,
          busy: _busy,
          onPressed: _busy ? null : _disable,
        ),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 34),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(title,
            textAlign: TextAlign.center,
            style: AppText.headline.copyWith(color: palette.textPrimary)),
        const SizedBox(height: AppSpacing.xs),
        Text(message,
            textAlign: TextAlign.center,
            style: AppText.body.copyWith(
              color: palette.textPrimary,
              height: 1.5,
              fontWeight: FontWeight.w500,
            )),
      ],
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({required this.n, required this.text});

  final String n;
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                // Pastel chip + coloured numeral (Divine Glass), instead of a
                // saturated gradient disc.
                color: AppColors.primaryGreen.withValues(alpha: 0.12),
                border: Border.all(
                  color: AppColors.primaryGreen.withValues(alpha: 0.22),
                ),
                shape: BoxShape.circle),
            child: Text(n,
                style:  TextStyle(
                    color: AppColors.primaryGreen,
                    fontWeight: FontWeight.w800,
                    fontSize: 13)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(text,
                  style: AppText.body.copyWith(
                      color: palette.textPrimary, height: 1.4)),
            ),
          ),
        ],
      ),
    );
  }
}

/// A read-only value with a copy button (setup key / URI).
class _CopyField extends StatelessWidget {
  const _CopyField({required this.label, required this.value, this.mono = false});

  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SettingsCard(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label.toUpperCase(),
                    style: AppText.label.copyWith(color: palette.textFaint)),
                const SizedBox(height: 4),
                SelectableText(
                  value,
                  maxLines: mono ? 2 : 1,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: mono ? 12 : 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: mono ? 0 : 1.5,
                    fontFamily: mono ? 'monospace' : null,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.copy_rounded, color: palette.textSecondary, size: 20),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: value));
              if (context.mounted) {
                BiometricUx.successSnack(
                    context,
                    AppLocalizations.of(context)
                        .t('copiedLabel')
                        .replaceFirst('{label}', label));
              }
            },
          ),
        ],
      ),
    );
  }
}
