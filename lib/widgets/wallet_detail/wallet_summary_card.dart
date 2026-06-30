import 'package:flutter/material.dart';

import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../dashboard/ino_card.dart';
import '../pressable_scale.dart';

/// Section 3 — the compact Wallet Summary Card (≈150dp).
///
/// One glance, four facts: how many documents, how many are expiring, that the
/// vault is protected, and when it last changed — plus a single "View Vault"
/// affordance. Deliberately *not* a storage dashboard; analytics live in
/// Wallet Settings. Reads from live counts so it stays in sync as the user
/// favorites / archives / deletes.
class WalletSummaryCard extends StatelessWidget {
  const WalletSummaryCard({
    super.key,
    required this.totalDocuments,
    required this.expiring,
    required this.protected,
    required this.lastUpdatedLabel,
    required this.gradient,
    required this.onViewVault,
  });

  final int totalDocuments;
  final int expiring;
  final bool protected;
  final String lastUpdatedLabel;
  final List<Color> gradient;
  final VoidCallback onViewVault;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return InoCard(
      radius: AppRadius.large,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _Stat(
                  value: '$totalDocuments',
                  label: 'Documents',
                  color: palette.textPrimary,
                ),
              ),
              _Divider(palette: palette),
              Expanded(
                child: _Stat(
                  value: '$expiring',
                  label: 'Expiring',
                  color: expiring > 0
                      ? AppColors.warning
                      : palette.textPrimary,
                ),
              ),
              _Divider(palette: palette),
              Expanded(
                child: _ProtectedStat(protected: protected),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(height: 1, thickness: 1, color: palette.border),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.schedule_rounded, size: 15, color: palette.textFaint),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  lastUpdatedLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: palette.textSecondary,
                  ),
                ),
              ),
              _ViewVaultButton(gradient: gradient, onTap: onViewVault),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, required this.color});

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: palette.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// The "✓ Protected" assurance, standing in for the removed security dashboard.
class _ProtectedStat extends StatelessWidget {
  const _ProtectedStat({required this.protected});

  final bool protected;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final color =
        protected ? AppColors.primaryGreen : palette.textFaint;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          protected
              ? Icons.verified_user_rounded
              : Icons.gpp_maybe_rounded,
          size: 24,
          color: color,
        ),
        const SizedBox(height: 4),
        Text(
          protected ? 'Protected' : 'At risk',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 34,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: palette.border,
    );
  }
}

class _ViewVaultButton extends StatelessWidget {
  const _ViewVaultButton({required this.gradient, required this.onTap});

  final List<Color> gradient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      pressedScale: 0.94,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.button),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: gradient,
              ),
              borderRadius: BorderRadius.circular(AppRadius.button),
              boxShadow: [
                BoxShadow(
                  color: gradient.first.withValues(alpha: 0.30),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'View Vault',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(width: 3),
                  Icon(Icons.chevron_right_rounded,
                      color: Colors.white, size: 18),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
