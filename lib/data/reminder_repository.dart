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

  /// The signed-in user's id, or null when signed out.
  String? get _uid => _client.auth.currentUser?.id;

  @override
  Future<ReminderData> load() async {
    final today = dateOnly(DateTime.now());

    List<Reminder> all;
    try {
      // `_uid` reads the Supabase client; resolving it inside the try keeps
      // load() from throwing when Supabase isn't initialised (e.g. in tests).
      final uid = _uid;
      if (uid == null) {
        // Not signed in → no reminders to load (screens show the placeholder).
        return _emptyData(today);
      }
      // Defense-in-depth: RLS already scopes rows to the owner, but we ALSO
      // filter by auth_user_id explicitly so a missing/misconfigured RLS policy
      // can never leak another user's reminders into this client.
      final rows = await _client
          .from(_table)
          .select()
          .eq('auth_user_id', uid)
          .order('due_date');
      all = [for (final r in rows) Reminder.fromMap(r)];
      debugPrint('Reminders loaded from Supabase: ${all.length}');
    } catch (e) {
      // Offline / not initialised / query error → start empty.
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
    final uid = _uid;
    if (uid == null) {
      throw const AuthException('You must be signed in to add a reminder.');
    }
    // Stamp the owner explicitly. The DB column also defaults to auth.uid() and
    // RLS enforces it, but setting it here guarantees ownership even if the
    // column default is ever missing — no reminder is created without an owner.
    final payload = reminder.toInsert()..['auth_user_id'] = uid;
    final row = await _client.from(_table).insert(payload).select().single();
    return Reminder.fromMap(row);
  }

  @override
  Future<void> setCompleted(String id, bool completed) async {
    final uid = _uid;
    if (uid == null) return;
    // Ownership check in the filter (belt-and-suspenders with the UPDATE RLS
    // policy): a user can only flip the status of their OWN reminder.
    await _client.from(_table).update({
      'completed': completed,
      'completed_at': completed ? DateTime.now().toIso8601String() : null,
    }).eq('id', id).eq('auth_user_id', uid);
  }

  @override
  Future<void> remove(String id) async {
    final uid = _uid;
    if (uid == null) return;
    // Ownership check in the filter: a user can only delete their OWN reminder.
    await _client.from(_table).delete().eq('id', id).eq('auth_user_id', uid);
  }

  ReminderData _emptyData(DateTime today) => ReminderData(
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
