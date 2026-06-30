import 'package:flutter/material.dart';

import '../../models/dashboard_models.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';

/// Section 6 — a single Recent Activity row.
///
/// Soft-tinted icon chip · title · trailing time. Clean list rows (no timeline
/// rail); Home shows the latest five.
class ActivityTile extends StatelessWidget {
  const ActivityTile({
    super.key,
    required this.item,
    this.isLast = false,
  });

  final ActivityItem item;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : AppSpacing.md),
      child: Row(
        children: [
          Container(
            width: AppSizes.iconContainerSm,
            height: AppSizes.iconContainerSm,
            decoration: BoxDecoration(
              color: item.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.chip),
            ),
            child: Icon(item.icon, size: 20, color: item.color),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.body.copyWith(
                  color: palette.textPrimary, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            item.time,
            style: AppText.caption.copyWith(color: palette.textFaint),
          ),
        ],
      ),
    );
  }
}
