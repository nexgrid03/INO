import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math' show Random;

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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
    var at = abs.lastIndexOf('/${OfflineDocumentStore.dirName}/');
    if (at < 0) at = abs.lastIndexOf('/offline_docs/');
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
  static const String dirName = 'offline';

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

  String _prefsKey(String uid) => '${_keyPrefix}_$uid';

  bool isSaved(String docId) => _docs.any((d) => d.id == docId);

  OfflineDoc? byId(String docId) {
    for (final d in _docs) {
      if (d.id == docId) return d;
    }
    return null;
  }

  /// The app documents directory, resolved once per launch.
  Future<String?> _baseDir() async {
    final cached = _baseDirPath;
    if (cached != null) return cached;
    try {
      final dir = await getApplicationDocumentsDirectory();
      return _baseDirPath = OfflineDoc._slashes(dir.path);
    } catch (_) {
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
    final uid = (liveUid != null && liveUid.isNotEmpty)
        ? liveUid
        : p.getString(_kLastUidKey);

    if (uid == null || uid.isEmpty) {
      _docs.clear();
      _loaded = true;
      _loadedUid = null;
      notifyListeners();
      return;
    }

    if (!force && _loaded && uid == _loadedUid) return;

    final base = await _baseDir();
    final loaded = <OfflineDoc>[];
    var repaired = false;
    try {
      final key = _prefsKey(uid);
      final list = p.getStringList(key);
      if (list != null) {
        final seenIds = <String>{};
        for (final raw in list) {
          try {
            final stored =
                OfflineDoc.fromJson(jsonDecode(raw) as Map<String, dynamic>);
            if (stored.id.isEmpty || seenIds.contains(stored.id)) continue;
            final doc = await _locate(stored, base);
            if (doc == null) continue;
            if (doc.localPath != stored.localPath ||
                doc.relPath != stored.relPath) {
              repaired = true;
            }
            seenIds.add(doc.id);
            loaded.add(doc);
          } catch (_) {
            // Skip corrupt entry
          }
        }
      }
    } catch (_) {
      // No plugin (tests) → empty
    }
    _docs
      ..clear()
      ..addAll(loaded);
    _loaded = true;
    _loadedUid = uid;
    notifyListeners();

    if (repaired) await _persist();

    if (liveUid != null && liveUid.isNotEmpty && _docs.isNotEmpty) {
      _syncToSupabase(liveUid);
    }
  }

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

  /// The durable folder for the current user's offline files (`offline/<uid>/documents`).
  Future<Directory> _dirFor(String uid) async {
    if (uid.isEmpty) throw StateError('User ID required for offline directory');
    final base = await _baseDir();
    if (base == null) throw const FileSystemException('no documents directory');
    final dir = Directory('$base/$dirName/$uid/documents');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Saves a document for offline viewing. Rejects save if user_id is unavailable.
  Future<OfflineDoc?> save({
    required String docId,
    required String name,
    required String wallet,
    required String objectPath,
    String? category,
    File? sourceFile,
  }) async {
    final p = await SharedPrefsCache.instance.prefsAsync;
    final uid = _uid() ?? p.getString(_kLastUidKey);
    if (uid == null || uid.isEmpty) {
      developer.log('Offline save rejected: active user ID required', name: 'offline');
      throw StateError('Offline document storage requires an active user ID.');
    }
    await ensureLoaded();

    try {
      final source = sourceFile ??
          await DocumentFileService.instance.ensureLocal(objectPath);
      final dir = await _dirFor(uid);
      final ext = DocumentFileService.extensionOf(objectPath);
      final safeId = docId.replaceAll(RegExp('[^a-zA-Z0-9_-]'), '_');
      final target = File('${dir.path}/$safeId.$ext');
      final rawBytes = await source.readAsBytes();
      final encryptedBytes = await _encryptBytes(rawBytes, uid);
      await target.writeAsBytes(encryptedBytes, flush: true);

      final entry = OfflineDoc(
        id: docId,
        name: name,
        wallet: wallet,
        category: category,
        relPath: '$dirName/$uid/documents/$safeId.$ext',
        localPath: OfflineDoc._slashes(target.path),
        objectPath: objectPath,
        sizeBytes: encryptedBytes.length,
        savedAt: DateTime.now(),
      );
      _docs.removeWhere((d) => d.id == docId);
      _docs.insert(0, entry);
      notifyListeners();
      await _persist();
      developer.log('saved offline: $name (${entry.sizeLabel})',
          name: 'offline');

      _upsertToSupabase(uid, entry);

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
      developer.log('offline file delete failed: $e', name: 'offline');
    }

    if (uid != null) {
      _deleteFromSupabase(uid, docId);
    }
  }

  Future<void> handleDocumentDeleted(String docId) => remove(docId);

  Future<void> _persist() async {
    try {
      final uid = _loadedUid ?? _uid();
      if (uid == null || uid.isEmpty) return;
      final p = await SharedPrefsCache.instance.prefsAsync;
      await p.setStringList(
        _prefsKey(uid),
        [for (final d in _docs) jsonEncode(d.toJson())],
      );
      await p.setString(_kLastUidKey, uid);
    } catch (_) {}
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

  static final _algorithm = AesGcm.with256bits();
  static const _secureStorage = FlutterSecureStorage();
  static const String _offlineKeyPrefix = 'ino_offline_key_';

  /// Obtains or generates a cryptographically secure random 256-bit encryption key
  /// per user, persisted safely in platform Keystore / Keychain via FlutterSecureStorage.
  static Future<SecretKey> _getOrCreateKey(String uid) async {
    if (uid.isEmpty) {
      throw StateError('Active user ID required for offline document encryption');
    }
    final storageKey = '$_offlineKeyPrefix$uid';
    try {
      final existingB64 = await _secureStorage.read(key: storageKey);
      if (existingB64 != null && existingB64.isNotEmpty) {
        final keyBytes = base64Decode(existingB64);
        if (keyBytes.length == 32) {
          return SecretKey(keyBytes);
        }
      }
    } catch (_) {}

    // Generate random 256-bit (32 bytes) key using cryptographically secure RNG
    final rng = Random.secure();
    final newKeyBytes = Uint8List.fromList(List<int>.generate(32, (_) => rng.nextInt(256)));
    try {
      await _secureStorage.write(key: storageKey, value: base64Encode(newKeyBytes));
    } catch (_) {}
    return SecretKey(newKeyBytes);
  }

  /// Encrypts raw document bytes using AES-256-GCM with a per-file random 12-byte nonce.
  /// Result format: [12-byte nonce][ciphertext][16-byte mac]
  static Future<Uint8List> _encryptBytes(Uint8List raw, String uid) async {
    final secretKey = await _getOrCreateKey(uid);
    // Generate fresh, cryptographically secure 12-byte nonce for EVERY document
    final rng = Random.secure();
    final nonce = List<int>.generate(12, (_) => rng.nextInt(256));
    final box = await _algorithm.encrypt(raw, secretKey: secretKey, nonce: nonce);
    return Uint8List.fromList([...box.nonce, ...box.cipherText, ...box.mac.bytes]);
  }

  static final _legacySecretKey = SecretKey(const [
    0x49, 0x4e, 0x4f, 0x5f, 0x4f, 0x46, 0x46, 0x4c, 0x49, 0x4e, 0x45, 0x5f, 0x44, 0x4f, 0x43, 0x5f,
    0x4b, 0x45, 0x59, 0x5f, 0x32, 0x30, 0x32, 0x36, 0x5f, 0x53, 0x45, 0x43, 0x55, 0x52, 0x45, 0x21
  ]);

  /// Decrypts document bytes using AES-256-GCM.
  /// Strictly throws an error if authentication / integrity check fails.
  /// NEVER returns raw encrypted input on failure.
  /// Provides backward-compatible migration path for pre-existing legacy documents.
  static Future<Uint8List> _decryptBytes(
    Uint8List encrypted,
    String? uid, {
    File? fileToMigrate,
  }) async {
    const nonceLen = 12;
    const macLen = 16;
    if (encrypted.length < (nonceLen + macLen)) {
      throw const FormatException('Corrupted offline file: insufficient data length');
    }
    final effectiveUid = uid ?? instance._loadedUid ?? instance._uid();
    if (effectiveUid == null || effectiveUid.isEmpty) {
      throw StateError('User ID required for offline document decryption');
    }

    final secretKey = await _getOrCreateKey(effectiveUid);
    final nonce = encrypted.sublist(0, nonceLen);
    final cipherText = encrypted.sublist(nonceLen, encrypted.length - macLen);
    final mac = Mac(encrypted.sublist(encrypted.length - macLen));
    final box = SecretBox(cipherText, nonce: nonce, mac: mac);

    try {
      // 1. Primary: decrypt using user-specific random key
      final decrypted = await _algorithm.decrypt(box, secretKey: secretKey);
      return Uint8List.fromList(decrypted);
    } catch (_) {
      // 2. Compatibility fallback: check if document was encrypted under legacy key
      try {
        final legacyDecrypted = await _algorithm.decrypt(box, secretKey: _legacySecretKey);
        final plaintext = Uint8List.fromList(legacyDecrypted);

        // Lazily migrate and re-encrypt under the new per-user key on disk
        if (fileToMigrate != null) {
          try {
            final reEncrypted = await _encryptBytes(plaintext, effectiveUid);
            await fileToMigrate.writeAsBytes(reEncrypted, flush: true);
            developer.log('Migrated legacy offline document to per-user AES-256 key', name: 'offline');
          } catch (e) {
            developer.log('Lazy re-encryption failed: $e', name: 'offline');
          }
        }
        return plaintext;
      } catch (e) {
        developer.log('Offline document decryption failed (tampered or invalid key): $e', name: 'offline');
        throw StateError('Decryption failed: integrity check failed or corrupted file');
      }
    }
  }

  /// Returns a temporary decrypted file for viewing offline documents.
  Future<File?> getDecryptedFile(OfflineDoc doc) async {
    try {
      final f = File(doc.localPath);
      if (!await f.exists()) return null;
      final raw = await f.readAsBytes();
      final uid = _loadedUid ?? _uid();
      final decrypted = await _decryptBytes(raw, uid, fileToMigrate: f);
      final tmpDir = await getTemporaryDirectory();
      final safeId = doc.id.replaceAll(RegExp('[^a-zA-Z0-9_-]'), '_');
      final ext = doc.extension;
      final tempFile = File('${tmpDir.path}/view_$safeId.$ext');
      await tempFile.writeAsBytes(decrypted, flush: true);
      return tempFile;
    } catch (e) {
      developer.log('getDecryptedFile failed: $e', name: 'offline');
      return null;
    }
  }

  /// Visible for unit testing encryption guarantees (per-user keys, random nonce, tamper rejection)
  @visibleForTesting
  static Future<Uint8List> encryptBytesForTest(Uint8List raw, String uid) =>
      _encryptBytes(raw, uid);

  @visibleForTesting
  static Future<Uint8List> decryptBytesForTest(Uint8List encrypted, String uid) =>
      _decryptBytes(encrypted, uid);

  @visibleForTesting
  static Future<SecretKey> getKeyForTest(String uid) => _getOrCreateKey(uid);

  /// Wipes all offline document state, metadata, and disk files on logout / clear.
  Future<void> clear() async {
    _docs.clear();
    _loaded = false;
    _loadedUid = null;
    _baseDirPath = null;
    notifyListeners();
    try {
      final p = await SharedPrefsCache.instance.prefsAsync;
      final keys = p.getKeys();
      for (final k in keys) {
        if (k.startsWith(_keyPrefix) || k == _kLastUidKey) {
          await p.remove(k);
        }
      }
      final base = await _baseDir();
      if (base != null) {
        final dir = Directory('$base/$dirName');
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      }
    } catch (e) {
      developer.log('OfflineDocumentStore clear failed: $e', name: 'offline');
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
