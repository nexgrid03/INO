import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/reminder_store.dart';
import '../../models/reminder_models.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../pressable_scale.dart';

/// Opens a reminder's detail sheet — full title, note, category, priority and
/// due date, with real actions (mark done / delete). Mutations go straight to
/// the [ReminderStore] so every screen updates.
Future<void> showReminderDetail(BuildContext context, Reminder reminder) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ReminderDetailSheet(reminder: reminder),
  );
}

class _ReminderDetailSheet extends StatelessWidget {
  const _ReminderDetailSheet({required this.reminder});

  final Reminder reminder;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final store = ReminderStore.instance;
    final categoryColor = reminder.category.color;
    final urgency = reminderUrgencyColor(reminder, store.today);

    return Container(
      decoration: BoxDecoration(
        color: palette.bg,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(AppRadius.large)),
      ),
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.lg),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                decoration: BoxDecoration(
                  color: palette.border,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: AppSizes.iconContainerSm,
                  height: AppSizes.iconContainerSm,
                  decoration: BoxDecoration(
                    color: categoryColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.chip),
                  ),
                  child: Icon(reminder.category.icon,
                      color: categoryColor, size: 22),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        reminder.title,
                        style: AppText.title.copyWith(color: palette.textPrimary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        reminder.category.label,
                        style: AppText.caption
                            .copyWith(color: palette.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (reminder.subtitle.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                reminder.subtitle,
                style: AppText.body
                    .copyWith(color: palette.textSecondary, height: 1.45),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                _MetaPill(
                  icon: Icons.event_rounded,
                  label: reminder.dueLabel(store.today),
                  color: urgency,
                ),
                const SizedBox(width: AppSpacing.xs),
                _MetaPill(
                  icon: Icons.flag_rounded,
                  label: reminder.priority.label,
                  color: reminder.priority.color,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            if (!reminder.completed) ...[
              _PrimaryAction(
                label: 'Mark as Done',
                icon: Icons.check_circle_rounded,
                onTap: () {
                  store.complete(reminder);
                  HapticFeedback.selectionClick();
                  Navigator.of(context).pop();
                },
              ),
              const SizedBox(height: AppSpacing.xs),
            ],
            _SecondaryAction(
              label: 'Delete Reminder',
              icon: Icons.delete_outline_rounded,
              color: AppColors.critical,
              onTap: () {
                store.remove(reminder);
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(label, style: AppText.label.copyWith(color: color, fontSize: 12)),
        ],
      ),
    );
  }
}

class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.button),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              gradient: AppColors.brandGradient,
              borderRadius: BorderRadius.circular(AppRadius.button),
            ),
            child: Container(
              height: 52,
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: AppText.subtitle.copyWith(
                        color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SecondaryAction extends StatelessWidget {
  const _SecondaryAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.button),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 50,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.button),
            border: Border.all(color: palette.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 19),
              const SizedBox(width: 8),
              Text(
                label,
                style: AppText.subtitle
                    .copyWith(color: color, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
