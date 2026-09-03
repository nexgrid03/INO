import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/reminder_models.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../common/shiny_icon.dart';
import '../dashboard/ino_card.dart';
import '../pressable_scale.dart';

/// A compact reminder row - the workhorse card used across every Reminders
/// surface, styled as a floating agenda card: a priority accent running down
/// the card's left edge, a glossy category icon badge, a bold title beside it,
/// a small meta line (due chip + category) under the title, and an optional
/// tap-to-complete circle on the right. Tapping the body opens details.
///
/// Deliberately short so a stack of them reads as a clean list rather than a
/// wall of boxes.
class ReminderCard extends StatelessWidget {
  const ReminderCard({
    super.key,
    required this.reminder,
    required this.today,
    this.onTap,
    this.onComplete,
  });

  final Reminder reminder;
  final DateTime today;
  final VoidCallback? onTap;

  /// When null, the trailing complete control is hidden (e.g. read-only lists).
  final VoidCallback? onComplete;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final categoryColor = reminder.category.color;
    final urgency = reminderUrgencyColor(reminder, today);

    return InoCard(
      radius: AppRadius.card,
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Priority accent running down the card's left edge.
              Container(width: 4, color: reminder.priority.color),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm + 2,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Glossy category icon badge — same vocabulary as Wallets.
                      ShinyIcon(
                        icon: reminder.category.icon,
                        color: categoryColor,
                        size: AppSizes.iconContainerSm,
                        iconSize: 22,
                        radius: AppRadius.chip,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              reminder.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.subtitle.copyWith(
                                color: palette.textPrimary,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 6),
                            // Due chip + category on one baseline, centred.
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Flexible(
                                  child: _DueBadge(
                                    label:
                                        '${reminder.localizedDueLabel(today, l10n)}'
                                        ' · ${reminder.timeLabel}',
                                    color: urgency,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    reminder.category.localizedLabel(l10n),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppText.label.copyWith(
                                      color: palette.textFaint,
                                      fontSize: 11,
                                      letterSpacing: 0.2,
                                      height: 1.0,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (onComplete != null) ...[
                        const SizedBox(width: AppSpacing.sm),
                        _CompleteButton(color: urgency, onTap: onComplete!),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DueBadge extends StatelessWidget {
  const _DueBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.label.copyWith(
                color: color,
                fontSize: 11,
                height: 1.0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompleteButton extends StatelessWidget {
  const _CompleteButton({required this.color, required this.onTap});

  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return PressableScale(
      pressedScale: 0.85,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: palette.border, width: 1.6),
            ),
            child: Icon(Icons.check_rounded, size: 17, color: palette.textFaint),
          ),
        ),
      ),
    );
  }
}
