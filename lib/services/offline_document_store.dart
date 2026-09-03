import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/storage/shared_prefs_cache.dart';
import 'document_file_service.dart';

/// One document saved for offline viewing.
class OfflineDoc {
  const OfflineDoc({
    required this.id,
    required this.name,
    required this.wallet,
    required this.relPath,
    required this.localPath,
    required this.objectPath,
    required this.sizeBytes,
    required this.savedAt,
    this.category,
  });

  /// The document row's id - how the viewer knows "this one is saved".
  final String id;
  final String name;
  final String wallet;
  final String? category;

  /// Where the copy lives *relative to the app documents directory* -
  /// `offline_docs/<uid>/<file>`.
  ///
  /// This, not [localPath], is the durable identity of the file. The app's
  /// documents container is re-created at a brand-new path on every iOS
  /// update (the UUID in `/var/mobile/Containers/Data/Application/<UUID>/`
  /// changes), so an absolute path written last week is dead today - and an
  /// entry whose file "does not exist" is dropped on load, which is exactly
  /// how a full offline library silently emptied itself. A relative path is
  /// re-resolved against the *current* container on every launch and stays
  /// valid for the life of the install.
  final String relPath;

  /// [relPath] resolved against the documents directory of THIS run - the
  /// absolute path the viewer actually opens. Always recomputed on load;
  /// never trusted as read from storage.
  final String localPath;

  /// The Storage object it came from (kept for re-download / diagnostics).
  final String objectPath;
  final int sizeBytes;
  final DateTime savedAt;

  String get extension => DocumentFileService.extensionOf(objectPath);

  bool get isImage =>
      const {'jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'heic'}
          .contains(extension);

  /// "2.4 MB" - what the list row shows.
  String get sizeLabel {
    if (sizeBytes >= 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (sizeBytes >= 1024) return '${(sizeBytes / 1024).round()} KB';
    return '$sizeBytes B';
  }

  /// The same entry with [localPath] rebuilt from [baseDir].
  OfflineDoc resolvedIn(String baseDir) => OfflineDoc(
        id: id,
        name: name,
        wallet: wallet,
        category: category,
        relPath: relPath,
        localPath: relPath.isEmpty ? localPath : '$baseDir/$relPath',
        objectPath: objectPath,
        sizeBytes: sizeBytes,
        savedAt: savedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'wallet': wallet,
        'category': category,
        'relPath': relPath,
        // Kept for diagnostics (and so an older build reading this same key
        // still finds its file). Loading always prefers `relPath`.
        'localPath': localPath,
        'objectPath': objectPath,
        'sizeBytes': sizeBytes,
        'savedAt': savedAt.toIso8601String(),
      };

  factory OfflineDoc.fromJson(Map<String, dynamic> j) {
    final abs = _slashes((j['localPath'] as String?) ?? '');
    final rel = _slashes((j['relPath'] as String?) ?? '');
    return OfflineDoc(
      id: j['id']?.toString() ?? '',
      name: (j['name'] as String?) ?? 'Document',
      wallet: (j['wallet'] as String?) ?? '',
      category: j['category'] as String?,
      relPath: rel.isNotEmpty ? rel : _relFromAbsolute(abs),
      localPath: abs,
      objectPath: (j['objectPath'] as String?) ?? '',
      sizeBytes: (j['sizeBytes'] as num?)?.toInt() ?? 0,
      savedAt:
          DateTime.tryParse(j['savedAt'] as String? ?? '') ?? DateTime.now(),
    );
  }

  /// Recovers the relative tail of a legacy absolute path, so entries written
  /// before [relPath] existed are migrated instead of thrown away.
  static String _relFromAbsolute(String abs) {
    const marker = '/${OfflineDocumentStore.dirName}/';
    final at = abs.lastIndexOf(marker);
    return at < 0 ? '' : abs.substring(at + 1);
  }

  /// Windows-style separators normalised, so `relPath` matching works the same
  /// on every platform the app builds for.
  static String _slashes(String p) => p.replaceAll(r'\', '/');
}

/// Documents saved for offline viewing.
///
/// **Why this exists.** [DocumentFileService] caches viewed files, but in the
/// TEMP directory - the OS is free to purge it, and a purged cache means a
/// re-download that needs internet. This store copies a document into the app's
/// **documents directory**, which survives until the user (or an uninstall)
/// removes it, and remembers the copy per user in `shared_preferences`. The
/// result: a doc saved here opens with zero network, forever.
///
/// **Isolation.** Files live under `offline_docs/<uid>/` and the metadata key
/// is per-uid, exactly like `LocalCollectionStore`: two accounts on one device
/// never see each other's offline library. Files deliberately SURVIVE account
/// switches and sign-outs - deleting them would defeat "view anytime"; they are
/// only removed when the user removes the doc from the offline list.
///
/// Everything is defensive: no network at load time, and a missing file (user
/// cleared app storage) drops that entry rather than throwing.
class OfflineDocumentStore extends ChangeNotifier {
  OfflineDocumentStore._();
  static final OfflineDocumentStore instance = OfflineDocumentStore._();

  /// Folder under the app documents directory that holds every offline copy.
  static const String dirName = 'offline_docs';

  static const String _keyPrefix = 'ino_offline_docs';
  static const String _kLastUidKey = 'ino_offline_docs_last_uid';

  final List<OfflineDoc> _docs = [];
  bool _loaded = false;
  String? _loadedUid;
  String? _baseDirPath;

  List<OfflineDoc> get docs => List.unmodifiable(_docs);
  bool get isLoaded => _loaded;
  bool get isEmpty => _docs.isEmpty;
  int get count => _docs.length;

  SupabaseClient? _client() {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  String? _uid() {
    try {
      return _client()?.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  String _prefsKey(String? uid) => '${_keyPrefix}_${uid ?? 'local'}';

  bool isSaved(String docId) => _docs.any((d) => d.id == docId);

  OfflineDoc? byId(String docId) {
    for (final d in _docs) {
      if (d.id == docId) return d;
    }
    return null;
  }

  /// The app documents directory, resolved once per launch.
  ///
  /// Deliberately never persisted: its value is the thing that changes across
  /// app updates, which is precisely why [OfflineDoc.relPath] exists.
  Future<String?> _baseDir() async {
    final cached = _baseDirPath;
    if (cached != null) return cached;
    try {
      final dir = await getApplicationDocumentsDirectory();
      return _baseDirPath = OfflineDoc._slashes(dir.path);
    } catch (_) {
      // No plugin (tests) - callers degrade to the stored absolute path.
      return null;
    }
  }

  /// Hydrates for the current user; reloads when the account changed. Safe to
  /// call from every screen's `initState`. Never touches the network.
  Future<void> ensureLoaded({bool force = false}) async {
    final liveUid = _uid();
    final p = await SharedPrefsCache.instance.prefsAsync;
    if (liveUid != null && liveUid.isNotEmpty) {
      await p.setString(_kLastUidKey, liveUid);
    }
    // Offline cold start: Supabase restores the session in the background and
    // may not have produced a user yet (and never will without network), so the
    // uid the library was saved under is remembered separately. Without this
    // the list reads an empty per-uid key and the offline screen looks empty
    // exactly when it is the only screen the user has.
    final uid = liveUid ?? p.getString(_kLastUidKey);
    if (!force && _loaded && uid == _loadedUid) return;

    final base = await _baseDir();
    final loaded = <OfflineDoc>[];
    var repaired = false;
    try {
      // This user's keys, plus the uid-less key that saves fall back to when
      // the session has not resolved yet. Deliberately NOT every offline key on
      // the device: that would hand one account another account's documents.
      final keysToTry = <String>{
        _prefsKey(uid),
        if (liveUid != null) _prefsKey(liveUid),
        _prefsKey(null),
      };

      final seenIds = <String>{};
      for (final key in keysToTry) {
        final list = p.getStringList(key);
        if (list == null) continue;
        for (final raw in list) {
          try {
            final stored =
                OfflineDoc.fromJson(jsonDecode(raw) as Map<String, dynamic>);
            if (stored.id.isEmpty || seenIds.contains(stored.id)) continue;
            // An entry whose file really is gone (storage cleared) is useless -
            // drop it so the list never advertises a doc it cannot open.
            final doc = await _locate(stored, base);
            if (doc == null) continue;
            if (doc.localPath != stored.localPath ||
                doc.relPath != stored.relPath) {
              repaired = true;
            }
            seenIds.add(doc.id);
            loaded.add(doc);
          } catch (_) {
            // Skip a corrupt entry rather than losing the whole library.
          }
        }
      }
    } catch (_) {
      // No plugin (tests) → empty, never throw.
    }
    _docs
      ..clear()
      ..addAll(loaded);
    _loaded = true;
    _loadedUid = uid;
    notifyListeners();

    // Rewrite entries whose paths moved, so the repair happens once instead of
    // on every launch.
    if (repaired) await _persist();

    // Background sync: push any locally cached documents to Supabase so
    // existing offline records populate the server-side table.
    if (liveUid != null && _docs.isNotEmpty) {
      _syncToSupabase(liveUid);
    }
  }

  /// Finds [doc]'s file in the container of this run, or null when it is
  /// genuinely gone.
  ///
  /// The relative path is tried first (the durable one), then the absolute path
  /// exactly as stored - which covers a legacy entry whose file sits outside
  /// the `offline_docs` tree, where no relative path can be derived.
  Future<OfflineDoc?> _locate(OfflineDoc doc, String? base) async {
    if (base != null && doc.relPath.isNotEmpty) {
      final resolved = doc.resolvedIn(base);
      if (await File(resolved.localPath).exists()) return resolved;
    }
    if (doc.localPath.isNotEmpty && await File(doc.localPath).exists()) {
      return doc;
    }
    return null;
  }

  /// The durable folder for the current user's offline files.
  Future<Directory> _dirFor(String uid) async {
    final base = await _baseDir();
    if (base == null) throw const FileSystemException('no documents directory');
    final dir = Directory('$base/$dirName/$uid');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Saves a document for offline viewing.
  ///
  /// [sourceFile] is an already-local copy when the caller has one (the viewer
  /// always does - it's the file being displayed), which makes saving instant
  /// and network-free. Without one, the file is downloaded once from Storage.
  /// Returns the entry, or null on failure (signed out, download failed).
  Future<OfflineDoc?> save({
    required String docId,
    required String name,
    required String wallet,
    required String objectPath,
    String? category,
    File? sourceFile,
  }) async {
    final p = await SharedPrefsCache.instance.prefsAsync;
    final uid = _uid() ?? p.getString(_kLastUidKey) ?? 'local';
    await ensureLoaded();

    try {
      final source = sourceFile ??
          await DocumentFileService.instance.ensureLocal(objectPath);
      final dir = await _dirFor(uid);
      final ext = DocumentFileService.extensionOf(objectPath);
      final safeId = docId.replaceAll(RegExp('[^a-zA-Z0-9_-]'), '_');
      final target = File('${dir.path}/$safeId.$ext');
      await source.copy(target.path);

      final entry = OfflineDoc(
        id: docId,
        name: name,
        wallet: wallet,
        category: category,
        relPath: '$dirName/$uid/$safeId.$ext',
        localPath: OfflineDoc._slashes(target.path),
        objectPath: objectPath,
        sizeBytes: await target.length(),
        savedAt: DateTime.now(),
      );
      _docs.removeWhere((d) => d.id == docId);
      _docs.insert(0, entry);
      notifyListeners();
      await _persist();
      developer.log('saved offline: $name (${entry.sizeLabel})',
          name: 'offline');

      // Best-effort sync to Supabase table
      if (uid != 'local') {
        _upsertToSupabase(uid, entry);
      }

      return entry;
    } catch (e) {
      developer.log('save offline failed: $e', name: 'offline');
      return null;
    }
  }

  /// Removes a doc from the offline library and deletes its on-device file.
  Future<void> remove(String docId) async {
    final uid = _uid();
    final entry = byId(docId);
    if (entry == null) return;
    _docs.removeWhere((d) => d.id == docId);
    notifyListeners();
    await _persist();
    try {
      final f = File(entry.localPath);
      if (await f.exists()) await f.delete();
    } catch (e) {
      // The entry is gone from the list either way; an orphaned file is
      // reclaimed the next time the same doc is saved (same target name).
      developer.log('offline file delete failed: $e', name: 'offline');
    }

    if (uid != null) {
      _deleteFromSupabase(uid, docId);
    }
  }

  /// When the underlying document is deleted from a wallet, its offline copy
  /// no longer has an owner - drop it too. No-op when it wasn't saved.
  Future<void> handleDocumentDeleted(String docId) => remove(docId);

  Future<void> _persist() async {
    try {
      final p = await SharedPrefsCache.instance.prefsAsync;
      final uid = _loadedUid ?? _uid() ?? p.getString(_kLastUidKey);
      await p.setStringList(
        _prefsKey(uid),
        [for (final d in _docs) jsonEncode(d.toJson())],
      );
      if (uid != null && uid != 'local') {
        await p.setString(_kLastUidKey, uid);
      }
    } catch (_) {
      // Best-effort; the in-memory list stays correct for this session.
    }
  }

  Future<void> _syncToSupabase(String uid) async {
    final client = _client();
    if (client == null || _docs.isEmpty) return;
    try {
      final rows = _docs
          .map((doc) => {
                'auth_user_id': uid,
                'document_id': doc.id,
                'name': doc.name,
                'wallet': doc.wallet,
                'category': doc.category,
                'object_path': doc.objectPath,
                'local_path': doc.relPath,
                'size_bytes': doc.sizeBytes,
                'saved_at': doc.savedAt.toIso8601String(),
              })
          .toList();

      await client.from('offline_documents').upsert(
            rows,
            onConflict: 'auth_user_id, document_id',
          );
      developer.log('synced ${_docs.length} offline docs to Supabase',
          name: 'offline');
    } catch (e) {
      developer.log('sync offline docs to Supabase failed: $e', name: 'offline');
    }
  }

  Future<void> _upsertToSupabase(String uid, OfflineDoc doc) async {
    final client = _client();
    if (client == null) return;
    try {
      await client.from('offline_documents').upsert(
        {
          'auth_user_id': uid,
          'document_id': doc.id,
          'name': doc.name,
          'wallet': doc.wallet,
          'category': doc.category,
          'object_path': doc.objectPath,
          'local_path': doc.relPath,
          'size_bytes': doc.sizeBytes,
          'saved_at': doc.savedAt.toIso8601String(),
        },
        onConflict: 'auth_user_id, document_id',
      );
      developer.log('upserted offline doc ${doc.id} to Supabase',
          name: 'offline');
    } catch (e) {
      developer.log('upsert offline doc to Supabase failed: $e',
          name: 'offline');
    }
  }

  Future<void> _deleteFromSupabase(String uid, String docId) async {
    final client = _client();
    if (client == null) return;
    try {
      await client.from('offline_documents').delete().match({
        'auth_user_id': uid,
        'document_id': docId,
      });
      developer.log('deleted offline doc $docId from Supabase',
          name: 'offline');
    } catch (e) {
      developer.log('delete offline doc from Supabase failed: $e',
          name: 'offline');
    }
  }

  /// Test hook: wipe in-memory state without touching storage.
  @visibleForTesting
  void reset() {
    _docs.clear();
    _loaded = false;
    _loadedUid = null;
    _baseDirPath = null;
  }
}
