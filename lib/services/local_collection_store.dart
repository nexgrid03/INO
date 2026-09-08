import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/net/net_guard.dart';
import '../core/net/paged_query.dart';
import '../core/perf/perf_tracer.dart';
import '../core/storage/shared_prefs_cache.dart';

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

  /// The last error that stopped a record reaching Supabase, or null when the
  /// most recent write went through.
  ///
  /// This exists because the alternative was worse than a crash: every server
  /// write here was wrapped in `catch (_)`, so a record the database REFUSED
  /// still appeared in the app, saved and correct-looking, while the wallet
  /// table stayed empty. Silence is the wrong answer for a failed save - the
  /// user has no way to find out, and neither did we.
  final ValueNotifier<String?> lastSyncError = ValueNotifier<String?>(null);

  /// Records that exist only on this device - created offline, or refused by
  /// the server. Every one of them is retried on the next load.
  int get pendingCount => items.where((i) => !isServerId(idOf(i))).length;

  bool get isLoaded => _loaded;
  bool get isLoading => _loading;
  bool get isEmpty => items.isEmpty;
  int get count => items.length;
  String? get loadedUid => _loadedUid;

  @protected
  void markUnloaded() {
    _loaded = false;
    _loading = false;
    _loadedUid = null;
  }

  @protected
  void setLoadedState({required bool loaded, required bool loading, String? uid}) {
    _loaded = loaded;
    _loading = loading;
    if (uid != null) _loadedUid = uid;
  }

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
    markUnloaded();
    await _load(_currentUid());
  }

  @protected
  Future<void> loadLocalCache(String? uid) async {
    final loaded = <T>[];
    try {
      final p = await SharedPrefsCache.instance.prefsAsync;
      final raw = p.getStringList(_keyFor(uid)) ?? const <String>[];
      // All collection JSON decoding runs in a background isolate to ensure
      // the main UI thread stays 100% free of parsing overhead.
      final maps = raw.isNotEmpty
          ? await compute(decodeJsonMapList, raw)
          : <Map<String, dynamic>>[];
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
  }

  Future<void> _load(String? uid) async {
    _loading = true;
    notifyListeners();
    await loadLocalCache(uid);

    // If local cache is empty and a server sync table exists (fresh install / reinstall),
    // await the server sync so the initial load actually hydrates the records.
    if (items.isEmpty && syncTable != null && uid != null) {
      await _syncFromServer(uid);
    }

    _loaded = true;
    _loading = false;
    _loadedUid = uid;
    notifyListeners();

    // If local cache was already present, reconcile with the server in background.
    if (items.isNotEmpty && syncTable != null && uid != null) {
      unawaited(_syncFromServer(uid));
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
          final inserted = await _sendRow(
            (payload) async => await Supabase.instance.client
                .from(table)
                .insert(payload)
                .select()
                .single()
                .timeout(NetGuard.mutation),
            {...await toRow(item), 'auth_user_id': uid},
          );
          remote.add(await fromRow(inserted));
        } catch (e) {
          // Upload failed - KEEP the local copy so the record is not lost, and
          // let the next sync try again.
          _noteSyncFailure('backfill insert', e);
          remote.add(item);
        }
      }

      items
        ..clear()
        ..addAll(remote);
      notifyListeners();
      await persist();
    } catch (e) {
      // Offline / table missing → keep the cache we already loaded. Still
      // worth naming: "the table does not exist" and "there is no network"
      // look identical from the UI, and only one of them is fixable by the
      // user waiting.
      debugPrint('[$storageKey] sync($table) failed: $e');
    }
  }

  Future<void> persist() async {
    try {
      final p = await SharedPrefsCache.instance.prefsAsync;
      final maps = [for (final i in items) encode(i)];
      final encoded = maps.isNotEmpty
          ? await compute(encodeJsonMapList, maps)
          : <String>[];
      await p.setStringList(_keyFor(_loadedUid), encoded);
    } catch (_) {
      // Best-effort; the in-memory list stays correct for this session.
    }
  }

  /// The substring between the first [open] and the next [close].
  static String? _between(String s, String open, String close) {
    final a = s.indexOf(open);
    if (a < 0) return null;
    final b = s.indexOf(close, a + open.length);
    if (b <= a) return null;
    final v = s.substring(a + open.length, b).trim();
    return v.isEmpty ? null : v;
  }

  /// The column the database says the table does not have, or null when [e] is
  /// a different kind of failure.
  ///
  /// Two shapes, because the complaint can come from either layer:
  ///   PGRST204 - Could not find the 'reminder_date' column of
  ///              'w_property_wallet' in the schema cache
  ///   42703    - column "reminder_date" of relation "..." does not exist
  @visibleForTesting
  static String? missingColumnOf(Object e) => _missingColumn(e);

  static String? _missingColumn(Object e) {
    if (e is! PostgrestException) return null;
    switch (e.code) {
      case 'PGRST204':
        return _between(e.message, "'", "'");
      case '42703':
        return _between(e.message, '"', '"');
      default:
        return null;
    }
  }

  /// Sends [payload] to the server, dropping any column the database turns out
  /// not to have and trying again.
  ///
  /// The wallet schema arrives across several migrations - the property table
  /// alone spans three (base columns, then `consent`, then `reminder_date`).
  /// With the last one unapplied, PostgREST rejects the WHOLE insert, so a
  /// partially-migrated database silently produced an empty wallet table while
  /// the app looked perfectly healthy. Saving everything the database CAN
  /// accept is strictly better than saving nothing, and the dropped column is
  /// named in the log and in [lastSyncError] so the fix is obvious rather than
  /// a hunt.
  ///
  /// Terminates: each pass removes exactly one key, and a payload cannot lose
  /// more keys than it has.
  Future<Map<String, dynamic>> _sendRow(
    Future<Map<String, dynamic>> Function(Map<String, dynamic> payload) send,
    Map<String, dynamic> payload,
  ) async {
    final working = Map<String, dynamic>.from(payload);
    final dropped = <String>[];
    while (true) {
      try {
        final row = await send(working);
        if (dropped.isEmpty) {
          lastSyncError.value = null;
        } else {
          final cols = dropped.join(', ');
          final msg = 'Saved without $cols - $syncTable is missing '
              '${dropped.length == 1 ? "that column" : "those columns"}. '
              'Apply the latest wallet migration to store it.';
          debugPrint('[$storageKey] $msg');
          lastSyncError.value = msg;
        }
        return row;
      } on PostgrestException catch (e) {
        final missing = _missingColumn(e);
        if (missing == null || !working.containsKey(missing)) rethrow;
        debugPrint('[$storageKey] $syncTable has no "$missing" column '
            '(${e.code}) - retrying without it');
        working.remove(missing);
        dropped.add(missing);
      }
    }
  }

  /// Records why a write did not reach the server, instead of discarding it.
  void _noteSyncFailure(String action, Object e) {
    final detail = e is PostgrestException
        ? [
            e.message,
            if ((e.details ?? '').toString().trim().isNotEmpty) '${e.details}',
            if ((e.hint ?? '').trim().isNotEmpty) 'Hint: ${e.hint}',
          ].join(' - ')
        : e.toString();
    final msg = 'Saved on this device only - $syncTable $action failed: $detail';
    debugPrint('[$storageKey] $msg');
    lastSyncError.value = msg;
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
      final row = await _sendRow(
        (payload) async => await Supabase.instance.client
            .from(table)
            .insert(payload)
            .select()
            .single()
            .timeout(NetGuard.mutation),
        {...await toRow(item), 'auth_user_id': uid},
      );
      final i = items.indexWhere((e) => idOf(e) == idOf(item));
      if (i != -1) {
        items[i] = await fromRow(row);
        notifyListeners();
        await persist();
      }
    } catch (e) {
      // Stays local with its `prop_17…` id; picked up by the next sync - but
      // no longer in silence, so the user can be told and the cause is in the
      // log rather than nowhere at all.
      _noteSyncFailure('insert', e);
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
      await _sendRow(
        (payload) async {
          await Supabase.instance.client
              .from(table)
              .update(payload)
              .eq('id', id)
              .eq('auth_user_id', uid)
              .timeout(NetGuard.mutation);
          return const <String, dynamic>{};
        },
        await toRow(item),
      );
    } catch (e) {
      // Local copy is already correct; the edit re-uploads on the next sync.
      _noteSyncFailure('update', e);
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
    } catch (e) {
      // The row survives on the server and would return on the next sync.
      // Accepted: a failed delete that reappears is safer than a local
      // tombstone that silently drops a record the server still has.
      _noteSyncFailure('delete', e);
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
      final p = await SharedPrefsCache.instance.prefsAsync;
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
