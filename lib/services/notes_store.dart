import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/note_models.dart';

/// The Notes Vault repository — a notify-on-change store for the user's personal
/// notes.
///
/// Persistence today: `shared_preferences`, keyed per signed-in user
/// (`ino_notes_<uid>`), so notes survive an app restart and each account only
/// ever sees its own. This keeps the module fully functional with no backend
/// migration. The repository shape (load / add / update / remove) is
/// deliberately Supabase-ready: swapping the storage backend later is a change
/// inside [_load] / [_persist] only — no screen touches storage directly.
///
/// Cross-session isolation: [clear] (called from `SessionReset` on sign-out)
/// drops the in-memory cache and re-arms the loader, so the next account loads
/// ITS OWN key. The persisted data itself is left intact so a user's notes come
/// back when they sign in again.
class NotesStore extends ChangeNotifier {
  NotesStore._();
  static final NotesStore instance = NotesStore._();

  final List<Note> _notes = [];
  bool _loaded = false;
  String? _loadedUid;
  int _seq = 0;

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
  /// signed-in user changes. Safe to call often.
  Future<void> ensureLoaded() async {
    final uid = _currentUid();
    if (_loaded && uid == _loadedUid) return;
    await _load(uid);
  }

  Future<void> _load(String? uid) async {
    _notes.clear();
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getStringList(_keyFor(uid)) ?? const [];
      for (final s in raw) {
        try {
          _notes.add(Note.fromJson(jsonDecode(s) as Map<String, dynamic>));
        } catch (_) {
          // Skip a corrupt entry rather than failing the whole load.
        }
      }
    } catch (_) {
      // No plugin (tests) / read error → start empty, never throw.
    }
    _loaded = true;
    _loadedUid = uid;
    notifyListeners();
  }

  Future<void> _persist() async {
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

  Future<Note> add({
    required String title,
    required String description,
    required NoteCategory category,
    List<String> tags = const [],
    bool isPinned = false,
    bool isFavorite = false,
  }) async {
    final now = DateTime.now();
    final note = Note(
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
    _notes.add(note);
    notifyListeners();
    await _persist();
    return note;
  }

  Future<void> update(Note note) async {
    final i = _notes.indexWhere((n) => n.id == note.id);
    if (i == -1) return;
    _notes[i] = note;
    notifyListeners();
    await _persist();
  }

  Future<void> remove(String id) async {
    final before = _notes.length;
    _notes.removeWhere((n) => n.id == id);
    if (_notes.length == before) return;
    notifyListeners();
    await _persist();
  }

  Future<void> togglePin(String id) => _mutate(id, (n) => n.copyWith(isPinned: !n.isPinned));

  Future<void> toggleFavorite(String id) =>
      _mutate(id, (n) => n.copyWith(isFavorite: !n.isFavorite));

  Future<void> toggleArchive(String id) =>
      _mutate(id, (n) => n.copyWith(isArchived: !n.isArchived));

  Future<void> _mutate(String id, Note Function(Note) change) async {
    final i = _notes.indexWhere((n) => n.id == id);
    if (i == -1) return;
    _notes[i] = change(_notes[i]);
    notifyListeners();
    await _persist();
  }

  /// Drops the in-memory cache and re-arms the loader so the next signed-in
  /// account loads its own notes. Persisted data is left intact (a user's notes
  /// return when they sign back in). Called from `SessionReset`.
  void clear() {
    _notes.clear();
    _loaded = false;
    _loadedUid = null;
    notifyListeners();
  }

  /// Test hook: reset all in-memory state.
  @visibleForTesting
  void reset() {
    _notes.clear();
    _loaded = false;
    _loadedUid = null;
    _seq = 0;
  }
}
