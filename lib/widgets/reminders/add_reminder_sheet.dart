import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/reminder_store.dart';
import '../../l10n/app_localizations.dart';
import '../../models/reminder_models.dart';
import '../../services/push_service.dart';
import '../../services/reminder_scheduler.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../common/ino_options_sheet.dart';
import '../pressable_scale.dart';
import '../common/ino_loader.dart';

/// Opens the "New Reminder" bottom sheet. Returns the created [Reminder] (also
/// already added to the [ReminderStore]) or null if dismissed.
///
/// Nothing is created until the form is complete: a date AND a time are
/// required and the moment must be in the future (the title is optional and
/// falls back to the category name). The sheet stays open with inline errors
/// until every field is valid and the server has actually accepted the row.
Future<Reminder?> showAddReminderSheet(
  BuildContext context, {
  ReminderCategory? initialCategory,
}) {
  final palette = AppPalette.of(context);
  return showModalBottomSheet<Reminder>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    backgroundColor: palette.surface,
    shape: const RoundedRectangleBorder(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(AppRadius.large)),
    ),
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

  /// Both deliberately start EMPTY - the user must pick them. A silently
  /// defaulted "tomorrow, whenever" is exactly the half-filled reminder this
  /// sheet exists to prevent.
  DateTime? _date;
  TimeOfDay? _time;

  bool _showCalendar = false;
  bool _saving = false;

  String? _dateError;
  String? _timeError;
  String? _saveError;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  void _setDate(DateTime d) {
    setState(() {
      _date = dateOnly(d);
      _dateError = null;
      _showCalendar = false;
    });
  }

  Future<void> _pickTime() async {
    final now = TimeOfDay.now();
    final picked = await showTimePicker(
      context: context,
      initialTime: _time ??
          TimeOfDay(hour: (now.hour + 1) % 24, minute: 0),
      helpText: AppLocalizations.of(context).t('pickTime').toUpperCase(),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _time = picked;
      _timeError = null;
    });
  }

  /// The exact local moment, or null while either half is missing.
  DateTime? get _moment {
    final d = _date;
    final t = _time;
    if (d == null || t == null) return null;
    return DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }

  /// Fills the inline errors; true when the form is complete and valid.
  bool _validate(AppLocalizations l10n) {
    String? dateError;
    String? timeError;
    if (_date == null) dateError = l10n.t('reminderDateRequired');
    if (_time == null) timeError = l10n.t('reminderTimeRequired');
    final moment = _moment;
    if (moment != null &&
        !moment.isAfter(DateTime.now().add(const Duration(minutes: 1)))) {
      timeError = l10n.t('reminderTimeInPast');
    }
    setState(() {
      _dateError = dateError;
      _timeError = timeError;
      _saveError = null;
    });
    return dateError == null && timeError == null;
  }

  Future<void> _create() async {
    if (_saving) return;
    final l10n = AppLocalizations.of(context);
    if (!_validate(l10n)) {
      HapticFeedback.heavyImpact();
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);

    // No title → the category name stands in, so the card never reads blank.
    var title = _titleController.text.trim();
    if (title.isEmpty) title = _category.localizedLabel(l10n);
    final reminder = Reminder(
      id: 'u${DateTime.now().microsecondsSinceEpoch}',
      title: title,
      subtitle: _category.localizedLabel(l10n),
      category: _category,
      priority: _priority,
      date: _moment!,
    );
    try {
      // Ask for push notification and exact-alarm permission when user creates a reminder.
      await PushService.instance.requestPermission();
      await ReminderScheduler.instance.ensureExactPermission();
      final saved = await ReminderStore.instance.add(reminder);
      if (!mounted) return;
      HapticFeedback.selectionClick();
      Navigator.of(context).pop(saved);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = l10n
            .t('reminderSaveFailed')
            .replaceAll('{error}', _describe(e));
      });
    }
  }

  static String _describe(Object e) {
    final text = e.toString();
    // Strip the exception class prefix Supabase adds so the sheet reads as a
    // sentence rather than a stack frame.
    final colon = text.indexOf(': ');
    return colon > 0 && colon < 40 ? text.substring(colon + 2) : text;
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final today = dateOnly(DateTime.now());
    final tomorrow = today.add(const Duration(days: 1));
    final nextWeek = today.add(const Duration(days: 7));
    final date = _date;
    final customDate =
        date != null && date != today && date != tomorrow && date != nextWeek;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(child: InoSheetGrip()),
              const SizedBox(height: AppSpacing.md),
              Text(l10n.t('newReminder'),
                  style:
                      AppText.headline.copyWith(color: palette.textPrimary)),
              const SizedBox(height: AppSpacing.md),

              _FieldLabel('${l10n.t('reminderTitle')} (${l10n.t('optional')})'),
              const SizedBox(height: AppSpacing.xs),
              TextField(
                controller: _titleController,
                autofocus: true,
                textInputAction: TextInputAction.done,
                textCapitalization: TextCapitalization.sentences,
                maxLength: 80,
                style: AppText.body.copyWith(color: palette.textPrimary),
                decoration: _inputDecoration(
                  palette,
                  '${l10n.t('reminderTitleHint')} (${l10n.t('optional')})',
                ),
              ),
              const SizedBox(height: AppSpacing.sm),

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
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  _QuickDateChip(
                    label: l10n.t('today'),
                    selected: date == today,
                    onTap: () => _setDate(today),
                  ),
                  _QuickDateChip(
                    label: l10n.t('tomorrow'),
                    selected: date == tomorrow,
                    onTap: () => _setDate(tomorrow),
                  ),
                  _QuickDateChip(
                    label: l10n.t('inDays').replaceAll('{n}', '7'),
                    selected: date == nextWeek,
                    onTap: () => _setDate(nextWeek),
                  ),
                  _QuickDateChip(
                    label: customDate
                        ? reminderShortDate(date)
                        : l10n.t('pickDate'),
                    selected: customDate,
                    icon: Icons.calendar_month_rounded,
                    onTap: () =>
                        setState(() => _showCalendar = !_showCalendar),
                  ),
                ],
              ),
              if (_dateError != null) _ErrorText(_dateError!),
              if (_showCalendar) ...[
                const SizedBox(height: AppSpacing.sm),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: palette.surfaceVariant,
                    borderRadius: BorderRadius.circular(AppRadius.chip),
                    border: Border.all(color: palette.border),
                  ),
                  child: CalendarDatePicker(
                    initialDate:
                        date == null || date.isBefore(today) ? today : date,
                    firstDate: today,
                    lastDate: DateTime(today.year + 6),
                    onDateChanged: _setDate,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),

              _FieldLabel(l10n.t('dueTime')),
              const SizedBox(height: AppSpacing.xs),
              _TimeButton(
                label: _time == null
                    ? l10n.t('pickTime')
                    : reminderTimeLabel(DateTime(
                        2000, 1, 1, _time!.hour, _time!.minute)),
                chosen: _time != null,
                onTap: _pickTime,
              ),
              if (_timeError != null) _ErrorText(_timeError!),
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
              if (_moment != null) ...[
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Icon(Icons.notifications_active_rounded,
                        size: 16, color: AppColors.primaryGreen),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        l10n.t('reminderWillRingAt').replaceAll(
                            '{when}', reminderDateTimeLabel(_moment!)),
                        style: AppText.caption
                            .copyWith(color: palette.textSecondary),
                      ),
                    ),
                  ],
                ),
              ],
              if (_saveError != null) ...[
                const SizedBox(height: AppSpacing.sm),
                _ErrorText(_saveError!),
              ],
              const SizedBox(height: AppSpacing.lg),

              _CreateButton(busy: _saving, onTap: _create),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(AppPalette palette, String hint,
      {String? error}) {
    OutlineInputBorder border(Color color) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
          borderSide: BorderSide(color: color),
        );
    return InputDecoration(
      hintText: hint,
      hintStyle: AppText.body.copyWith(color: palette.textFaint),
      filled: true,
      fillColor: palette.surface,
      counterText: '',
      errorText: error,
      contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: 14),
      border: border(palette.border),
      enabledBorder: border(palette.border),
      focusedBorder: border(AppColors.primaryGreen),
      errorBorder: border(AppColors.critical),
      focusedErrorBorder: border(AppColors.critical),
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

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 14, color: AppColors.critical),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              text,
              style: AppText.caption
                  .copyWith(color: AppColors.critical, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeButton extends StatelessWidget {
  const _TimeButton({
    required this.label,
    required this.chosen,
    required this.onTap,
  });

  final String label;
  final bool chosen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final color = AppColors.primaryGreen;
    return PressableScale(
      pressedScale: 0.97,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.button),
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            decoration: BoxDecoration(
              color: chosen ? color.withValues(alpha: 0.12) : palette.surface,
              borderRadius: BorderRadius.circular(AppRadius.button),
              border: Border.all(
                color: chosen ? color : palette.border,
                width: chosen ? 1.4 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.schedule_rounded,
                    size: 18, color: chosen ? color : palette.textSecondary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: AppText.body.copyWith(
                      color: chosen ? color : palette.textSecondary,
                      fontWeight: chosen ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    size: 20, color: palette.textFaint),
              ],
            ),
          ),
        ),
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

class _QuickDateChip extends StatelessWidget {
  const _QuickDateChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final color = AppColors.primaryGreen;
    return PressableScale(
      pressedScale: 0.95,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? color.withValues(alpha: 0.14) : palette.surfaceVariant,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(
                color: selected ? color : palette.border,
                width: selected ? 1.4 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon,
                      size: 15,
                      color: selected ? color : palette.textSecondary),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
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
  const _CreateButton({required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      pressedScale: busy ? 1.0 : 0.97,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.button),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: busy ? null : onTap,
          child: Ink(
            decoration: BoxDecoration(
              gradient: AppColors.brandGradient,
              borderRadius: BorderRadius.circular(AppRadius.button),
            ),
            child: Container(
              height: 52,
              alignment: Alignment.center,
              child: busy
                  ? const InoLoader(size: 22, color: Colors.white)
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.add_rounded,
                            color: Colors.white, size: 20),
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
    );
  }
}
