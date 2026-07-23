import 'package:flutter/material.dart';

import '../../models/dashboard_models.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../dashboard/sparkline.dart';
import '../pressable_scale.dart';

/// Section 6 — Live Market Prices (Gold & Silver ONLY).
///
/// Features two premium theme-colored cards side-by-side:
/// 1. Gold Card: Background #EAFBF7, Accent #0CB7A3, Gold Icon #E0A100, Teal Sparkline.
/// 2. Silver Card: Background #EDF8FF, Accent #3EC7FF, Silver Icon #8C9BA5, Cyan Sparkline.
class MarketCard extends StatelessWidget {
  const MarketCard({super.key, required this.quotes, this.onTap});

  final List<MarketQuote> quotes;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // Find live gold and silver quotes or fallback to exact design specs.
    MarketQuote? goldQuote;
    MarketQuote? silverQuote;

    for (final q in quotes) {
      if (q.label.toLowerCase().contains('gold')) {
        goldQuote = q;
      } else if (q.label.toLowerCase().contains('silver')) {
        silverQuote = q;
      }
    }

    final goldPrice = goldQuote?.price ?? '₹10,250';
    final goldUnit = goldQuote?.unit ?? '/ gram';
    final goldChange = goldQuote != null
        ? '${goldQuote.changePercent >= 0 ? '+' : ''}${goldQuote.changePercent.toStringAsFixed(2)}%'
        : '+0.35%';

    final silverPrice = silverQuote?.price ?? '₹120.50';
    final silverUnit = silverQuote?.unit ?? '/ gram';
    final silverChange = silverQuote != null
        ? '${silverQuote.changePercent >= 0 ? '+' : ''}${silverQuote.changePercent.toStringAsFixed(2)}%'
        : '+0.28%';

    return Row(
      children: [
        // Gold Card
        Expanded(
          child: _MarketTile(
            title: 'Gold',
            price: goldPrice,
            unit: goldUnit,
            change: goldChange,
            backgroundColor: const Color(0xFFEAFBF7),
            accentColor: AppColors.primaryGreen,
            iconColor: AppColors.gold,
            icon: Icons.diamond_rounded,
            graphColors: const [AppColors.primaryGreen, AppColors.lightBlue],
            onTap: onTap,
          ),
        ),
        const SizedBox(width: 12),
        // Silver Card
        Expanded(
          child: _MarketTile(
            title: 'Silver',
            price: silverPrice,
            unit: silverUnit,
            change: silverChange,
            backgroundColor: const Color(0xFFEDF8FF),
            accentColor: AppColors.lightBlue,
            iconColor: AppColors.silver,
            icon: Icons.auto_awesome_rounded,
            graphColors: const [AppColors.lightBlue, AppColors.skyBlue],
            onTap: onTap,
          ),
        ),
      ],
    );
  }
}

class _MarketTile extends StatelessWidget {
  const _MarketTile({
    required this.title,
    required this.price,
    required this.unit,
    required this.change,
    required this.backgroundColor,
    required this.accentColor,
    required this.iconColor,
    required this.icon,
    required this.graphColors,
    this.onTap,
  });

  final String title;
  final String price;
  final String unit;
  final String change;
  final Color backgroundColor;
  final Color accentColor;
  final Color iconColor;
  final IconData icon;
  final List<Color> graphColors;
  final VoidCallback? onTap;

  static const List<double> _dummySparkline = [
    10.0, 10.5, 10.3, 11.0, 11.2, 11.8, 12.0
  ];

  @override
  Widget build(BuildContext context) {
    final isUp = !change.startsWith('-');

    final card = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: accentColor.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Icon + Title + Change Chip
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: accentColor.withValues(alpha: 0.12),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.textDark,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      unit,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: (isUp ? AppColors.positive : AppColors.negative)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  change,
                  style: TextStyle(
                    color: isUp ? AppColors.positive : AppColors.negative,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Price
          Text(
            price,
            style: const TextStyle(
              color: AppColors.textDark,
              fontSize: 19,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 10),
          // Mini Graph (Teal / Cyan Gradient)
          SizedBox(
            height: 36,
            width: double.infinity,
            child: Sparkline(
              values: _dummySparkline,
              color: accentColor,
              strokeWidth: 2.5,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return card;
    return PressableScale(
      pressedScale: 0.97,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: card,
      ),
    );
  }
}
