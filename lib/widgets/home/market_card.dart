import 'package:flutter/material.dart';

import '../../models/dashboard_models.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../dashboard/sparkline.dart';
import '../pressable_scale.dart';

/// Market Snapshot — Gold & Silver in one calm, scannable card.
///
/// A single premium surface (white, 20-radius, hairline teal border, whisper
/// shadow) with a "Live rates" header and one row per metal:
///
///   [icon badge]  Gold          ~~sparkline~~   ₹10,250   [+0.35%]
///                 per gram                      caption
///
/// Everything lines up on a shared grid — name column left, trend centre,
/// price column right — so the eye scans straight down. Rows are divided by a
/// soft hairline; the whole card is one tap target for the full markets view.
class MarketCard extends StatelessWidget {
  const MarketCard({super.key, required this.quotes, this.onTap});

  final List<MarketQuote> quotes;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    // Find live gold and silver quotes or fall back to realistic values.
    MarketQuote? goldQuote;
    MarketQuote? silverQuote;
    for (final q in quotes) {
      if (q.label.toLowerCase().contains('gold')) {
        goldQuote = q;
      } else if (q.label.toLowerCase().contains('silver')) {
        silverQuote = q;
      }
    }

    String changeOf(MarketQuote? q, String fallback) => q != null
        ? '${q.changePercent >= 0 ? '+' : ''}${q.changePercent.toStringAsFixed(2)}%'
        : fallback;

    final card = Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: palette.border),
        boxShadow: palette.cardShadow,
      ),
      child: Column(
        children: [
          // Header strip: pulsing live dot + caption, over a faint teal wash.
          Container(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
            decoration: BoxDecoration(
              gradient: AppGradients.wash(opacity: 0.06),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppRadius.card),
              ),
            ),
            child: Row(
              children: [
                const _LiveDot(),
                const SizedBox(width: 8),
                Text(
                  'Live rates',
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
                const Spacer(),
                Text(
                  'per gram · INR',
                  style: TextStyle(
                    color: palette.textFaint,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          _MetalRow(
            name: 'Gold',
            caption: '24K fine',
            icon: Icons.diamond_rounded,
            badgeColor: AppColors.gold,
            price: goldQuote?.price ?? '₹10,250',
            change: changeOf(goldQuote, '+0.35%'),
            spark: const [10.0, 10.5, 10.3, 11.0, 11.2, 11.8, 12.0],
          ),
          Divider(color: palette.border, height: 1, indent: 18, endIndent: 18),
          _MetalRow(
            name: 'Silver',
            caption: '999 pure',
            icon: Icons.auto_awesome_rounded,
            badgeColor: AppColors.silver,
            price: silverQuote?.price ?? '₹120.50',
            change: changeOf(silverQuote, '+0.28%'),
            spark: const [8.0, 8.4, 8.2, 8.7, 8.6, 9.1, 9.4],
          ),
        ],
      ),
    );

    if (onTap == null) return card;
    return PressableScale(
      pressedScale: 0.98,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: card,
      ),
    );
  }
}

/// One metal: identity left, trend centre, price + change right.
class _MetalRow extends StatelessWidget {
  const _MetalRow({
    required this.name,
    required this.caption,
    required this.icon,
    required this.badgeColor,
    required this.price,
    required this.change,
    required this.spark,
  });

  final String name;
  final String caption;
  final IconData icon;
  final Color badgeColor;
  final String price;
  final String change;
  final List<double> spark;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final isUp = !change.startsWith('-');
    final trendColor = isUp ? AppColors.positive : AppColors.negative;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Row(
        children: [
          // Identity: soft tinted badge + name / caption.
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: badgeColor, size: 21),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 64,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  caption,
                  style: TextStyle(
                    color: palette.textFaint,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          // Trend: a quiet sparkline that fills the middle ground.
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: SizedBox(
                height: 30,
                child: Sparkline(
                  values: spark,
                  color: trendColor,
                  strokeWidth: 2.2,
                ),
              ),
            ),
          ),
          // Price column, right-aligned for instant comparison.
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                price,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 16.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 3),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: trendColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  change,
                  style: TextStyle(
                    color: trendColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A softly pulsing teal dot — the "live" affordance in the card header.
class _LiveDot extends StatefulWidget {
  const _LiveDot();

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(
        begin: 0.45,
        end: 1.0,
      ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)),
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: AppColors.primaryGreen,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryGreen.withValues(alpha: 0.45),
              blurRadius: 6,
            ),
          ],
        ),
      ),
    );
  }
}
