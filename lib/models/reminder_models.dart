import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
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

  /// Localized [label].
  String localizedLabel(AppLocalizations l10n) {
    switch (this) {
      case ReminderPriority.critical:
        return l10n.t('critical');
      case ReminderPriority.important:
        return l10n.t('important');
      case ReminderPriority.normal:
        return l10n.t('normal');
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

  /// Localized [label].
  String localizedLabel(AppLocalizations l10n) {
    switch (this) {
      case ReminderCategory.documents:
        return l10n.t('documents');
      case ReminderCategory.insurance:
        return l10n.t('insurance');
      case ReminderCategory.health:
        return l10n.t('health');
      case ReminderCategory.property:
        return l10n.t('property');
      case ReminderCategory.investments:
        return l10n.t('investments');
      case ReminderCategory.birthdays:
        return l10n.t('birthdays');
      case ReminderCategory.anniversaries:
        return l10n.t('anniversaries');
      case ReminderCategory.custom:
        return l10n.t('custom');
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
        return const Color(0xFF30ACB3);
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

  /// Localized [dueLabel] relative to [today].
  String localizedDueLabel(DateTime today, AppLocalizations l10n) {
    final d = daysFrom(today);
    if (d < 0) {
      return d == -1
          ? l10n.t('overdueByOneDay')
          : l10n.t('overdueByDays').replaceAll('{n}', '${-d}');
    }
    if (d == 0) return l10n.t('dueToday');
    if (d == 1) return l10n.t('dueTomorrow');
    if (d <= 6) return l10n.t('inDays').replaceAll('{n}', '$d');
    if (d <= 13) return l10n.t('nextWeek');
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

  /// Builds a [Reminder] from a `public.reminders` table row.
  factory Reminder.fromMap(Map<String, dynamic> m) {
    final completedAt = m['completed_at'] == null
        ? null
        : DateTime.parse(m['completed_at'] as String);
    return Reminder(
      id: m['id'] as String,
      title: m['title'] as String,
      subtitle: (m['subtitle'] as String?) ?? '',
      category: ReminderCategory.values.firstWhere(
        (c) => c.name == m['category'],
        orElse: () => ReminderCategory.custom,
      ),
      priority: ReminderPriority.values.firstWhere(
        (p) => p.name == m['priority'],
        orElse: () => ReminderPriority.normal,
      ),
      date: DateTime.parse(m['due_date'] as String),
      completed: (m['completed'] as bool?) ?? false,
      completedLabel:
          completedAt == null ? null : reminderRelativeLabel(completedAt),
    );
  }

  /// Columns the app owns on insert; the DB fills id / auth_user_id / timestamps.
  Map<String, dynamic> toInsert() => {
        'title': title,
        'subtitle': subtitle,
        'category': category.name,
        'priority': priority.name,
        'due_date': _reminderDateOnly(date),
        'completed': completed,
      };
}

/// Formats a [DateTime] as a DATE-only string (YYYY-MM-DD) for the DB.
String _reminderDateOnly(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// A short relative label like "Just now", "2h ago", "3 days ago".
String reminderRelativeLabel(DateTime t) {
  final diff = DateTime.now().difference(t);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays == 1) return 'Yesterday';
  return '${diff.inDays} days ago';
}

/// The colour that communicates a reminder's *time urgency* (independent of its
/// priority accent): red when overdue/today, orange tomorrow, green this week,
/// blue for anything further out. Used by the due badge and complete control.
Color reminderUrgencyColor(Reminder r, DateTime today) {
  final d = r.daysFrom(today);
  if (d <= 0) return AppColors.critical; // overdue or due today
  if (d == 1) return AppColors.warning; // due tomorrow
  if (d <= 7) return AppColors.primaryGreen; // this week
  return AppColors.lightBlue; // later
}

// ---------------------------------------------------------------------------
// Filters
// ---------------------------------------------------------------------------

/// The curated set of top-level filters shown on the Reminders screens. Kept
/// deliberately short (six chips) — "Family" groups birthdays + anniversaries;
/// investments/custom items surface only under "All".
enum ReminderFilterKind { all, documents, insurance, health, property, family }

extension ReminderFilterKindX on ReminderFilterKind {
  String get label {
    switch (this) {
      case ReminderFilterKind.all:
        return 'All';
      case ReminderFilterKind.documents:
        return 'Documents';
      case ReminderFilterKind.insurance:
        return 'Insurance';
      case ReminderFilterKind.health:
        return 'Health';
      case ReminderFilterKind.property:
        return 'Property';
      case ReminderFilterKind.family:
        return 'Family';
    }
  }

  /// Localized [label].
  String localizedLabel(AppLocalizations l10n) {
    switch (this) {
      case ReminderFilterKind.all:
        return l10n.t('all');
      case ReminderFilterKind.documents:
        return l10n.t('documents');
      case ReminderFilterKind.insurance:
        return l10n.t('insurance');
      case ReminderFilterKind.health:
        return l10n.t('health');
      case ReminderFilterKind.property:
        return l10n.t('property');
      case ReminderFilterKind.family:
        return l10n.t('family');
    }
  }

  IconData get icon {
    switch (this) {
      case ReminderFilterKind.all:
        return Icons.apps_rounded;
      case ReminderFilterKind.documents:
        return Icons.description_rounded;
      case ReminderFilterKind.insurance:
        return Icons.shield_rounded;
      case ReminderFilterKind.health:
        return Icons.favorite_rounded;
      case ReminderFilterKind.property:
        return Icons.home_work_rounded;
      case ReminderFilterKind.family:
        return Icons.people_alt_rounded;
    }
  }

  bool matches(Reminder r) {
    switch (this) {
      case ReminderFilterKind.all:
        return true;
      case ReminderFilterKind.documents:
        return r.category == ReminderCategory.documents;
      case ReminderFilterKind.insurance:
        return r.category == ReminderCategory.insurance;
      case ReminderFilterKind.health:
        return r.category == ReminderCategory.health;
      case ReminderFilterKind.property:
        return r.category == ReminderCategory.property;
      case ReminderFilterKind.family:
        return r.category == ReminderCategory.birthdays ||
            r.category == ReminderCategory.anniversaries;
    }
  }
}

// ---------------------------------------------------------------------------
// Time grouping
// ---------------------------------------------------------------------------

/// A labelled bucket of reminders for the grouped All-Reminders list. [labelKey]
/// is an [AppLocalizations] key (e.g. `overdue`, `today`) resolved at render.
class ReminderGroup {
  const ReminderGroup(this.labelKey, this.items);
  final String labelKey;
  final List<Reminder> items;
}

/// Splits reminders into ordered, non-empty time buckets relative to [today].
/// Assumes [reminders] is already sorted ascending by date.
List<ReminderGroup> groupRemindersByTime(
    List<Reminder> reminders, DateTime today) {
  final overdue = <Reminder>[];
  final todayItems = <Reminder>[];
  final tomorrow = <Reminder>[];
  final thisWeek = <Reminder>[];
  final later = <Reminder>[];
  for (final r in reminders) {
    final d = r.daysFrom(today);
    if (d < 0) {
      overdue.add(r);
    } else if (d == 0) {
      todayItems.add(r);
    } else if (d == 1) {
      tomorrow.add(r);
    } else if (d <= 7) {
      thisWeek.add(r);
    } else {
      later.add(r);
    }
  }
  return [
    if (overdue.isNotEmpty) ReminderGroup('overdue', overdue),
    if (todayItems.isNotEmpty) ReminderGroup('today', todayItems),
    if (tomorrow.isNotEmpty) ReminderGroup('tomorrow', tomorrow),
    if (thisWeek.isNotEmpty) ReminderGroup('thisWeek', thisWeek),
    if (later.isNotEmpty) ReminderGroup('later', later),
  ];
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
