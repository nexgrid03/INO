import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/notes_repository.dart';
import '../models/note_models.dart';

/// The Notes Vault store — a notify-on-change source of truth for the user's
/// personal notes.
///
/// Persistence: the `public.notes` table in Supabase via [NotesRepository],
/// owner-scoped by RLS (see supabase/migrations/20260724000000_notes_expenses.sql).
/// When nobody is signed in (tests / signed-out browsing) it falls back to the
/// legacy `shared_preferences` storage (`ino_notes_local`), so the module keeps
/// working without a session and the existing tests stay valid.
///
/// Legacy migration: notes saved by older builds under `ino_notes_<uid>` are
/// uploaded to Supabase on the first signed-in load, then the local key is
/// removed — nobody loses the notes they already wrote.
///
/// Cross-session isolation: [clear] (called from `SessionReset` on sign-out)
/// drops the in-memory cache and re-arms the loader, so the next account loads
/// ITS OWN rows (RLS guarantees that server-side too).
class NotesStore extends ChangeNotifier {
  NotesStore._();
  static final NotesStore instance = NotesStore._();

  final List<Note> _notes = [];
  bool _loaded = false;
  bool _loading = false;
  String? _loadedUid;
  String? _loadError;
  int _seq = 0;

  /// True while the first load (or a [reload]) is in flight.
  bool get isLoading => _loading;

  /// True once a load has completed (even an empty or failed one).
  bool get isLoaded => _loaded;

  /// Human-readable message when the last load failed (offline, …), else null.
  String? get loadError => _loadError;

  static String _keyFor(String? uid) => 'ino_notes_${uid ?? 'local'}';

  /// The signed-in user's id, or null (tests / signed out). Defensive: reading
  /// Supabase before init throws, so we treat any failure as "no user".
  String? _currentUid() {
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  /// Hydrates the notes for the current user. Reloads automatically when the
  /// signed-in user changes. Safe to call often (every screen `initState`).
  Future<void> ensureLoaded() async {
    final uid = _currentUid();
    if (_loading) return;
    if (_loaded && uid == _loadedUid) return;
    await _load(uid);
  }

  /// Pull-to-refresh: re-hydrates from the backend.
  Future<void> reload() async {
    if (_loading) return;
    await _load(_currentUid());
  }

  Future<void> _load(String? uid) async {
    _loading = true;
    _loadError = null;
    notifyListeners();

    List<Note>? fetched;
    if (uid == null) {
      // Signed out / tests → local storage only.
      fetched = await _loadLocal(uid);
    } else {
      try {
        await _migrateLegacyLocal(uid);
        fetched = await NotesRepository.instance.load();
      } catch (e) {
        debugPrint('Notes load failed: $e');
        _loadError = 'Couldn\'t load your notes. Check your connection.';
        // Keep whatever is already in memory (e.g. a previous good load).
        fetched = null;
      }
    }

    if (fetched != null) {
      _notes
        ..clear()
        ..addAll(fetched);
    }
    _loaded = true;
    _loading = false;
    _loadedUid = uid;
    notifyListeners();
  }

  /// Loads notes from `shared_preferences` (signed-out / test mode).
  Future<List<Note>> _loadLocal(String? uid) async {
    final out = <Note>[];
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getStringList(_keyFor(uid)) ?? const [];
      for (final s in raw) {
        try {
          out.add(Note.fromJson(jsonDecode(s) as Map<String, dynamic>));
        } catch (_) {
          // Skip a corrupt entry rather than failing the whole load.
        }
      }
    } catch (_) {
      // No plugin (tests) / read error → start empty, never throw.
    }
    return out;
  }

  /// One-time upload of notes an older build stored on-device for [uid].
  /// Runs before the first Supabase load; on success the local key is removed
  /// so it never runs again. A failure leaves the local copy intact for the
  /// next attempt.
  Future<void> _migrateLegacyLocal(String uid) async {
    List<String> raw;
    SharedPreferences p;
    try {
      p = await SharedPreferences.getInstance();
      raw = p.getStringList(_keyFor(uid)) ?? const [];
    } catch (_) {
      return; // No plugin (tests) → nothing to migrate.
    }
    if (raw.isEmpty) return;
    debugPrint('Notes: migrating ${raw.length} legacy local note(s) to Supabase');
    for (final s in raw) {
      try {
        final note = Note.fromJson(jsonDecode(s) as Map<String, dynamic>);
        await NotesRepository.instance.add(note);
      } catch (e) {
        // A malformed entry is dropped; a network failure aborts the migration
        // (rethrown) so the local copy is preserved for the next attempt.
        if (e is FormatException || e is TypeError) continue;
        rethrow;
      }
    }
    await p.remove(_keyFor(uid));
    debugPrint('Notes: legacy local notes migrated');
  }

  Future<void> _persistLocal() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(
        _keyFor(_loadedUid),
        [for (final n in _notes) jsonEncode(n.toJson())],
      );
    } catch (_) {
      // Best-effort; the in-memory list stays correct for this session.
    }
  }

  bool get _remote => _loadedUid != null;

  int _cmp(Note a, Note b) {
    if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
    return b.updatedAt.compareTo(a.updatedAt);
  }

  /// All non-archived notes, pinned first, then most recently updated.
  List<Note> get active {
    final list = _notes.where((n) => !n.isArchived).toList()..sort(_cmp);
    return List.unmodifiable(list);
  }

  /// Archived notes, most recently updated first.
  List<Note> get archived {
    final list = _notes.where((n) => n.isArchived).toList()..sort(_cmp);
    return List.unmodifiable(list);
  }

  bool get isEmpty => _notes.isEmpty;
  int get totalCount => _notes.length;
  int get activeCount => _notes.where((n) => !n.isArchived).length;

  Note? byId(String id) {
    for (final n in _notes) {
      if (n.id == id) return n;
    }
    return null;
  }

  String _newId() =>
      'note_${DateTime.now().microsecondsSinceEpoch}_${_seq++}';

  /// Creates a note. When signed in this awaits the Supabase insert (so the
  /// caller can show a saving spinner and a failure surfaces as a thrown
  /// error); the returned note carries its real DB id.
  Future<Note> add({
    required String title,
    required String description,
    required NoteCategory category,
    List<String> tags = const [],
    bool isPinned = false,
    bool isFavorite = false,
  }) async {
    final now = DateTime.now();
    var note = Note(
      id: _newId(),
      title: title.trim(),
      description: description.trim(),
      category: category,
      createdAt: now,
      updatedAt: now,
      tags: tags,
      isPinned: isPinned,
      isFavorite: isFavorite,
    );
    if (_remote) {
      note = await NotesRepository.instance.add(note); // real DB id
    }
    _notes.add(note);
    notifyListeners();
    if (!_remote) await _persistLocal();
    return note;
  }

  /// Saves an edited note. Optimistic: the UI updates immediately; a backend
  /// failure rolls the note back and rethrows so the caller can show an error.
  Future<void> update(Note note) async {
    final i = _notes.indexWhere((n) => n.id == note.id);
    if (i == -1) return;
    final previous = _notes[i];
    _notes[i] = note;
    notifyListeners();
    if (!_remote) {
      await _persistLocal();
      return;
    }
    try {
      await NotesRepository.instance.update(note);
    } catch (e) {
      debugPrint('Note update failed: $e');
      final j = _notes.indexWhere((n) => n.id == note.id);
      if (j != -1) _notes[j] = previous;
      notifyListeners();
      rethrow;
    }
  }

  /// Deletes a note. Optimistic, with rollback + rethrow on backend failure.
  Future<void> remove(String id) async {
    final i = _notes.indexWhere((n) => n.id == id);
    if (i == -1) return;
    final removed = _notes.removeAt(i);
    notifyListeners();
    if (!_remote) {
      await _persistLocal();
      return;
    }
    try {
      await NotesRepository.instance.remove(id);
    } catch (e) {
      debugPrint('Note delete failed: $e');
      _notes.insert(i.clamp(0, _notes.length), removed);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> togglePin(String id) =>
      _mutate(id, (n) => n.copyWith(isPinned: !n.isPinned));

  Future<void> toggleFavorite(String id) =>
      _mutate(id, (n) => n.copyWith(isFavorite: !n.isFavorite));

  Future<void> toggleArchive(String id) =>
      _mutate(id, (n) => n.copyWith(isArchived: !n.isArchived));

  Future<void> _mutate(String id, Note Function(Note) change) async {
    final i = _notes.indexWhere((n) => n.id == id);
    if (i == -1) return;
    final previous = _notes[i];
    _notes[i] = change(previous);
    notifyListeners();
    if (!_remote) {
      await _persistLocal();
      return;
    }
    try {
      await NotesRepository.instance.update(_notes[i]);
    } catch (e) {
      // Toggles are quick actions — roll back quietly, no throw.
      debugPrint('Note update failed: $e');
      final j = _notes.indexWhere((n) => n.id == id);
      if (j != -1) _notes[j] = previous;
      notifyListeners();
    }
  }

  /// Drops the in-memory cache and re-arms the loader so the next signed-in
  /// account loads its own notes (RLS scopes the fetch server-side). Called
  /// from `SessionReset` on sign-out.
  void clear() {
    _notes.clear();
    _loaded = false;
    _loading = false;
    _loadedUid = null;
    _loadError = null;
    notifyListeners();
  }

  /// Test hook: reset all in-memory state.
  @visibleForTesting
  void reset() {
    _notes.clear();
    _loaded = false;
    _loading = false;
    _loadedUid = null;
    _loadError = null;
    _seq = 0;
  }
}
