import 'package:flutter/material.dart';

import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';

/// A compact storage-usage meter: "1.2 GB of 5 GB" with an animated green→blue
/// gradient progress bar. Sits at the top of the Data & Storage card.
class StorageMeter extends StatelessWidget {
  const StorageMeter({
    super.key,
    required this.usedLabel,
    required this.totalLabel,
    required this.fraction,
  });

  final String usedLabel; // "1.2 GB"
  final String totalLabel; // "5 GB"
  final double fraction; // 0..1

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final pct = (fraction.clamp(0.0, 1.0) * 100).round();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm, AppSpacing.sm, AppSpacing.sm, AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                usedLabel,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                'of $totalLabel used',
                style: AppText.caption.copyWith(color: palette.textSecondary),
              ),
              const Spacer(),
              Text(
                '$pct%',
                style: AppText.label.copyWith(
                  color: AppColors.primaryGreen,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: Stack(
              children: [
                Container(height: 8, color: palette.surfaceVariant),
                LayoutBuilder(
                  builder: (context, constraints) => Container(
                    height: 8,
                    width: constraints.maxWidth * fraction.clamp(0.0, 1.0),
                    decoration: const BoxDecoration(
                      gradient: AppColors.brandGradient,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
