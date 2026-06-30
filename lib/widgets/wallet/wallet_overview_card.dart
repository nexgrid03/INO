import 'package:flutter/material.dart';

import '../../models/wallet_models.dart';
import '../../theme/app_theme.dart';
import '../pressable_scale.dart';

/// Section 2 — Wallet Overview hero card.
///
/// A premium green→light-blue gradient card with a glassmorphism feel: faint
/// blurred light orbs behind translucent stat blocks. Surfaces the at-a-glance
/// vault summary — wallets, records, protected items, last backup and storage.
class WalletOverviewCard extends StatelessWidget {
  const WalletOverviewCard({super.key, required this.overview});

  final WalletOverview overview;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      pressedScale: 0.985,
      child: Container(
        decoration: BoxDecoration(
          gradient: AppColors.brandGradient,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryGreen.withValues(alpha: 0.32),
              blurRadius: 28,
              offset: const Offset(0, 14),
            ),
            BoxShadow(
              color: AppColors.lightBlue.withValues(alpha: 0.22),
              blurRadius: 24,
              spreadRadius: -4,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            children: [
              // Glass light orbs for depth.
              Positioned(
                right: -30,
                top: -40,
                child: _orb(120, 0.16),
              ),
              Positioned(
                left: -24,
                bottom: -50,
                child: _orb(140, 0.10),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.account_balance_wallet_rounded,
                              color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Vault Overview',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.lock_rounded,
                                  size: 12, color: Colors.white),
                              SizedBox(width: 4),
                              Text(
                                'Encrypted',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        _Stat(
                          value: '${overview.totalWallets}',
                          label: 'Wallets',
                        ),
                        _vDivider(),
                        _Stat(
                          value: '${overview.totalRecords}',
                          label: 'Records',
                        ),
                        _vDivider(),
                        _Stat(
                          value: '${overview.protectedItems}',
                          label: 'Protected',
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Container(
                      height: 1,
                      color: Colors.white.withValues(alpha: 0.18),
                    ),
                    const SizedBox(height: 14),
                    _InfoRow(
                      icon: Icons.cloud_done_rounded,
                      label: 'Last backup',
                      value: overview.lastBackup,
                    ),
                    const SizedBox(height: 12),
                    // Storage used with a thin glass progress bar.
                    Row(
                      children: [
                        const Icon(Icons.sd_storage_rounded,
                            size: 15, color: Colors.white),
                        const SizedBox(width: 8),
                        const Text(
                          'Storage used',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          overview.storageUsedLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: overview.storageFraction.clamp(0.0, 1.0),
                        minHeight: 7,
                        backgroundColor: Colors.white.withValues(alpha: 0.22),
                        valueColor:
                            const AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _orb(double size, double alpha) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: alpha),
        ),
      );

  static Widget _vDivider() => Container(
        width: 1,
        height: 38,
        color: Colors.white.withValues(alpha: 0.18),
      );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          FittedBox(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: Colors.white),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
