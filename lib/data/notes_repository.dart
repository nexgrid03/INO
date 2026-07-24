import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/note_models.dart';

/// Source of Notes Vault data — the `public.notes` table in Supabase.
///
/// The store/screens depend only on this abstraction, so it stays the single
/// place that talks to the notes table (same pattern as ReminderRepository /
/// DocumentRepository). RLS scopes rows to the owner server-side; every query
/// here ALSO filters by `auth_user_id` as defense-in-depth.
abstract class NotesRepository {
  /// Loads all of the signed-in user's notes (active + archived).
  Future<List<Note>> load();

  /// Inserts a new note and returns it with its real DB id.
  Future<Note> add(Note note);

  /// Updates an existing note (matched by id, owner-scoped).
  Future<void> update(Note note);

  /// Permanently deletes a note.
  Future<void> remove(String id);

  static NotesRepository instance = SupabaseNotesRepository();
}

class SupabaseNotesRepository implements NotesRepository {
  SupabaseClient get _client => Supabase.instance.client;

  static const String _table = 'notes';

  /// The signed-in user's id, or null when signed out.
  String? get _uid => _client.auth.currentUser?.id;

  @override
  Future<List<Note>> load() async {
    // `_uid` reads the Supabase client; resolving it inside the caller's
    // try/catch keeps load() from throwing when Supabase isn't initialised
    // (e.g. in tests) — here we throw so the store can show an error state.
    final uid = _uid;
    if (uid == null) return const [];
    final rows = await _client
        .from(_table)
        .select()
        .eq('auth_user_id', uid)
        .order('updated_at', ascending: false);
    final notes = [for (final r in rows) Note.fromRow(r)];
    debugPrint('Notes loaded from Supabase: ${notes.length}');
    return notes;
  }

  @override
  Future<Note> add(Note note) async {
    final uid = _uid;
    if (uid == null) {
      throw const AuthException('You must be signed in to save a note.');
    }
    // Stamp the owner explicitly. The DB column also defaults to auth.uid()
    // and RLS enforces it, but setting it here guarantees ownership even if
    // the column default is ever missing.
    final payload = note.toInsert()..['auth_user_id'] = uid;
    final row = await _client.from(_table).insert(payload).select().single();
    return Note.fromRow(row);
  }

  @override
  Future<void> update(Note note) async {
    final uid = _uid;
    if (uid == null) {
      throw const AuthException('You must be signed in to update a note.');
    }
    // Ownership check in the filter (belt-and-suspenders with the UPDATE RLS
    // policy): a user can only edit their OWN note.
    await _client
        .from(_table)
        .update(note.toInsert())
        .eq('id', note.id)
        .eq('auth_user_id', uid);
  }

  @override
  Future<void> remove(String id) async {
    final uid = _uid;
    if (uid == null) {
      throw const AuthException('You must be signed in to delete a note.');
    }
    // Ownership check in the filter: a user can only delete their OWN note.
    await _client.from(_table).delete().eq('id', id).eq('auth_user_id', uid);
  }
}
