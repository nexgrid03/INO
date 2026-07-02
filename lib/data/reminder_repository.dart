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

    // No seeded/dummy reminders — start empty so the user only ever sees
    // reminders they create themselves. The screens fall back to their
    // empty-state placeholder ("No reminders yet") until then.
    return ReminderData(
      today: today,
      reminders: const [],
      completed: const [],
      summary: const ReminderSummary(
        dueToday: 0,
        upcomingThisWeek: 0,
        expiringSoon: 0,
        completedThisMonth: 0,
      ),
    );
  }
}
