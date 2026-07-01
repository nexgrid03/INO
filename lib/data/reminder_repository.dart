import '../models/reminder_models.dart';

/// Source of Reminders Dashboard data. The screen depends only on this
/// abstraction, so the sample data can be swapped for Supabase (a `reminders`
/// table with RLS) without touching any widget.
abstract class ReminderRepository {
  Future<ReminderData> load();

  static ReminderRepository instance = SampleReminderRepository();
}

class SampleReminderRepository implements ReminderRepository {
  @override
  Future<ReminderData> load() async {
    await Future<void>.delayed(const Duration(milliseconds: 260));

    final today = dateOnly(DateTime.now());
    Reminder r(
      String id,
      String title,
      String subtitle,
      ReminderCategory category,
      ReminderPriority priority,
      int dayOffset,
    ) =>
        Reminder(
          id: id,
          title: title,
          subtitle: subtitle,
          category: category,
          priority: priority,
          date: today.add(Duration(days: dayOffset)),
        );

    final reminders = <Reminder>[
      r('r1', 'Passport Renewal', 'Expires soon — renew now',
          ReminderCategory.documents, ReminderPriority.critical, 0),
      r('r2', 'Insurance Premium', 'Health cover — ₹12,400 due',
          ReminderCategory.insurance, ReminderPriority.important, 1),
      r('r3', 'Medical Checkup', 'Annual full-body checkup',
          ReminderCategory.health, ReminderPriority.normal, 5),
      r('r4', 'Birthday · Dad', 'Turns 62 — plan something special',
          ReminderCategory.birthdays, ReminderPriority.normal, 3),
      r('r5', 'Anniversary · Parents', '35th wedding anniversary',
          ReminderCategory.anniversaries, ReminderPriority.normal, 9),
      r('r6', 'Property Tax Due', 'Municipal tax — 2nd installment',
          ReminderCategory.property, ReminderPriority.important, 12),
      r('r7', 'Insurance Renewal', 'Car insurance renewal',
          ReminderCategory.insurance, ReminderPriority.important, 16),
      r('r8', 'Passport Expiry', 'Family passports expiring',
          ReminderCategory.documents, ReminderPriority.critical, 21),
      r('r9', 'PAN Update', 'Link PAN with latest KYC',
          ReminderCategory.documents, ReminderPriority.normal, 24),
      r('r10', 'Driving License Renewal', 'License renewal at RTO',
          ReminderCategory.documents, ReminderPriority.important, 28),
      r('r11', 'SIP Review', 'Rebalance mutual fund portfolio',
          ReminderCategory.investments, ReminderPriority.normal, 34),
    ];
    reminders.sort((a, b) => a.date.compareTo(b.date));

    final completed = <Reminder>[
      Reminder(
        id: 'c1',
        title: 'Insurance Premium Paid',
        subtitle: 'Life cover premium',
        category: ReminderCategory.insurance,
        priority: ReminderPriority.important,
        date: today.subtract(const Duration(days: 2)),
        completed: true,
        completedLabel: '2 days ago',
      ),
      Reminder(
        id: 'c2',
        title: 'Passport Renewed',
        subtitle: 'Collected new passport',
        category: ReminderCategory.documents,
        priority: ReminderPriority.critical,
        date: today.subtract(const Duration(days: 6)),
        completed: true,
        completedLabel: 'Last week',
      ),
      Reminder(
        id: 'c3',
        title: 'Health Checkup Completed',
        subtitle: 'Reports uploaded to Health Wallet',
        category: ReminderCategory.health,
        priority: ReminderPriority.normal,
        date: today.subtract(const Duration(days: 11)),
        completed: true,
        completedLabel: '11 days ago',
      ),
    ];

    final dueToday = reminders.where((x) => x.daysFrom(today) == 0).length;
    final thisWeek = reminders
        .where((x) => x.daysFrom(today) >= 0 && x.daysFrom(today) <= 7)
        .length;
    final expiring = reminders
        .where((x) =>
            x.category.isExpiryKind &&
            x.daysFrom(today) >= 0 &&
            x.daysFrom(today) <= 30)
        .length;

    return ReminderData(
      today: today,
      reminders: reminders,
      completed: completed,
      summary: ReminderSummary(
        dueToday: dueToday,
        upcomingThisWeek: thisWeek,
        expiringSoon: expiring,
        completedThisMonth: completed.length,
      ),
    );
  }
}
