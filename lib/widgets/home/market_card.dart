import 'package:flutter/material.dart';

import '../../models/dashboard_models.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../dashboard/ino_card.dart';

/// Section 4 — Market Snapshot.
///
/// A horizontally-scrolling row of live rates (Gold, Silver, Petrol, Diesel …),
/// each in its own compact card wide enough to show the full price. Swipe right
/// to reveal more. "View Markets" lives in the section header.
class MarketCard extends StatelessWidget {
  const MarketCard({super.key, required this.quotes, this.onTap});

  final List<MarketQuote> quotes;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 122,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        physics: const BouncingScrollPhysics(),
        itemCount: quotes.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, i) => _QuoteCard(quote: quotes[i], onTap: onTap),
      ),
    );
  }
}

class _QuoteCard extends StatelessWidget {
  const _QuoteCard({required this.quote, this.onTap});

  final MarketQuote quote;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final up = quote.changePercent >= 0;
    final changeColor = up ? AppColors.positive : AppColors.negative;

    return InoCard(
      radius: AppRadius.card,
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: SizedBox(
        width: 150,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: quote.accent.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(quote.icon, color: quote.accent, size: 19),
                ),
                const Spacer(),
                Icon(
                    up
                        ? Icons.arrow_upward_rounded
                        : Icons.arrow_downward_rounded,
                    size: 13,
                    color: changeColor),
                const SizedBox(width: 1),
                Text(
                  '${quote.changePercent.abs().toStringAsFixed(2)}%',
                  style:
                      AppText.label.copyWith(color: changeColor, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              quote.location == null
                  ? quote.label
                  : '${quote.label} · ${quote.location}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.caption.copyWith(color: palette.textSecondary),
            ),
            const SizedBox(height: 2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: Text(
                    quote.price,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.subtitle
                        .copyWith(color: palette.textPrimary, fontSize: 16),
                  ),
                ),
                const SizedBox(width: 3),
                Text(
                  quote.unit,
                  style: AppText.caption
                      .copyWith(color: palette.textFaint, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
