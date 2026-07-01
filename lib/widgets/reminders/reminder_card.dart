import 'package:flutter/material.dart';

import '../../models/reminder_models.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../dashboard/ino_card.dart';
import '../pressable_scale.dart';

/// A compact reminder row — the workhorse card used across every Reminders
/// surface. One tight line for the title, one meta line for the due badge +
/// category. A priority accent bar on the left, and an optional tap-to-complete
/// circle on the right. Tapping the body opens details.
///
/// Deliberately short (~64dp) so a stack of them reads as a clean list rather
/// than a wall of boxes.
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
    final categoryColor = reminder.category.color;
    final urgency = reminderUrgencyColor(reminder, today);

    return InoCard(
      radius: AppRadius.card,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
      onTap: onTap,
      child: Row(
        children: [
          // Priority accent bar.
          Container(
            width: 4,
            height: 42,
            decoration: BoxDecoration(
              color: reminder.priority.color,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          // Category icon chip.
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: categoryColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.chip),
            ),
            child: Icon(reminder.category.icon, color: categoryColor, size: 21),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  reminder.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.subtitle.copyWith(
                    color: palette.textPrimary,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    _DueBadge(label: reminder.dueLabel(today), color: urgency),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        reminder.category.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.label
                            .copyWith(color: palette.textFaint, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (onComplete != null) ...[
            const SizedBox(width: AppSpacing.xs),
            _CompleteButton(color: urgency, onTap: onComplete!),
          ],
        ],
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
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: AppText.label.copyWith(color: color, fontSize: 11),
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
