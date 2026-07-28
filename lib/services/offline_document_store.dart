import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'document_file_service.dart';

/// One document saved for offline viewing.
class OfflineDoc {
  const OfflineDoc({
    required this.id,
    required this.name,
    required this.wallet,
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

  /// The durable on-device copy. This is what the offline viewer opens.
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

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'wallet': wallet,
        'category': category,
        'localPath': localPath,
        'objectPath': objectPath,
        'sizeBytes': sizeBytes,
        'savedAt': savedAt.toIso8601String(),
      };

  factory OfflineDoc.fromJson(Map<String, dynamic> j) => OfflineDoc(
        id: j['id']?.toString() ?? '',
        name: (j['name'] as String?) ?? 'Document',
        wallet: (j['wallet'] as String?) ?? '',
        category: j['category'] as String?,
        localPath: (j['localPath'] as String?) ?? '',
        objectPath: (j['objectPath'] as String?) ?? '',
        sizeBytes: (j['sizeBytes'] as num?)?.toInt() ?? 0,
        savedAt:
            DateTime.tryParse(j['savedAt'] as String? ?? '') ?? DateTime.now(),
      );
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

  static const String _keyPrefix = 'ino_offline_docs';

  final List<OfflineDoc> _docs = [];
  bool _loaded = false;
  String? _loadedUid;

  List<OfflineDoc> get docs => List.unmodifiable(_docs);
  bool get isLoaded => _loaded;
  bool get isEmpty => _docs.isEmpty;
  int get count => _docs.length;

  String? _uid() {
    try {
      return Supabase.instance.client.auth.currentUser?.id;
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

  /// Hydrates for the current user; reloads when the account changed. Safe to
  /// call from every screen's `initState`. Never touches the network.
  Future<void> ensureLoaded() async {
    final uid = _uid();
    if (_loaded && uid == _loadedUid) return;
    final loaded = <OfflineDoc>[];
    try {
      final p = await SharedPreferences.getInstance();
      for (final raw in p.getStringList(_prefsKey(uid)) ?? const <String>[]) {
        try {
          final doc =
              OfflineDoc.fromJson(jsonDecode(raw) as Map<String, dynamic>);
          // An entry whose file vanished (storage cleared) is useless - drop
          // it here so the list never advertises a doc it cannot open.
          if (doc.localPath.isNotEmpty && File(doc.localPath).existsSync()) {
            loaded.add(doc);
          }
        } catch (_) {
          // Skip a corrupt entry rather than losing the whole library.
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
  }

  /// The durable folder for the current user's offline files.
  Future<Directory> _dirFor(String uid) async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/offline_docs/$uid');
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
    final uid = _uid();
    if (uid == null) return null;
    await ensureLoaded();

    try {
      final source = sourceFile ??
          await DocumentFileService.instance.ensureLocal(objectPath);
      final dir = await _dirFor(uid);
      final ext = DocumentFileService.extensionOf(objectPath);
      final safeId = docId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final target = File('${dir.path}/$safeId.$ext');
      await source.copy(target.path);

      final entry = OfflineDoc(
        id: docId,
        name: name,
        wallet: wallet,
        category: category,
        localPath: target.path,
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
      return entry;
    } catch (e) {
      developer.log('save offline failed: $e', name: 'offline');
      return null;
    }
  }

  /// Removes a doc from the offline library and deletes its on-device file.
  Future<void> remove(String docId) async {
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
  }

  /// When the underlying document is deleted from a wallet, its offline copy
  /// no longer has an owner - drop it too. No-op when it wasn't saved.
  Future<void> handleDocumentDeleted(String docId) => remove(docId);

  Future<void> _persist() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(
        _prefsKey(_loadedUid),
        [for (final d in _docs) jsonEncode(d.toJson())],
      );
    } catch (_) {
      // Best-effort; the in-memory list stays correct for this session.
    }
  }

  /// Test hook: wipe in-memory state without touching storage.
  @visibleForTesting
  void reset() {
    _docs.clear();
    _loaded = false;
    _loadedUid = null;
  }
}
