import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/dashboard_models.dart';
import '../../../theme/app_theme.dart';
import '../ino_card.dart';
import '../section_header.dart';
import '../sparkline.dart';

/// Section 2 — Live Market Intelligence.
///
/// A horizontal carousel of premium financial cards (gold, silver, petrol,
/// diesel) each showing price, daily change with a coloured trend pill, and a
/// mini sparkline. Placed high on the screen to drive daily engagement.
class MarketSection extends StatelessWidget {
  const MarketSection({super.key, required this.quotes});

  final List<MarketQuote> quotes;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: l10n.t('liveMarket'),
          subtitle: l10n.t('liveMarketSubtitle'),
          actionLabel: l10n.t('markets'),
          icon: Icons.show_chart_rounded,
        ),
        SizedBox(
          height: 148,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 2),
            physics: const BouncingScrollPhysics(),
            itemCount: quotes.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) => _MarketCard(quote: quotes[i]),
          ),
        ),
      ],
    );
  }
}

class _MarketCard extends StatelessWidget {
  const _MarketCard({required this.quote});

  final MarketQuote quote;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final up = quote.trend == TrendDirection.up;
    final flat = quote.trend == TrendDirection.flat;
    final trendColor = flat
        ? palette.textSecondary
        : up
            ? AppColors.positive
            : AppColors.negative;

    final filled = quote.filled;
    // Colour roles flip when the card is a filled gradient hero (Gold).
    final titleColor =
        filled ? Colors.white.withValues(alpha: 0.92) : palette.textSecondary;
    final priceColor = filled ? Colors.white : palette.textPrimary;
    final unitColor =
        filled ? Colors.white.withValues(alpha: 0.8) : palette.textFaint;
    final sparkColor = filled ? Colors.white : trendColor;

    return SizedBox(
      width: 176,
      child: InoCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        onTap: () {},
        gradient: filled
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: quote.gradient,
              )
            : null,
        borderColor: filled ? Colors.transparent : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Icon chip — translucent white on the filled hero, gradient
                // tile on the white cards. White glyph either way.
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: filled ? Colors.white.withValues(alpha: 0.22) : null,
                    gradient: filled
                        ? null
                        : LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: quote.gradient,
                          ),
                    borderRadius: BorderRadius.circular(11),
                    boxShadow: filled
                        ? null
                        : [
                            BoxShadow(
                              color: quote.gradient.first
                                  .withValues(alpha: 0.35),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                  ),
                  child: Icon(quote.icon, size: 19, color: Colors.white),
                ),
                const Spacer(),
                _TrendPill(
                  color: trendColor,
                  up: up,
                  flat: flat,
                  onGradient: filled,
                  text:
                      '${quote.changePercent >= 0 ? '+' : ''}${quote.changePercent.toStringAsFixed(2)}%',
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              quote.label,
              style: TextStyle(
                fontSize: 12.5,
                color: titleColor,
                fontWeight: FontWeight.w600,
              ),
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
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: priceColor,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                const SizedBox(width: 3),
                Text(
                  quote.unit,
                  style: TextStyle(fontSize: 11, color: unitColor),
                ),
              ],
            ),
            const Spacer(),
            Row(
              children: [
                if (quote.location != null) ...[
                  Icon(Icons.place_rounded, size: 12, color: unitColor),
                  const SizedBox(width: 2),
                  Text(
                    quote.location!,
                    style: TextStyle(fontSize: 11, color: unitColor),
                  ),
                ],
                const Spacer(),
                SizedBox(
                  width: 70,
                  height: 28,
                  child: Sparkline(
                    values: quote.spark,
                    color: sparkColor,
                    strokeWidth: 2.6,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TrendPill extends StatelessWidget {
  const _TrendPill({
    required this.color,
    required this.up,
    required this.flat,
    required this.text,
    this.onGradient = false,
  });

  final Color color;
  final bool up;
  final bool flat;
  final String text;

  /// When the pill sits on a filled gradient card, render it as translucent
  /// white for legibility instead of the semantic up/down colour.
  final bool onGradient;

  @override
  Widget build(BuildContext context) {
    final fg = onGradient ? Colors.white : color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: onGradient
            ? Colors.white.withValues(alpha: 0.22)
            : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            flat
                ? Icons.remove_rounded
                : up
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
            size: 11,
            color: fg,
          ),
          const SizedBox(width: 2),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}
