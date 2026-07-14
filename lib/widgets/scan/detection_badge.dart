import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/scan_models.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../wallet/wallet_grid.dart' show localizedWalletName;

/// Compact auto-detection summary shown above the editable OCR fields:
/// "Detected as PAN Card · Identity Wallet" with a colour-coded confidence
/// badge. Reassures the user that INO understood the document before they
/// review the details.
class DetectionBadge extends StatelessWidget {
  const DetectionBadge({
    super.key,
    required this.detectedType,
    required this.suggestedWallet,
    required this.confidence,
  });

  final String detectedType;
  final String suggestedWallet;
  final DetectionConfidence confidence;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primaryGreen.withValues(alpha: 0.10),
            AppColors.lightBlue.withValues(alpha: 0.10),
          ],
        ),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.primaryGreen.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Container(
            width: AppSizes.iconContainerSm,
            height: AppSizes.iconContainerSm,
            decoration: BoxDecoration(
              gradient: AppColors.brandGradient,
              borderRadius: BorderRadius.circular(AppRadius.chip),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryGreen.withValues(alpha: 0.30),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: const Icon(Icons.auto_awesome_rounded,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('${l10n.t('detectedAs')} ',
                        style: AppText.caption
                            .copyWith(color: palette.textSecondary)),
                    Flexible(
                      child: Text(
                        detectedType,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.subtitle.copyWith(
                            color: palette.textPrimary, fontSize: 13.5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(Icons.account_balance_wallet_rounded,
                        size: 13, color: palette.textFaint),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        localizedWalletName(l10n, suggestedWallet),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            AppText.caption.copyWith(color: palette.textSecondary),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          _ConfidenceChip(confidence: confidence),
        ],
      ),
    );
  }
}

class _ConfidenceChip extends StatelessWidget {
  const _ConfidenceChip({required this.confidence});

  final DetectionConfidence confidence;

  @override
  Widget build(BuildContext context) {
    final color = confidence.color;
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            confidence.localizedLabel(l10n),
            style: AppText.label.copyWith(color: color, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
