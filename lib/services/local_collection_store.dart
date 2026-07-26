import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Shared machinery for the wallet modules that keep a **device-local** list of
/// records: properties, investments, saved cards and vault credentials.
///
/// Why local rather than Supabase: these four modules hold either highly
/// sensitive identifiers (cards, credentials) or large, deeply-nested personal
/// records the vault has no table for yet. Keeping them on-device means nothing
/// leaves the phone. The trade-off is honest and deliberate: they do **not**
/// sync across devices, and they are removed on sign-out like every other
/// user-scoped cache (see `SessionReset`).
///
/// Storage is `shared_preferences`, keyed per signed-in user so two accounts on
/// one device never see each other's records. Every operation is defensive: a
/// missing plugin (tests) or a corrupt entry degrades to "empty", never a throw.
abstract class LocalCollectionStore<T> extends ChangeNotifier {
  LocalCollectionStore();

  /// The `shared_preferences` key prefix, e.g. `ino_properties`.
  String get storageKey;

  Map<String, dynamic> encode(T item);
  T decode(Map<String, dynamic> json);

  /// Stable identity of an item, used by [update] / [remove].
  String idOf(T item);

  final List<T> items = [];
  bool _loaded = false;
  bool _loading = false;
  String? _loadedUid;
  int _seq = 0;

  bool get isLoaded => _loaded;
  bool get isLoading => _loading;
  bool get isEmpty => items.isEmpty;
  int get count => items.length;

  String _keyFor(String? uid) => '${storageKey}_${uid ?? 'local'}';

  /// The signed-in user's id, or null (signed out / tests). Reading Supabase
  /// before it is initialised throws, so any failure means "no user".
  String? _currentUid() {
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  /// Hydrates for the current user; reloads when the account changed. Safe to
  /// call from every screen's `initState`.
  Future<void> ensureLoaded() async {
    final uid = _currentUid();
    if (_loading) return;
    if (_loaded && uid == _loadedUid) return;
    await _load(uid);
  }

  Future<void> reload() async {
    if (_loading) return;
    await _load(_currentUid());
  }

  Future<void> _load(String? uid) async {
    _loading = true;
    notifyListeners();
    final loaded = <T>[];
    try {
      final p = await SharedPreferences.getInstance();
      for (final raw in p.getStringList(_keyFor(uid)) ?? const <String>[]) {
        try {
          loaded.add(decode(jsonDecode(raw) as Map<String, dynamic>));
        } catch (_) {
          // Skip a corrupt entry rather than losing the whole collection.
        }
      }
    } catch (_) {
      // No plugin (tests) / read error → start empty, never throw.
    }
    items
      ..clear()
      ..addAll(loaded);
    _loaded = true;
    _loading = false;
    _loadedUid = uid;
    notifyListeners();
  }

  Future<void> persist() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(
        _keyFor(_loadedUid),
        [for (final i in items) jsonEncode(encode(i))],
      );
    } catch (_) {
      // Best-effort; the in-memory list stays correct for this session.
    }
  }

  /// A collision-proof local id (microsecond clock + a per-session counter).
  String newId(String prefix) =>
      '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${_seq++}';

  T? byId(String id) {
    for (final i in items) {
      if (idOf(i) == id) return i;
    }
    return null;
  }

  Future<void> add(T item) async {
    items.add(item);
    notifyListeners();
    await persist();
  }

  /// Replaces the item with the same id. No-op when it isn't there.
  Future<void> update(T item) async {
    final i = items.indexWhere((e) => idOf(e) == idOf(item));
    if (i == -1) return;
    items[i] = item;
    notifyListeners();
    await persist();
  }

  Future<void> remove(String id) async {
    final before = items.length;
    items.removeWhere((e) => idOf(e) == id);
    if (items.length == before) return;
    notifyListeners();
    await persist();
  }

  /// Drops everything for this device account and re-arms the loader. Called on
  /// sign-out so the next account starts clean.
  Future<void> clear() async {
    final key = _keyFor(_loadedUid);
    items.clear();
    _loaded = false;
    _loading = false;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(key);
    } catch (_) {
      // Best-effort.
    }
    _loadedUid = null;
  }

  /// Test hook: wipe in-memory state without touching storage.
  @visibleForTesting
  void reset() {
    items.clear();
    _loaded = false;
    _loading = false;
    _loadedUid = null;
    _seq = 0;
  }
}
