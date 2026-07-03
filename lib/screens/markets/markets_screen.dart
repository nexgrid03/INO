import 'package:flutter/material.dart';

import '../../models/dashboard_models.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/dashboard/sparkline.dart';
import '../../widgets/profile/settings_scaffold.dart';

/// Markets — the full list behind the Home "Market Snapshot": gold, silver and
/// fuel rates with mini trends and change indicators. Rates are indicative
/// (realistic fallback) until a live pricing feed is connected.
class MarketsScreen extends StatelessWidget {
  const MarketsScreen({super.key, required this.quotes});

  final List<MarketQuote> quotes;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SettingsScaffold(
      title: 'Markets',
      child: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.screen, AppSpacing.md, AppSpacing.screen, AppSpacing.xl),
        children: [
          for (final q in quotes) ...[
            _MarketRow(quote: q),
            const SizedBox(height: AppSpacing.sm),
          ],
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Rates are indicative and refresh periodically. Connect a live '
            'pricing feed for real-time quotes.',
            style: AppText.caption.copyWith(color: palette.textFaint, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _MarketRow extends StatelessWidget {
  const _MarketRow({required this.quote});

  final MarketQuote quote;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final up = quote.changePercent >= 0;
    final changeColor = up ? AppColors.positive : AppColors.negative;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(AppRadius.button),
        border: Border.all(color: palette.border),
        boxShadow: palette.cardShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: quote.gradient),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(quote.icon, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(quote.label,
                  style: AppText.subtitle.copyWith(color: palette.textPrimary)),
              const SizedBox(height: 2),
              Text(quote.location ?? quote.unit,
                  style: AppText.caption.copyWith(color: palette.textSecondary)),
            ],
          ),
          const Spacer(),
          SizedBox(
            width: 56,
            height: 34,
            child: Sparkline(
              values: quote.spark,
              color: changeColor,
              strokeWidth: 2,
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(quote.price,
                  style: AppText.subtitle.copyWith(color: palette.textPrimary)),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                      up
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded,
                      size: 12,
                      color: changeColor),
                  Text('${quote.changePercent.abs().toStringAsFixed(2)}%',
                      style: AppText.label.copyWith(color: changeColor)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
