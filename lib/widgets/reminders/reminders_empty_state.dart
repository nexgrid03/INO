import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../pressable_scale.dart';

/// Shown when there are no reminders at all. A premium gradient illustration, a
/// warm message, and a single clear call to create the first reminder.
class RemindersEmptyState extends StatelessWidget {
  const RemindersEmptyState({super.key, required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
          vertical: 48, horizontal: AppSpacing.screen),
      child: Column(
        children: [
          Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              gradient: AppColors.brandGradient,
              borderRadius: BorderRadius.circular(AppRadius.large + 8),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryGreen.withValues(alpha: 0.30),
                  blurRadius: 28,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: const Icon(Icons.notifications_active_rounded,
                color: Colors.white, size: 50),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(l10n.t('noRemindersYet'),
              style: AppText.title.copyWith(color: palette.textPrimary)),
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.t('remindersEmptySubtitle'),
            textAlign: TextAlign.center,
            style: AppText.body
                .copyWith(color: palette.textSecondary, height: 1.5),
          ),
          const SizedBox(height: AppSpacing.lg),
          PressableScale(
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.button),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onCreate,
                child: Ink(
                  decoration: BoxDecoration(
                    gradient: AppColors.brandGradient,
                    borderRadius: BorderRadius.circular(AppRadius.button),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 28, vertical: 14),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.add_rounded,
                            color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                        Text(l10n.t('createReminder'),
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
        ],
      ),
    );
  }
}
