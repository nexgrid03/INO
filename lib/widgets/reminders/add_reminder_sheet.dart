import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/reminder_store.dart';
import '../../l10n/app_localizations.dart';
import '../../models/reminder_models.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../pressable_scale.dart';

/// Opens the "New Reminder" bottom sheet. Returns the created [Reminder] (also
/// already added to the [ReminderStore]) or null if dismissed.
Future<Reminder?> showAddReminderSheet(
  BuildContext context, {
  ReminderCategory? initialCategory,
}) {
  return showModalBottomSheet<Reminder>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AddReminderSheet(initialCategory: initialCategory),
  );
}

class _AddReminderSheet extends StatefulWidget {
  const _AddReminderSheet({this.initialCategory});

  final ReminderCategory? initialCategory;

  @override
  State<_AddReminderSheet> createState() => _AddReminderSheetState();
}

class _AddReminderSheetState extends State<_AddReminderSheet> {
  final _titleController = TextEditingController();
  late ReminderCategory _category =
      widget.initialCategory ?? ReminderCategory.custom;
  ReminderPriority _priority = ReminderPriority.normal;
  late DateTime _date = dateOnly(DateTime.now()).add(const Duration(days: 1));
  bool _titleEmpty = true;

  @override
  void initState() {
    super.initState();
    _titleController.addListener(() {
      final empty = _titleController.text.trim().isEmpty;
      if (empty != _titleEmpty) setState(() => _titleEmpty = empty);
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final today = dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: today,
      lastDate: DateTime(today.year + 6),
    );
    if (picked != null) setState(() => _date = dateOnly(picked));
  }

  void _create() {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;
    final reminder = Reminder(
      id: 'u${DateTime.now().microsecondsSinceEpoch}',
      title: title,
      subtitle: _category.label,
      category: _category,
      priority: _priority,
      date: _date,
    );
    ReminderStore.instance.add(reminder);
    HapticFeedback.selectionClick();
    Navigator.of(context).pop(reminder);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: BoxDecoration(
          color: palette.bg,
          borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppRadius.large)),
        ),
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.lg),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Grip.
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
                Text(l10n.t('newReminder'),
                    style: AppText.headline.copyWith(color: palette.textPrimary)),
                const SizedBox(height: AppSpacing.md),

                _FieldLabel(l10n.t('reminderTitle')),
                const SizedBox(height: AppSpacing.xs),
                TextField(
                  controller: _titleController,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _create(),
                  style: AppText.body.copyWith(color: palette.textPrimary),
                  decoration:
                      _inputDecoration(palette, l10n.t('reminderTitleHint')),
                ),
                const SizedBox(height: AppSpacing.md),

                _FieldLabel(l10n.t('type')),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (final c in ReminderCategory.values)
                      _TypeChip(
                        category: c,
                        selected: c == _category,
                        onTap: () => setState(() => _category = c),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),

                _FieldLabel(l10n.t('dueDate')),
                const SizedBox(height: AppSpacing.xs),
                _DateRow(date: _date, onTap: _pickDate),
                const SizedBox(height: AppSpacing.md),

                _FieldLabel(l10n.t('priority')),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    for (final p in ReminderPriority.values) ...[
                      if (p != ReminderPriority.values.first)
                        const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: _PriorityChip(
                          priority: p,
                          selected: p == _priority,
                          onTap: () => setState(() => _priority = p),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),

                _CreateButton(enabled: !_titleEmpty, onTap: _create),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(AppPalette palette, String hint) {
    OutlineInputBorder border(Color color) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
          borderSide: BorderSide(color: color),
        );
    return InputDecoration(
      hintText: hint,
      hintStyle: AppText.body.copyWith(color: palette.textFaint),
      filled: true,
      fillColor: palette.surface,
      contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: 14),
      border: border(palette.border),
      enabledBorder: border(palette.border),
      focusedBorder: border(AppColors.primaryGreen),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Text(
      text.toUpperCase(),
      style: AppText.label.copyWith(
        color: palette.textFaint,
        fontSize: 11,
        letterSpacing: 0.6,
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final ReminderCategory category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final color = category.color;
    return PressableScale(
      pressedScale: 0.95,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? color.withValues(alpha: 0.14) : palette.surface,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(
                color: selected ? color : palette.border,
                width: selected ? 1.4 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(category.icon,
                    size: 15,
                    color: selected ? color : palette.textSecondary),
                const SizedBox(width: 6),
                Text(
                  category.localizedLabel(AppLocalizations.of(context)),
                  style: AppText.label.copyWith(
                    fontSize: 12,
                    color: selected ? color : palette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DateRow extends StatelessWidget {
  const _DateRow({required this.date, required this.onTap});

  final DateTime date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(AppRadius.button),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.button),
            border: Border.all(color: palette.border),
          ),
          child: Row(
            children: [
              const Icon(Icons.event_rounded,
                  size: 19, color: AppColors.primaryGreen),
              const SizedBox(width: AppSpacing.sm),
              Text(
                reminderShortDate(date),
                style: AppText.body.copyWith(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Icon(Icons.chevron_right_rounded, color: palette.textFaint),
            ],
          ),
        ),
      ),
    );
  }
}

class _PriorityChip extends StatelessWidget {
  const _PriorityChip({
    required this.priority,
    required this.selected,
    required this.onTap,
  });

  final ReminderPriority priority;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final color = priority.color;
    return PressableScale(
      pressedScale: 0.95,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.button),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 11),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? color.withValues(alpha: 0.14) : palette.surface,
              borderRadius: BorderRadius.circular(AppRadius.button),
              border: Border.all(
                color: selected ? color : palette.border,
                width: selected ? 1.4 : 1,
              ),
            ),
            child: Text(
              priority.localizedLabel(AppLocalizations.of(context)),
              style: AppText.label.copyWith(
                fontSize: 12.5,
                color: selected ? color : palette.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CreateButton extends StatelessWidget {
  const _CreateButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: PressableScale(
        pressedScale: enabled ? 0.97 : 1.0,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.button),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? onTap : null,
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
                    const Icon(Icons.add_rounded, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      AppLocalizations.of(context).t('createReminder'),
                      style: AppText.subtitle.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
