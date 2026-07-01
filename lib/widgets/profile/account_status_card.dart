import 'package:flutter/material.dart';

import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../dashboard/ino_card.dart';

/// A compact assurance card: the account is active and secure, when it last
/// backed up, and quick status pills for Cloud Synced · Secure Vault ·
/// Biometric. Green + light-blue accents; no analytics.
class AccountStatusCard extends StatelessWidget {
  const AccountStatusCard({
    super.key,
    required this.lastBackup,
    required this.cloudSynced,
    required this.vaultEnabled,
    required this.biometricEnabled,
  });

  final String lastBackup; // "Today, 9:24 AM"
  final bool cloudSynced;
  final bool vaultEnabled;
  final bool biometricEnabled;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return InoCard(
      radius: AppRadius.card,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: AppColors.brandGradient,
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryGreen.withValues(alpha: 0.28),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: const Icon(Icons.verified_user_rounded,
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Account Active',
                      style: AppText.subtitle.copyWith(
                        color: palette.textPrimary,
                        fontSize: 14.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Last backup · $lastBackup',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          AppText.caption.copyWith(color: palette.textSecondary),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.primaryGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: AppColors.primaryGreen,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text('Active',
                        style: AppText.label.copyWith(
                            color: AppColors.primaryGreen, fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              _StatusPill(
                icon: Icons.cloud_done_rounded,
                label: 'Cloud Synced',
                color: AppColors.lightBlue,
                on: cloudSynced,
              ),
              _StatusPill(
                icon: Icons.lock_rounded,
                label: 'Secure Vault',
                color: AppColors.primaryGreen,
                on: vaultEnabled,
              ),
              _StatusPill(
                icon: Icons.fingerprint_rounded,
                label: 'Biometric',
                color: AppColors.secondaryGreen,
                on: biometricEnabled,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.icon,
    required this.label,
    required this.color,
    required this.on,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool on;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final accent = on ? color : palette.textFaint;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: on
            ? color.withValues(alpha: 0.10)
            : palette.surfaceVariant,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(
          color: on ? color.withValues(alpha: 0.22) : palette.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(on ? Icons.check_circle_rounded : icon, size: 14, color: accent),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppText.label.copyWith(color: accent, fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}
