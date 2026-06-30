import 'package:flutter/material.dart';

import '../../models/dashboard_models.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../dashboard/ino_card.dart';

/// Section 4 — compact Market Snapshot.
///
/// A single low-profile card showing Gold and Silver side by side — circular
/// tinted icon, name, price with unit, and the daily change (green up / red
/// down). "View Markets" lives in the section header.
class MarketCard extends StatelessWidget {
  const MarketCard({super.key, required this.quotes, this.onTap});

  /// Expects the gold & silver quotes (first two are used).
  final List<MarketQuote> quotes;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final shown = quotes.take(2).toList();
    return InoCard(
      radius: AppRadius.card,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: 14),
      onTap: onTap,
      child: Row(
        children: [
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0)
              Container(
                width: 1,
                height: 40,
                margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                color: palette.border,
              ),
            Expanded(child: _MiniQuote(quote: shown[i])),
          ],
        ],
      ),
    );
  }
}

class _MiniQuote extends StatelessWidget {
  const _MiniQuote({required this.quote});

  final MarketQuote quote;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final up = quote.trend != TrendDirection.down;
    final changeColor = up ? AppColors.positive : AppColors.negative;
    return Row(
      children: [
        Container(
          width: AppSizes.iconContainerSm,
          height: AppSizes.iconContainerSm,
          decoration: BoxDecoration(
            color: quote.accent.withValues(alpha: 0.14),
            shape: BoxShape.circle,
          ),
          child: Icon(quote.icon, color: quote.accent, size: 22),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                quote.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.caption.copyWith(color: palette.textSecondary),
              ),
              const SizedBox(height: 1),
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
                          .copyWith(color: palette.textPrimary, fontSize: 15),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Text(
                    quote.unit,
                    style: AppText.caption
                        .copyWith(color: palette.textFaint, fontSize: 11),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Icon(
                      up
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded,
                      size: 12,
                      color: changeColor),
                  const SizedBox(width: 2),
                  Text(
                    '${quote.changePercent.abs().toStringAsFixed(2)}%',
                    style:
                        AppText.label.copyWith(color: changeColor, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
