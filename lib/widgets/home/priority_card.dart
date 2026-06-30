import 'package:flutter/material.dart';

import '../../models/dashboard_models.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../dashboard/ino_card.dart';

/// Section 3 — a single Priority Center card (premium vertical format).
///
/// A compact card for a horizontal row: tinted icon chip top-left, a status
/// badge top-right (colour-coded by urgency), then title, subtitle and a
/// chevron. Home surfaces only the top three.
class PriorityCard extends StatelessWidget {
  const PriorityCard({super.key, required this.item, this.onTap});

  final PriorityItem item;
  final VoidCallback? onTap;

  Color get _color {
    switch (item.level) {
      case PriorityLevel.critical:
        return AppColors.critical; // red
      case PriorityLevel.important:
        return AppColors.warning; // orange
      case PriorityLevel.info:
        return AppColors.primaryGreen; // green
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final color = _color;
    return InoCard(
      radius: AppRadius.card,
      padding: const EdgeInsets.all(AppSpacing.md),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: AppSizes.iconContainerSm,
                height: AppSizes.iconContainerSm,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
                child: Icon(item.icon, color: color, size: 22),
              ),
              const Spacer(),
              Flexible(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    item.due,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.label.copyWith(color: color, fontSize: 10.5),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            item.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppText.subtitle.copyWith(
              color: palette.textPrimary,
              fontSize: 14.5,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            item.subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.caption.copyWith(color: palette.textSecondary),
          ),
          const Spacer(),
          Align(
            alignment: Alignment.centerRight,
            child: Icon(AppIcons.chevron, size: 20, color: palette.textFaint),
          ),
        ],
      ),
    );
  }
}
