import 'package:flutter/material.dart';

import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../dashboard/ino_card.dart';
import '../pressable_scale.dart';

/// A compact monthly calendar. Days with reminders show an accent dot, today is
/// ringed, and the selected day is a gradient pill. Month navigation is driven
/// by [onPrev] / [onNext]; day selection by [onSelectDay].
class MonthCalendar extends StatelessWidget {
  const MonthCalendar({
    super.key,
    required this.month,
    required this.today,
    required this.markedDays,
    required this.selectedDay,
    required this.onSelectDay,
    required this.onPrev,
    required this.onNext,
  });

  /// Any date within the visible month.
  final DateTime month;
  final DateTime today;

  /// Day numbers (1..31) in this month that have reminders.
  final Set<int> markedDays;
  final int? selectedDay;
  final ValueChanged<int> onSelectDay;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June', //
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  static const _weekdays = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

  bool get _isCurrentMonth =>
      month.year == today.year && month.month == today.month;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final firstWeekday = DateTime(month.year, month.month, 1).weekday % 7; // Sun=0
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;

    // Build cells: leading blanks + day numbers, chunked into weeks.
    final cells = <int?>[
      ...List<int?>.filled(firstWeekday, null),
      for (var d = 1; d <= daysInMonth; d++) d,
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    final weeks = <List<int?>>[
      for (var i = 0; i < cells.length; i += 7) cells.sublist(i, i + 7),
    ];

    return InoCard(
      radius: AppRadius.card,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        children: [
          // Month header + navigation.
          Row(
            children: [
              Text(
                '${_monthNames[month.month - 1]} ${month.year}',
                style: AppText.title.copyWith(color: palette.textPrimary),
              ),
              const Spacer(),
              _NavButton(icon: Icons.chevron_left_rounded, onTap: onPrev),
              const SizedBox(width: 6),
              _NavButton(icon: Icons.chevron_right_rounded, onTap: onNext),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          // Weekday labels.
          Row(
            children: [
              for (final w in _weekdays)
                Expanded(
                  child: Center(
                    child: Text(
                      w,
                      style: AppText.label.copyWith(
                        color: palette.textFaint,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          // Weeks.
          for (final week in weeks)
            Row(
              children: [
                for (final day in week)
                  Expanded(
                    child: _DayCell(
                      day: day,
                      marked: day != null && markedDays.contains(day),
                      isToday: _isCurrentMonth && day == today.day,
                      isSelected: day != null && day == selectedDay,
                      onTap: day == null ? null : () => onSelectDay(day),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.marked,
    required this.isToday,
    required this.isSelected,
    required this.onTap,
  });

  final int? day;
  final bool marked;
  final bool isToday;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    if (day == null) return const SizedBox(height: 34);

    final Color textColor = isSelected
        ? Colors.white
        : isToday
            ? AppColors.primaryGreen
            : palette.textPrimary;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: 34,
        child: Center(
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              gradient: isSelected ? AppColors.brandGradient : null,
              shape: BoxShape.circle,
              border: isToday && !isSelected
                  ? Border.all(color: AppColors.primaryGreen, width: 1.4)
                  : null,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Text(
                  '$day',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isToday || isSelected
                        ? FontWeight.w800
                        : FontWeight.w600,
                    color: textColor,
                  ),
                ),
                if (marked)
                  Positioned(
                    bottom: 3,
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.white : AppColors.lightBlue,
                        shape: BoxShape.circle,
                      ),
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

class _NavButton extends StatelessWidget {
  const _NavButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return PressableScale(
      pressedScale: 0.88,
      child: Material(
        color: palette.surfaceVariant,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 32,
            height: 32,
            child: Icon(icon, size: 20, color: palette.textPrimary),
          ),
        ),
      ),
    );
  }
}
