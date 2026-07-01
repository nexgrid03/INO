import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Models backing the Reminders Dashboard — the Life Events & Due Dates center.
/// UI-agnostic plain objects, hydrated today by `ReminderRepository`'s sample
/// data and tomorrow by Supabase without touching a single widget.

const List<String> _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Compact, intl-free date: "12 Jul".
String reminderShortDate(DateTime d) => '${d.day} ${_months[d.month - 1]}';

/// Truncates a datetime to midnight (date-only comparisons).
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

// ---------------------------------------------------------------------------
// Priority
// ---------------------------------------------------------------------------

enum ReminderPriority { critical, important, normal }

extension ReminderPriorityX on ReminderPriority {
  String get label {
    switch (this) {
      case ReminderPriority.critical:
        return 'Critical';
      case ReminderPriority.important:
        return 'Important';
      case ReminderPriority.normal:
        return 'Normal';
    }
  }

  Color get color {
    switch (this) {
      case ReminderPriority.critical:
        return AppColors.critical; // red
      case ReminderPriority.important:
        return AppColors.warning; // orange
      case ReminderPriority.normal:
        return AppColors.primaryGreen; // green
    }
  }
}

// ---------------------------------------------------------------------------
// Category
// ---------------------------------------------------------------------------

enum ReminderCategory {
  documents,
  insurance,
  health,
  property,
  investments,
  birthdays,
  anniversaries,
  custom,
}

extension ReminderCategoryX on ReminderCategory {
  String get label {
    switch (this) {
      case ReminderCategory.documents:
        return 'Documents';
      case ReminderCategory.insurance:
        return 'Insurance';
      case ReminderCategory.health:
        return 'Health';
      case ReminderCategory.property:
        return 'Property';
      case ReminderCategory.investments:
        return 'Investments';
      case ReminderCategory.birthdays:
        return 'Birthdays';
      case ReminderCategory.anniversaries:
        return 'Anniversaries';
      case ReminderCategory.custom:
        return 'Custom';
    }
  }

  IconData get icon {
    switch (this) {
      case ReminderCategory.documents:
        return Icons.description_rounded;
      case ReminderCategory.insurance:
        return Icons.shield_rounded;
      case ReminderCategory.health:
        return Icons.favorite_rounded;
      case ReminderCategory.property:
        return Icons.home_work_rounded;
      case ReminderCategory.investments:
        return Icons.trending_up_rounded;
      case ReminderCategory.birthdays:
        return Icons.cake_rounded;
      case ReminderCategory.anniversaries:
        return Icons.celebration_rounded;
      case ReminderCategory.custom:
        return Icons.bolt_rounded;
    }
  }

  Color get color {
    switch (this) {
      case ReminderCategory.documents:
        return AppColors.lightBlue;
      case ReminderCategory.insurance:
        return AppColors.warning;
      case ReminderCategory.health:
        return const Color(0xFFEC6A8C);
      case ReminderCategory.property:
        return const Color(0xFF8B6CEF);
      case ReminderCategory.investments:
        return const Color(0xFF2BB6A3);
      case ReminderCategory.birthdays:
        return const Color(0xFFF5704A);
      case ReminderCategory.anniversaries:
        return const Color(0xFFEC4899);
      case ReminderCategory.custom:
        return AppColors.primaryGreen;
    }
  }

  /// Categories that represent an *expiry* (feed the "Expiring Soon" summary).
  bool get isExpiryKind =>
      this == ReminderCategory.documents ||
      this == ReminderCategory.insurance ||
      this == ReminderCategory.property;
}

// ---------------------------------------------------------------------------
// Reminder
// ---------------------------------------------------------------------------

class Reminder {
  const Reminder({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.category,
    required this.priority,
    required this.date,
    this.completed = false,
    this.completedLabel,
  });

  final String id;
  final String title;
  final String subtitle;
  final ReminderCategory category;
  final ReminderPriority priority;
  final DateTime date;
  final bool completed;

  /// When [completed], a human label of when ("2 days ago").
  final String? completedLabel;

  /// Whole-day offset from [today] (negative = overdue).
  int daysFrom(DateTime today) =>
      dateOnly(date).difference(dateOnly(today)).inDays;

  /// A human due label relative to [today].
  String dueLabel(DateTime today) {
    final d = daysFrom(today);
    if (d < 0) return d == -1 ? 'Overdue by 1 day' : 'Overdue by ${-d} days';
    if (d == 0) return 'Due Today';
    if (d == 1) return 'Due Tomorrow';
    if (d <= 6) return 'In $d days';
    if (d <= 13) return 'Next week';
    return reminderShortDate(date);
  }

  Reminder copyWith({bool? completed, String? completedLabel}) => Reminder(
        id: id,
        title: title,
        subtitle: subtitle,
        category: category,
        priority: priority,
        date: date,
        completed: completed ?? this.completed,
        completedLabel: completedLabel ?? this.completedLabel,
      );
}

// ---------------------------------------------------------------------------
// Summary
// ---------------------------------------------------------------------------

/// The four compact headline counts across the top of the dashboard.
class ReminderSummary {
  const ReminderSummary({
    required this.dueToday,
    required this.upcomingThisWeek,
    required this.expiringSoon,
    required this.completedThisMonth,
  });

  final int dueToday;
  final int upcomingThisWeek;
  final int expiringSoon;
  final int completedThisMonth;
}

// ---------------------------------------------------------------------------
// Aggregate read model
// ---------------------------------------------------------------------------

class ReminderData {
  const ReminderData({
    required this.today,
    required this.reminders,
    required this.completed,
    required this.summary,
  });

  /// The reference "now" the whole dashboard computes against.
  final DateTime today;

  /// Active (not completed) reminders, ascending by date.
  final List<Reminder> reminders;

  /// Recently completed reminders (newest first).
  final List<Reminder> completed;

  final ReminderSummary summary;
}
