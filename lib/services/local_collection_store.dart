import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/net/net_guard.dart';
import '../core/net/paged_query.dart';
import '../core/perf/perf_tracer.dart';

/// Parses a list of JSON strings into maps, skipping corrupt entries. Top-level
/// so [compute] can run it in a background isolate for big collections - the
/// main isolate no longer pays the parse cost (which caused frame drops and,
/// under stress tests, ANRs as collections grew).
List<Map<String, dynamic>> decodeJsonMapList(List<String> raw) {
  final out = <Map<String, dynamic>>[];
  for (final s in raw) {
    try {
      final m = jsonDecode(s);
      if (m is Map<String, dynamic>) out.add(m);
    } catch (_) {
      // Skip a corrupt entry rather than losing the whole collection.
    }
  }
  return out;
}

/// Serialises maps back to one JSON string per record (same shape
/// `shared_preferences` stored before). Top-level for [compute].
List<String> encodeJsonMapList(List<Map<String, dynamic>> maps) =>
    [for (final m in maps) jsonEncode(m)];

/// Shared machinery for the wallet modules that keep a list of records:
/// properties, investments, saved cards and vault credentials.
///
/// **Storage model.** `shared_preferences` is always the local cache, keyed per
/// signed-in user so two accounts on one device never see each other's records.
/// A store that also sets [syncTable] is additionally backed by its Supabase
/// wallet table (`w_property_wallet`, …), which then becomes the source of
/// truth: records survive a reinstall and follow the user across devices.
///
/// A store that leaves [syncTable] null stays device-local exactly as before -
/// which is what the Password Vault does, because its `secret` column must hold
/// a client-side-encrypted value and the app has no key-derivation scheme yet.
/// Uploading plaintext credentials would violate the invariant stated on
/// `w_password_vault.secret` itself.
///
/// **Sync shape.** Deliberately last-write-wins per record rather than a real
/// CRDT: these are single-user records edited on one device at a time, and the
/// failure mode of a merge conflict (a silently resurrected old value) is worse
/// than the failure mode of last-write-wins (the newer edit stands).
///
/// Every operation is defensive: a missing plugin (tests), no network, or a
/// corrupt entry degrades to "local only", never a throw. A sync failure must
/// never cost the user a record they just typed.
abstract class LocalCollectionStore<T> extends ChangeNotifier {
  LocalCollectionStore();

  /// The `shared_preferences` key prefix, e.g. `ino_properties`.
  String get storageKey;

  Map<String, dynamic> encode(T item);
  T decode(Map<String, dynamic> json);

  /// Stable identity of an item, used by [update] / [remove].
  String idOf(T item);

  // ---- Optional Supabase sync ----------------------------------------------
  //
  // A subclass opts in by overriding all four. The default is null/unsupported,
  // which keeps the store device-local and byte-for-byte as it behaved before.

  /// The wallet table backing this store, e.g. `w_property_wallet`.
  /// Null (the default) means device-local only - no row ever leaves the phone.
  String? get syncTable => null;

  /// The record's Postgres columns. MUST NOT include `id` or `auth_user_id` -
  /// those are owned by the database and set by this class.
  ///
  /// Async because the Password Vault seals its secret here, and encryption
  /// cannot be done synchronously. Stores with nothing to encrypt just return
  /// a literal map.
  Future<Map<String, dynamic>> toRow(T item) async => throw UnimplementedError(
      '$runtimeType sets syncTable but does not implement toRow');

  /// Rebuilds a record from a table row (including its `id`).
  Future<T> fromRow(Map<String, dynamic> row) async => throw UnimplementedError(
      '$runtimeType sets syncTable but does not implement fromRow');

  /// A copy of [item] carrying [id]. Used to adopt the database's generated
  /// uuid when a device-local record is uploaded for the first time.
  T withId(T item, String id) => throw UnimplementedError(
      '$runtimeType sets syncTable but does not implement withId');

  /// Whether [id] came from Postgres (a uuid) rather than [newId] (`prop_17…`).
  ///
  /// This is how a record that has never reached the server is recognised, and
  /// therefore what makes the one-time migration of pre-existing device records
  /// work without a separate "synced" flag on every model.
  static bool isServerId(String id) => _uuidRe.hasMatch(id);

  static final RegExp _uuidRe = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

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
  Future<void> ensureLoaded() =>
      PerfTracer.traceQuery('LocalCollectionStore($storageKey).ensureLoaded', () async {
        final uid = _currentUid();
        if (_loading) return;
        if (_loaded && uid == _loadedUid) return;
        await _load(uid);
      });

  Future<void> reload() async {
    if (_loading) return;
    await _load(_currentUid());
  }

  /// Below this many records the isolate-spawn overhead of [compute] costs
  /// more than the JSON work it saves; above it, parsing off the main isolate
  /// keeps the UI thread free.
  static const int _computeThreshold = 50;

  Future<void> _load(String? uid) async {
    _loading = true;
    notifyListeners();
    final loaded = <T>[];
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getStringList(_keyFor(uid)) ?? const <String>[];
      // Big collections parse in a background isolate so hydration never
      // janks the first frame; tiny ones parse inline (cheaper than an
      // isolate round-trip).
      final maps = raw.length > _computeThreshold
          ? await compute(decodeJsonMapList, raw)
          : decodeJsonMapList(raw);
      for (final m in maps) {
        try {
          loaded.add(decode(m));
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

    // Paint from the local cache first (above), then reconcile with the server.
    // Ordering matters: hydrating from cache synchronously means the wallet
    // renders its real contents on the first frame instead of an empty state
    // that fills in a second later.
    if (syncTable != null && uid != null) {
      await _syncFromServer(uid);
    }
  }

  /// Pulls the user's rows, uploads any device-local record that has never been
  /// synced, and leaves the server as the source of truth.
  ///
  /// Never throws: offline or mid-migration, the local cache already loaded
  /// above stays in place and the next [ensureLoaded] retries.
  Future<void> _syncFromServer(String uid) async {
    final table = syncTable!;
    try {
      // Paged rather than capped, and explicitly ordered by id: `.range()` over
      // an unordered query returns arbitrary windows, so the sort is what makes
      // paging correct here, not just tidy.
      final rows = await fetchAllPaged(
        (from, to) => Supabase.instance.client
            .from(table)
            .select()
            .eq('auth_user_id', uid)
            .order('id')
            .range(from, to)
            .timeout(NetGuard.query),
        label: 'sync($table)',
      );

      final remote = <T>[];
      for (final row in rows) {
        try {
          remote.add(await fromRow(row));
        } catch (_) {
          // One unreadable row must not sink the whole wallet.
        }
      }

      // One-time migration: anything created before this store synced (or while
      // offline) still carries a local `prop_17…` id, so it exists nowhere but
      // this phone. Push those up and adopt the uuid the database assigns.
      final pending = [for (final i in items) if (!isServerId(idOf(i))) i];
      for (final item in pending) {
        try {
          final inserted = await Supabase.instance.client
              .from(table)
              .insert({...await toRow(item), 'auth_user_id': uid})
              .select()
              .single()
              .timeout(NetGuard.mutation);
          remote.add(await fromRow(inserted));
        } catch (_) {
          // Upload failed - KEEP the local copy so the record is not lost, and
          // let the next sync try again.
          remote.add(item);
        }
      }

      items
        ..clear()
        ..addAll(remote);
      notifyListeners();
      await persist();
    } catch (_) {
      // Offline / table missing → keep the cache we already loaded.
    }
  }

  Future<void> persist() async {
    try {
      final p = await SharedPreferences.getInstance();
      // Domain encode (cheap map building) stays here; the JSON string
      // serialisation - the expensive part for big collections - runs in a
      // background isolate past the same threshold as loading.
      final maps = [for (final i in items) encode(i)];
      final encoded = maps.length > _computeThreshold
          ? await compute(encodeJsonMapList, maps)
          : encodeJsonMapList(maps);
      await p.setStringList(_keyFor(_loadedUid), encoded);
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

    // Write through, then swap the optimistic copy for the stored row so the
    // item carries its server uuid from here on. Failure is not surfaced: the
    // record is already saved locally and _syncFromServer uploads it later.
    final table = syncTable;
    final uid = _loadedUid;
    if (table == null || uid == null) return;
    try {
      final row = await Supabase.instance.client
          .from(table)
          .insert({...await toRow(item), 'auth_user_id': uid})
          .select()
          .single()
          .timeout(NetGuard.mutation);
      final i = items.indexWhere((e) => idOf(e) == idOf(item));
      if (i != -1) {
        items[i] = await fromRow(row);
        notifyListeners();
        await persist();
      }
    } catch (_) {
      // Stays local with its `prop_17…` id; picked up by the next sync.
    }
  }

  /// Replaces the item with the same id. No-op when it isn't there.
  Future<void> update(T item) async {
    final i = items.indexWhere((e) => idOf(e) == idOf(item));
    if (i == -1) return;
    items[i] = item;
    notifyListeners();
    await persist();

    final table = syncTable;
    final uid = _loadedUid;
    final id = idOf(item);
    // A record with a local id has never been uploaded, so there is no row to
    // update - the next sync inserts it whole.
    if (table == null || uid == null || !isServerId(id)) return;
    try {
      await Supabase.instance.client
          .from(table)
          .update(await toRow(item))
          .eq('id', id)
          .eq('auth_user_id', uid)
          .timeout(NetGuard.mutation);
    } catch (_) {
      // Local copy is already correct; the edit re-uploads on the next sync.
    }
  }

  Future<void> remove(String id) async {
    final before = items.length;
    items.removeWhere((e) => idOf(e) == id);
    if (items.length == before) return;
    notifyListeners();
    await persist();

    final table = syncTable;
    final uid = _loadedUid;
    if (table == null || uid == null || !isServerId(id)) return;
    try {
      await Supabase.instance.client
          .from(table)
          .delete()
          .eq('id', id)
          .eq('auth_user_id', uid)
          .timeout(NetGuard.mutation);
    } catch (_) {
      // The row survives on the server and would return on the next sync.
      // Accepted: a failed delete that reappears is safer than a local
      // tombstone that silently drops a record the server still has.
    }
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
