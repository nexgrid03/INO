import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
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
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
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
              item.localizedTitle(l10n),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppText.body.copyWith(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w600,
                  height: 1.25),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          // Fixed-width, top-aligned time so it never squeezes the title.
          SizedBox(
            width: 76,
            child: Text(
              item.localizedTime(l10n),
              textAlign: TextAlign.right,
              maxLines: 2,
              style: AppText.caption.copyWith(color: palette.textFaint),
            ),
          ),
        ],
      ),
    );
  }
}
