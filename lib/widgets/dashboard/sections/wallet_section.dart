import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/dashboard_models.dart';
import '../section_header.dart';
import '../../pressable_scale.dart';

/// Section 6 — Wallet Ecosystem Overview.
///
/// A horizontal row of gradient wallet tiles (Identity, Documents, Insurance …)
/// — the Apple/Google Wallet metaphor. Each shows item count, last activity and
/// a status chip on a brand-tinted gradient so the section feels like a deck of
/// premium cards.
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
        SizedBox(
          height: 132,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 2),
            physics: const BouncingScrollPhysics(),
            itemCount: wallets.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) => _WalletCard(wallet: wallets[i]),
          ),
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
    return PressableScale(
      child: Container(
        width: 168,
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: wallet.gradient,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: wallet.gradient.first.withValues(alpha: 0.32),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(wallet.icon, color: Colors.white, size: 20),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    wallet.status,
                    style: const TextStyle(
                      color: Colors.white,
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
                  style: const TextStyle(
                    color: Colors.white,
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
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            Text(
              wallet.name,
              style: const TextStyle(
                color: Colors.white,
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
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 10.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
