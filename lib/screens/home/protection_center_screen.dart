import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/app_settings.dart';
import '../../services/biometric_service.dart';
import '../../services/document_protection_store.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/profile/settings_scaffold.dart';
import '../shell/shell_controller.dart';

/// Protection Center — the security & coverage overview behind the "Protected"
/// summary card and the "Protect" quick action: a live security score, the
/// device protections in place, protected-document count and insurance coverage.
class ProtectionCenterScreen extends StatelessWidget {
  const ProtectionCenterScreen({super.key});

  void _openSecurity(BuildContext context) {
    Navigator.of(context).popUntil((r) => r.isFirst);
    ShellController.tab.value = 4; // Profile (Security section)
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return SettingsScaffold(
      title: l10n.t('protectionCenter'),
      child: ListenableBuilder(
        listenable: Listenable.merge([
          BiometricService.instance.lockEnabled,
          AppSettings.instance.twoFactor,
          DocumentProtectionStore.instance,
        ]),
        builder: (context, _) {
          final biometric = BiometricService.instance.lockEnabled.value;
          final twoFactor = AppSettings.instance.twoFactor.value;
          final protectedDocs = DocumentProtectionStore.instance.protectedCount;

          // A simple, honest security score out of 100.
          var score = 40; // baseline: signed-in + private storage
          if (biometric) score += 30;
          if (twoFactor) score += 20;
          if (protectedDocs > 0) score += 10;

          return ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.md,
                AppSpacing.screen, AppSpacing.xl),
            children: [
              _ScoreCard(score: score),
              const SizedBox(height: AppSpacing.lg),
              Text(l10n.t('security').toUpperCase(),
                  style: AppText.label.copyWith(color: palette.textFaint)),
              const SizedBox(height: AppSpacing.sm),
              _StatusTile(
                icon: Icons.fingerprint_rounded,
                title: l10n.t('biometricLock'),
                on: biometric,
                onText: l10n.t('protectingVault'),
                offText: l10n.t('turnOnToLock'),
                onManage: () => _openSecurity(context),
              ),
              const SizedBox(height: AppSpacing.xs),
              _StatusTile(
                icon: Icons.verified_user_rounded,
                title: l10n.t('twoFactor'),
                on: twoFactor,
                onText: l10n.t('twoFactorOnText'),
                offText: l10n.t('twoFactorOffText'),
                onManage: () => _openSecurity(context),
              ),
              const SizedBox(height: AppSpacing.xs),
              _StatusTile(
                icon: Icons.lock_rounded,
                title: l10n.t('protectedDocuments'),
                on: protectedDocs > 0,
                onText: l10n
                    .t('protectedDocsRequireUnlock')
                    .replaceFirst('{n}', '$protectedDocs'),
                offText: l10n.t('noProtectedDocs'),
                onManage: () {
                  Navigator.of(context).popUntil((r) => r.isFirst);
                  ShellController.tab.value = 1; // Wallet, to protect documents
                },
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(l10n.t('coverage').toUpperCase(),
                  style: AppText.label.copyWith(color: palette.textFaint)),
              const SizedBox(height: AppSpacing.sm),
              _CoverageCard(),
            ],
          );
        },
      ),
    );
  }
}

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({required this.score});
  final int score;

  Color get _color => score >= 80
      ? AppColors.primaryGreen
      : score >= 55
          ? AppColors.warning
          : AppColors.critical;

  String _label(AppLocalizations l10n) => score >= 80
      ? l10n.t('scoreStrong')
      : score >= 55
          ? l10n.t('scoreGood')
          : l10n.t('scoreNeedsAttention');

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return SettingsCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: [
          SizedBox(
            width: 74,
            height: 74,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 74,
                  height: 74,
                  child: CircularProgressIndicator(
                    value: score / 100,
                    strokeWidth: 7,
                    backgroundColor: palette.surfaceVariant,
                    valueColor: AlwaysStoppedAnimation(_color),
                  ),
                ),
                Text('$score',
                    style: AppText.title.copyWith(color: palette.textPrimary)),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.t('securityScore'),
                    style: AppText.caption
                        .copyWith(color: palette.textSecondary)),
                const SizedBox(height: 2),
                Text(_label(l10n),
                    style: AppText.headline
                        .copyWith(color: _color, fontSize: 22)),
                const SizedBox(height: 4),
                Text(l10n.t('securityScoreSubtitle'),
                    style:
                        AppText.caption.copyWith(color: palette.textFaint)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusTile extends StatelessWidget {
  const _StatusTile({
    required this.icon,
    required this.title,
    required this.on,
    required this.onText,
    required this.offText,
    required this.onManage,
  });

  final IconData icon;
  final String title;
  final bool on;
  final String onText;
  final String offText;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final color = on ? AppColors.primaryGreen : AppColors.warning;
    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(AppRadius.button),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onManage,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.button),
            border: Border.all(color: palette.border),
          ),
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: AppText.subtitle
                            .copyWith(color: palette.textPrimary)),
                    const SizedBox(height: 2),
                    Text(on ? onText : offText,
                        style: AppText.caption
                            .copyWith(color: palette.textSecondary)),
                  ],
                ),
              ),
              Icon(on ? Icons.check_circle_rounded : Icons.chevron_right_rounded,
                  color: on ? AppColors.primaryGreen : palette.textFaint,
                  size: on ? 22 : 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoverageCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    // Realistic fallback coverage summary until policies are added.
    return SettingsCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: AppColors.brandGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child:
                    const Icon(Icons.shield_rounded, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.t('insuranceCoverage'),
                        style: AppText.subtitle
                            .copyWith(color: palette.textPrimary)),
                    const SizedBox(height: 2),
                    Text(l10n.t('coverageFallback'),
                        style: AppText.caption
                            .copyWith(color: palette.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
