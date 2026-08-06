import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/profile/settings_scaffold.dart';
import '../../widgets/security/biometric_ux.dart';

/// Contact Support - comoposes an email to the support address via the device's
/// mail app.
class ContactSupportScreen extends StatefulWidget {
  const ContactSupportScreen({super.key, this.supportEmail});

  final String? supportEmail;

  @override
  State<ContactSupportScreen> createState() => _ContactSupportScreenState();
}

class _ContactSupportScreenState extends State<ContactSupportScreen> {
  static const _fallbackEmail = 'inosupport.app@gmail.com';

  bool _busy = false;

  String get _email => widget.supportEmail ?? _fallbackEmail;

  Future<void> _send() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      final uri = Uri(
        scheme: 'mailto',
        path: _email,
      );
      developer.log('contact: launching $uri', name: 'support');
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!mounted) return;
      if (ok) {
        BiometricUx.successSnack(context, l10n.t('openingMailApp'));
        Navigator.of(context).pop();
      } else {
        BiometricUx.errorSnack(
            context, l10n.t('noMailApp').replaceFirst('{email}', _email));
      }
    } catch (e) {
      developer.log('contact send error: $e', name: 'support', error: e);
      if (mounted) {
        BiometricUx.errorSnack(context, l10n.t('couldNotOpenMailApp'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return SettingsScaffold(
      title: l10n.t('contactSupport'),
      child: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.md,
            AppSpacing.screen, AppSpacing.xl),
        children: [
          SettingsCard(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.t('contactSupportIntro'),
                  style: AppText.body.copyWith(
                    color: palette.textPrimary,
                    height: 1.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: _busy ? null : _send,
                    child: Ink(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: palette.surfaceVariant
                            .withValues(alpha: palette.isDark ? 1 : 0.55),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: palette.border),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.alternate_email_rounded,
                              color: palette.textSecondary, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _email,
                              style: AppText.body.copyWith(
                                color: palette.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Icon(Icons.open_in_new_rounded,
                              color: palette.textSecondary, size: 18),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          SettingsPrimaryButton(
            label: l10n.t('contactSupport'),
            icon: Icons.mail_rounded,
            busy: _busy,
            onPressed: _busy ? null : _send,
          ),
        ],
      ),
    );
  }
}
