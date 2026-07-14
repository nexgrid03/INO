import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/reminder_models.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';

/// A small "Recently Completed" row: a green check chip, the title, and when it
/// was completed. Compact and quiet — these are done, not demanding attention.
class CompletedReminderTile extends StatelessWidget {
  const CompletedReminderTile({
    super.key,
    required this.reminder,
    this.isLast = false,
  });

  final Reminder reminder;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : AppSpacing.sm),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primaryGreen.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.chip),
            ),
            child: const Icon(Icons.check_circle_rounded,
                size: 20, color: AppColors.primaryGreen),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  reminder.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body.copyWith(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  reminder.category.localizedLabel(l10n),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.caption.copyWith(color: palette.textFaint),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            reminder.completedLabel ?? l10n.t('done'),
            style: AppText.caption.copyWith(color: palette.textFaint),
          ),
        ],
      ),
    );
  }
}
