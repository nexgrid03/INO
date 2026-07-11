import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/area_unit.dart';
import '../../services/area_conversion_service.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../dashboard/ino_card.dart';

/// "Area Conversion Summary" — a reusable INO card that shows [value] [fromUnit]
/// converted into every other supported unit, plus a Copy All action.
///
/// Pure presentation: all maths comes from [AreaConversionService]; the widget
/// never computes a factor itself.
class AreaConversionSummary extends StatelessWidget {
  const AreaConversionSummary({
    super.key,
    required this.value,
    required this.fromUnit,
    this.units = AreaConversionService.displayOrder,
    this.title = 'Area Conversion Summary',
  });

  /// The entered area value (in [fromUnit]).
  final double value;

  /// The unit [value] is expressed in.
  final AreaUnit fromUnit;

  /// Which target units to show (source unit is excluded automatically).
  final List<AreaUnit> units;

  final String title;

  static const _service = AreaConversionService.instance;

  void _copyAll(BuildContext context) {
    final text = _service.asCopyText(value, fromUnit, units: units);
    Clipboard.setData(ClipboardData(text: text));
    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Area conversions copied to clipboard'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.primaryGreen,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final conversions = _service.summary(value, fromUnit, units: units);

    return InoCard(
      radius: AppRadius.card,
      padding: const EdgeInsets.all(AppSpacing.internal),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ---- Header ----
          Row(
            children: [
              Container(
                width: AppSizes.iconContainerSm,
                height: AppSizes.iconContainerSm,
                decoration: BoxDecoration(
                  gradient: AppColors.brandGradient,
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
                child: const Icon(Icons.straighten_rounded,
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: AppText.title
                            .copyWith(color: palette.textPrimary)),
                    const SizedBox(height: 2),
                    Text(
                      _service.formatWithUnit(value, fromUnit),
                      style:
                          AppText.caption.copyWith(color: palette.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // ---- Responsive conversion grid ----
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = AppSpacing.xs;
              final cols =
                  (constraints.maxWidth / 168).floor().clamp(2, 4).toInt();
              final tileWidth =
                  (constraints.maxWidth - (cols - 1) * gap) / cols;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final c in conversions)
                    SizedBox(
                      width: tileWidth,
                      child: _ConversionTile(conversion: c),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.md),

          // ---- Copy All ----
          _CopyAllButton(onTap: () => _copyAll(context)),
        ],
      ),
    );
  }
}

class _ConversionTile extends StatelessWidget {
  const _ConversionTile({required this.conversion});

  final AreaConversion conversion;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.xs + 2),
      decoration: BoxDecoration(
        color: palette.surfaceVariant,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            conversion.display,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.title.copyWith(
              color: AppColors.darkGreen,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            conversion.unit.shortLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.caption.copyWith(color: palette.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _CopyAllButton extends StatelessWidget {
  const _CopyAllButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primaryGreen.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(AppRadius.button),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: AppSizes.button,
          width: double.infinity,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.copy_rounded,
                  size: 18, color: AppColors.darkGreen),
              const SizedBox(width: AppSpacing.xs),
              Text(
                'Copy All',
                style: AppText.subtitle.copyWith(
                  color: AppColors.darkGreen,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
