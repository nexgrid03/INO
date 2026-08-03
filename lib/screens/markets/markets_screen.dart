import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/dashboard_models.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_style.dart';
import '../../widgets/common/liquid_glass.dart';
import '../../widgets/dashboard/sparkline.dart';
import '../../widgets/markets/live_metal_rates_card.dart';
import '../../widgets/profile/settings_scaffold.dart';

/// Markets - the full list behind the Home "Market Snapshot": gold, silver and
/// fuel rates with mini trends and change indicators. Rates are indicative
/// (realistic fallback) until a live pricing feed is connected.
class MarketsScreen extends StatelessWidget {
  const MarketsScreen({super.key, required this.quotes});

  final List<MarketQuote> quotes;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return SettingsScaffold(
      title: l10n.t('markets'),
      child: ListView(
        physics: InoStyle.usesDivineGlass(context)
            ? const ClampingScrollPhysics()
            : const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.screen, AppSpacing.md, AppSpacing.screen, AppSpacing.xl),
        children: [
          const LiveMetalRatesCard(),
          const SizedBox(height: AppSpacing.md),
          for (final q in quotes) ...[
            _MarketRow(quote: q),
            const SizedBox(height: AppSpacing.sm),
          ],
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.t('marketsInfoLine'),
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
    final accent = quote.gradient.first;
    final launcher = InoStyle.usesDivineGlass(context);
    final chip = launcher ? 48.0 : 42.0;

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: chip,
              height: chip,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(launcher ? 14 : 13),
              ),
              child: Icon(quote.icon, color: accent, size: launcher ? 24 : 21),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(quote.label,
                      style: AppText.subtitle
                          .copyWith(color: palette.textPrimary)),
                  const SizedBox(height: 2),
                  Text(quote.location ?? quote.unit,
                      style: AppText.caption
                          .copyWith(color: palette.textSecondary)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: changeColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                      up
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded,
                      size: 12,
                      color: changeColor),
                  const SizedBox(width: 2),
                  Text('${quote.changePercent.abs().toStringAsFixed(2)}%',
                      style: AppText.label.copyWith(color: changeColor)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  quote.price,
                  style: AppText.headline.copyWith(
                    color: palette.textPrimary,
                    fontSize: 22,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 76,
              height: 36,
              child: Sparkline(
                values: quote.spark,
                color: changeColor,
                strokeWidth: 2,
              ),
            ),
          ],
        ),
      ],
    );

    if (launcher) {
      return LiquidGlass(
        borderRadius: BorderRadius.circular(AppRadius.card),
        blur: 18,
        padding: const EdgeInsets.all(16),
        child: body,
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: palette.cardGradient,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: palette.border),
        boxShadow: palette.cardShadow,
      ),
      child: body,
    );
  }
}
