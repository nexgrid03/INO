import 'dart:developer' as developer;

import '../data/reminder_store.dart';
import '../repositories/document_repository.dart';
import 'app_settings.dart';
import 'category_store.dart';
import 'document_protection_store.dart';
import 'expense_store.dart';
import 'global_search_service.dart';
import 'notes_store.dart';
import 'notification_center.dart';
import 'voice_greeting_service.dart';

/// Clears every piece of **user-scoped in-memory / local state** so that when
/// one account signs out and another signs in on the same device, the new
/// account never sees the previous account's data.
///
/// This is the client-side half of data isolation. The server-side half is Row
/// Level Security (see `supabase/migrations/20260710000000_user_data_isolation.sql`):
/// RLS scopes what the database returns; [SessionReset] scopes what the app has
/// already cached in process-wide singletons and `shared_preferences`.
///
/// Why this is required: the app holds several `static final … instance`
/// singletons ([ReminderStore], [NotificationCenter], [CategoryStore],
/// [DocumentProtectionStore], …). The Dart process does NOT restart on sign-out,
/// so those singletons — and their `_loaded` guards — survive an account switch.
/// Without this reset, `ReminderStore.ensureLoaded()` would no-op for the second
/// user and hand them the first user's reminders.
///
/// Call [clear] on every sign-out (wired into `AuthService.signOut`) and account
/// deletion. It is best-effort and never throws: one store failing to clear must
/// not block sign-out.
class SessionReset {
  SessionReset._();
  static final SessionReset instance = SessionReset._();

  /// Wipes all user-scoped caches. Safe to call multiple times.
  Future<void> clear() async {
    developer.log('clearing user-scoped state', name: 'session');

    // In-memory reminders (+ `_loaded` guard) — the reported leak vector.
    await _guard('reminders', () async => ReminderStore.instance.clear());

    // Derived notifications + persisted read/dismissed ids (global keys).
    await _guard('notifications', () => NotificationCenter.instance.clear());

    // User-created custom document categories (persisted global key).
    await _guard('categories', () => CategoryStore.instance.clear());

    // Per-document biometric-protection flags (persisted global key).
    await _guard('protection', () => DocumentProtectionStore.instance.clear());

    // In-memory document cache + persisted recent-search history.
    await _guard('search', () => GlobalSearchService.instance.clear());

    // Transaction Vault cache (rows live in Supabase, RLS-scoped; the next
    // account's ensureLoaded() re-hydrates its OWN records).
    await _guard('expenses', () async => ExpenseStore.instance.clear());

    // Notes Vault cache — same: drop in-memory state + re-arm the loader; the
    // next account's ensureLoaded() fetches its own RLS-scoped rows.
    await _guard('notes', () async => NotesStore.instance.clear());

    // Re-arm the spoken welcome so the next sign-in is greeted at the start of
    // ITS session — still exactly once per session.
    await _guard('greeting',
        () async => VoiceGreetingService.instance.resetForNextSession());

    // Account-scoped preferences (2FA flag, last-backup, toggles). Language is a
    // device preference and is intentionally preserved.
    await _guard('settings', () => AppSettings.instance.resetAccountScoped());

    // Nudge document listeners (storage meter, wallet counts) to re-fetch — the
    // next fetch is RLS-scoped to whoever signs in next.
    DocumentRepository.revision.value++;
  }

  Future<void> _guard(String label, Future<void> Function() body) async {
    try {
      await body();
    } catch (e) {
      developer.log('reset "$label" failed: $e', name: 'session');
    }
  }
}
