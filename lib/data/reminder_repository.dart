import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/reminder_models.dart';

/// Source of Reminders data — the `public.reminders` table in Supabase.
///
/// The screens/store depend only on this abstraction, so it stays the single
/// place that talks to the reminders table (same pattern as DocumentRepository).
abstract class ReminderRepository {
  /// Loads all of the signed-in user's reminders (active + completed).
  Future<ReminderData> load();

  /// Inserts a new reminder and returns it with its real DB id.
  Future<Reminder> add(Reminder reminder);

  /// Marks a reminder complete / active.
  Future<void> setCompleted(String id, bool completed);

  /// Permanently deletes a reminder.
  Future<void> remove(String id);

  static ReminderRepository instance = SupabaseReminderRepository();
}

class SupabaseReminderRepository implements ReminderRepository {
  SupabaseClient get _client => Supabase.instance.client;

  static const String _table = 'reminders';

  @override
  Future<ReminderData> load() async {
    final today = dateOnly(DateTime.now());

    List<Reminder> all;
    try {
      final rows = await _client.from(_table).select().order('due_date');
      all = [for (final r in rows) Reminder.fromMap(r)];
      debugPrint('Reminders loaded from Supabase: ${all.length}');
    } catch (e) {
      // Offline / not signed in → start empty (screens show the placeholder).
      debugPrint('Reminders load failed: $e');
      all = const [];
    }

    final active = all.where((r) => !r.completed).toList();
    final completed = all.where((r) => r.completed).toList();

    int days(Reminder r) => r.daysFrom(today);

    return ReminderData(
      today: today,
      reminders: active,
      completed: completed,
      summary: ReminderSummary(
        dueToday: active.where((r) => days(r) == 0).length,
        upcomingThisWeek:
            active.where((r) => days(r) >= 0 && days(r) <= 7).length,
        expiringSoon: active
            .where((r) =>
                r.category.isExpiryKind && days(r) >= 0 && days(r) <= 30)
            .length,
        completedThisMonth: completed.length,
      ),
    );
  }

  @override
  Future<Reminder> add(Reminder reminder) async {
    final row = await _client
        .from(_table)
        .insert(reminder.toInsert())
        .select()
        .single();
    return Reminder.fromMap(row);
  }

  @override
  Future<void> setCompleted(String id, bool completed) async {
    await _client.from(_table).update({
      'completed': completed,
      'completed_at': completed ? DateTime.now().toIso8601String() : null,
    }).eq('id', id);
  }

  @override
  Future<void> remove(String id) async {
    await _client.from(_table).delete().eq('id', id);
  }
}
