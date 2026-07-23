import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';

/// Section 3 — the Wallet Summary stat-card row.
///
/// One glance, three facts, styled as a strip of tinted stat cards ("Total
/// Documents" treatment): each card carries a coloured accent edge on the
/// left, a small label + icon up top and one big figure below — documents,
/// expiring, and the vault-protection assurance. Deliberately *not* a storage
/// dashboard; analytics live in Wallet Settings. Reads from live counts so it
/// stays in sync as the user favorites / archives / deletes.
class WalletSummaryCard extends StatelessWidget {
  const WalletSummaryCard({
    super.key,
    required this.totalDocuments,
    required this.expiring,
    required this.protected,
  });

  final int totalDocuments;
  final int expiring;
  final bool protected;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final protectedColor = protected
        ? AppColors.primaryGreen
        : palette.textFaint;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _StatCard(
            accent: AppColors.primaryGreen,
            label: l10n.t('documents'),
            icon: Icons.folder_open_rounded,
            child: _BigValue(
              value: '$totalDocuments',
              color: palette.textPrimary,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            accent: AppColors.warning,
            label: l10n.t('expiring'),
            icon: Icons.warning_amber_rounded,
            child: _BigValue(
              value: '$expiring',
              color: expiring > 0 ? AppColors.warning : palette.textPrimary,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            accent: protectedColor,
            label: protected ? l10n.t('protected') : l10n.t('atRisk'),
            labelColor: protectedColor,
            icon: Icons.lock_rounded,
            child: Icon(
              protected ? Icons.verified_user_rounded : Icons.gpp_maybe_rounded,
              size: 26,
              color: protectedColor,
            ),
          ),
        ),
      ],
    );
  }
}

/// One tinted stat card: accent edge on the left, label + small icon on top,
/// a big figure (or assurance icon) below — the Stitch summary treatment.
class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.accent,
    required this.label,
    required this.icon,
    required this.child,
    this.labelColor,
  });

  final Color accent;
  final String label;
  final IconData icon;
  final Widget child;
  final Color? labelColor;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        gradient: palette.cardGradient,
        borderRadius: BorderRadius.circular(AppRadius.button),
        border: Border.all(color: palette.border),
        boxShadow: palette.cardShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.button),
        child: Stack(
          children: [
            // The coloured accent edge.
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Container(width: 4, color: accent),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        // Scale-down keeps the label on one line — never dots.
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            label,
                            maxLines: 1,
                            softWrap: false,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: labelColor ?? palette.textSecondary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(icon, size: 15, color: accent),
                    ],
                  ),
                  const SizedBox(height: 8),
                  child,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BigValue extends StatelessWidget {
  const _BigValue({required this.value, required this.color});

  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(
        value,
        style: TextStyle(
          fontSize: 25,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.8,
          height: 1.0,
          color: color,
        ),
      ),
    );
  }
}
