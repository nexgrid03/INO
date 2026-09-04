import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/auth_service.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/pressable_scale.dart';
import '../legal/legal_document_screen.dart';

/// Screen displayed when a user signs in via Google for the first time
/// and must explicitly consent to the Terms of Service & Privacy Policy
/// before account setup completes.
class GoogleTermsConsentScreen extends StatefulWidget {
  const GoogleTermsConsentScreen({super.key, required this.onConsentGiven});

  final VoidCallback onConsentGiven;

  @override
  State<GoogleTermsConsentScreen> createState() =>
      _GoogleTermsConsentScreenState();
}

class _GoogleTermsConsentScreenState
    extends State<GoogleTermsConsentScreen> {
  bool _accepted = false;
  bool _saving = false;

  Future<void> _submit() async {
    if (!_accepted || _saving) return;
    setState(() => _saving = true);
    try {
      await AuthService.instance.recordTermsConsent(version: '1.0');
      if (!mounted) return;
      widget.onConsentGiven();
    } catch (e) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.t('acceptTermsRequired'),
          ),
          backgroundColor: AppColors.critical,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: palette.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
          child: Column(
            children: [
              const SizedBox(height: AppSpacing.xl),
              // App Branding Icon
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  gradient: AppGradients.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.shield_outlined,
                  color: Colors.white,
                  size: 36,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Terms & Privacy Consent',
                style: AppText.headline.copyWith(color: palette.textPrimary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Before continuing with Google Sign-In, please review and accept our Terms of Service and Privacy Policy.',
                style: AppText.body.copyWith(color: palette.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xl),

              // Legal document cards
              Card(
                color: palette.surfaceVariant,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(
                        Icons.description_outlined,
                        color: AppColors.primaryGreen,
                      ),
                      title: Text(
                        l10n.t('termsConditions'),
                        style: AppText.title.copyWith(color: palette.textPrimary),
                      ),
                      subtitle: Text(
                        'Read terms & user agreement',
                        style: AppText.caption.copyWith(color: palette.textSecondary),
                      ),
                      trailing: Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 16,
                        color: palette.textSecondary,
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => LegalDocumentScreen.terms(),
                        ),
                      ),
                    ),
                    Divider(height: 1, color: palette.border),
                    ListTile(
                      leading: Icon(
                        Icons.privacy_tip_outlined,
                        color: AppColors.primaryGreen,
                      ),
                      title: Text(
                        l10n.t('privacyPolicy'),
                        style: AppText.title.copyWith(color: palette.textPrimary),
                      ),
                      subtitle: Text(
                        'Read privacy policy & data practices',
                        style: AppText.caption.copyWith(color: palette.textSecondary),
                      ),
                      trailing: Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 16,
                        color: palette.textSecondary,
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => LegalDocumentScreen.privacy(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // Agreement Checkbox
              InkWell(
                onTap: () => setState(() => _accepted = !_accepted),
                borderRadius: BorderRadius.circular(AppRadius.chip),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.xs,
                    horizontal: AppSpacing.xs,
                  ),
                  child: Row(
                    children: [
                      Checkbox(
                        value: _accepted,
                        onChanged: (val) =>
                            setState(() => _accepted = val ?? false),
                        activeColor: AppColors.primaryGreen,
                      ),
                      Expanded(
                        child: Text(
                          l10n.t('agreeToTerms'),
                          style: AppText.body
                              .copyWith(color: palette.textPrimary),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: AppSpacing.md),

              // Accept Button
              SizedBox(
                width: double.infinity,
                height: AppSizes.button,
                child: GestureDetector(
                  onTap: _accepted && !_saving ? _submit : null,
                  child: PressableScale(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: _accepted && !_saving
                            ? AppGradients.primary
                            : null,
                        color: !_accepted || _saving ? palette.surfaceVariant : null,
                        borderRadius: BorderRadius.circular(AppRadius.button),
                      ),
                      alignment: Alignment.center,
                      child: _saving
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            )
                          : Text(
                              'Accept & Continue',
                              style: AppText.title.copyWith(
                                color: _accepted ? Colors.white : palette.textSecondary,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }
}

