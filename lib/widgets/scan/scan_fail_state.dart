import 'package:flutter/material.dart';

import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../pressable_scale.dart';

/// Shown when OCR can't read the capture. A calm illustration, a plain-language
/// message, and two clear ways forward: try the scan again, or skip OCR and fill
/// the details in by hand.
class ScanFailState extends StatelessWidget {
  const ScanFailState({
    super.key,
    required this.message,
    required this.onTryAgain,
    required this.onManualEntry,
  });

  final String message;
  final VoidCallback onTryAgain;
  final VoidCallback onManualEntry;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.screen),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.large + 8),
              ),
              child: Icon(Icons.document_scanner_outlined,
                  color: AppColors.warning, size: 50),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Unable to extract information',
              textAlign: TextAlign.center,
              style: AppText.title.copyWith(color: palette.textPrimary),
            ),
            const SizedBox(height: AppSpacing.xs),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: AppText.body
                    .copyWith(color: palette.textSecondary, height: 1.5),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            // Primary — try again.
            PressableScale(
              child: Container(
                height: AppSizes.button,
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: AppColors.brandGradient,
                  borderRadius: BorderRadius.circular(AppRadius.button),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryGreen.withValues(alpha: 0.30),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onTryAgain,
                    borderRadius: BorderRadius.circular(AppRadius.button),
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.refresh_rounded,
                              color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                          Text('Try Again',
                              style: AppText.subtitle.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            // Secondary — manual entry.
            PressableScale(
              child: Material(
                color: palette.surface,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.button),
                  side: BorderSide(color: palette.border),
                ),
                child: InkWell(
                  onTap: onManualEntry,
                  child: SizedBox(
                    height: AppSizes.button,
                    width: double.infinity,
                    child: Center(
                      child: Text('Manual Entry',
                          style: AppText.subtitle
                              .copyWith(color: palette.textSecondary)),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
