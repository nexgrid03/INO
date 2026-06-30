import 'package:flutter/material.dart';

import '../../models/wallet_models.dart';
import '../../theme/app_theme.dart';
import '../dashboard/fade_slide_in.dart';
import '../dashboard/ino_card.dart';

/// The Wallet Hub launcher grid.
///
/// A compact 2-column grid of all wallet vaults — each card shows only the
/// gradient icon, the wallet name and its item count, so all 8 wallets fit on
/// one screen without scrolling. Cards stagger in and squish on press.
class WalletGrid extends StatelessWidget {
  const WalletGrid({super.key, required this.categories, this.onOpen});

  final List<WalletCategory> categories;
  final void Function(WalletCategory category)? onOpen;

  static const double _cardHeight = 126;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final cols = w >= 640 ? 3 : 2;
        const gap = 12.0;
        final cardW = (w - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var i = 0; i < categories.length; i++)
              SizedBox(
                width: cardW,
                height: _cardHeight,
                child: FadeSlideIn(
                  delay: Duration(milliseconds: (i * 45).clamp(0, 360)),
                  offset: 14,
                  child: _WalletCard(
                    category: categories[i],
                    onTap: () => onOpen?.call(categories[i]),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _WalletCard extends StatelessWidget {
  const _WalletCard({required this.category, required this.onTap});

  final WalletCategory category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return InoCard(
      radius: 20,
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: category.gradient,
              ),
              borderRadius: BorderRadius.circular(13),
              boxShadow: [
                BoxShadow(
                  color: category.gradient.first.withValues(alpha: 0.32),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(category.icon, color: Colors.white, size: 22),
          ),
          const Spacer(),
          Text(
            category.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: palette.textPrimary,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${category.metric} ${category.metricLabel}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              color: palette.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
