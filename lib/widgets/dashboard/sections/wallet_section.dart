import 'package:flutter/material.dart';

import '../../../core/responsive/responsive_h_list.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/dashboard_models.dart';
import '../../../theme/app_theme.dart';
import '../section_header.dart';
import '../../pressable_scale.dart';

/// Section 6 - Wallet Ecosystem Overview.
///
/// A horizontal row of wallet tiles (Identity, Documents, Insurance …) - the
/// Apple/Google Wallet metaphor. Each is a white glass card with a pastel
/// accent icon chip, item count, last activity and a tinted status chip so the
/// section reads as a deck of premium Divine Glass cards.
class WalletSection extends StatelessWidget {
  const WalletSection({super.key, required this.wallets});

  final List<WalletSummary> wallets;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: l10n.t('walletEcosystem'),
          subtitle: l10n.t('walletEcosystemSubtitle'),
          actionLabel: l10n.t('openWallet'),
          icon: Icons.account_balance_wallet_rounded,
        ),
        ResponsiveHList(
          baseHeight: 132,
          padding: const EdgeInsets.symmetric(horizontal: 2),
          itemCount: wallets.length,
          itemBuilder: (context, i) => _WalletCard(wallet: wallets[i]),
        ),
      ],
    );
  }
}

class _WalletCard extends StatelessWidget {
  const _WalletCard({required this.wallet});

  final WalletSummary wallet;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = AppPalette.of(context);
    final accent = wallet.gradient.first;
    return PressableScale(
      child: Container(
        width: 168,
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: palette.border),
          boxShadow: palette.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Pastel accent chip: tinted fill, coloured glyph, subtle edge.
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(
                      color: accent.withValues(alpha: 0.30),
                    ),
                  ),
                  child: Icon(wallet.icon, color: accent, size: 20),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    wallet.status,
                    style: TextStyle(
                      color: accent,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '${wallet.itemCount}',
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    l10n.t('itemsLabel'),
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            Text(
              wallet.name,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              wallet.lastActivity,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.textFaint,
                fontSize: 10.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
