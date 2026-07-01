import 'package:flutter/material.dart';

import '../../data/reminder_store.dart';
import '../../models/reminder_models.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/reminders/month_calendar.dart';
import '../../widgets/reminders/reminder_card.dart';
import '../../widgets/reminders/reminder_detail_sheet.dart';

/// A dedicated month calendar. Days with reminders are dotted; tapping a date
/// lists that day's reminders below. Moved off the home screen so the daily
/// view stays fast and uncluttered.
class ReminderCalendarScreen extends StatefulWidget {
  const ReminderCalendarScreen({super.key});

  @override
  State<ReminderCalendarScreen> createState() => _ReminderCalendarScreenState();
}

class _ReminderCalendarScreenState extends State<ReminderCalendarScreen> {
  final _store = ReminderStore.instance;

  late DateTime _month;
  int? _selectedDay;

  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June', //
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  @override
  void initState() {
    super.initState();
    final today = _store.today;
    _month = DateTime(today.year, today.month);
    _selectedDay = today.day;
    _store.ensureLoaded();
  }

  void _shiftMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
      _selectedDay = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        title: Text('Calendar',
            style: AppText.title.copyWith(color: palette.textPrimary)),
      ),
      body: ListenableBuilder(
        listenable: _store,
        builder: (context, _) {
          if (!_store.isLoaded) {
            return const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2.6,
                color: AppColors.primaryGreen,
              ),
            );
          }
          final selected = _selectedDay == null
              ? null
              : DateTime(_month.year, _month.month, _selectedDay!);
          final dayReminders = selected == null
              ? const <Reminder>[]
              : _store.onDay(selected, ReminderFilterKind.all);

          return ListView(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.screen, AppSpacing.sm, AppSpacing.screen, 40),
            physics: const BouncingScrollPhysics(),
            children: [
              MonthCalendar(
                month: _month,
                today: _store.today,
                markedDays:
                    _store.markedDaysIn(_month, ReminderFilterKind.all),
                selectedDay: _selectedDay,
                onSelectDay: (d) => setState(() => _selectedDay = d),
                onPrev: () => _shiftMonth(-1),
                onNext: () => _shiftMonth(1),
              ),
              const SizedBox(height: AppSpacing.md),
              if (selected != null)
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: AppSpacing.xs),
                  child: Text(
                    '$_selectedDay ${_monthNames[_month.month - 1]}',
                    style:
                        AppText.title.copyWith(color: palette.textPrimary),
                  ),
                ),
              if (selected != null && dayReminders.isEmpty)
                _NoReminderNote(palette: palette)
              else
                for (final r in dayReminders)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: ReminderCard(
                      reminder: r,
                      today: _store.today,
                      onTap: () => showReminderDetail(context, r),
                      onComplete: () => _store.complete(r),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}

class _NoReminderNote extends StatelessWidget {
  const _NoReminderNote({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      decoration: BoxDecoration(
        color: palette.surfaceVariant,
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Row(
        children: [
          Icon(Icons.event_available_rounded,
              size: 18, color: palette.textFaint),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'No reminders on this day',
              style: AppText.caption.copyWith(color: palette.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
