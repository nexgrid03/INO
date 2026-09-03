import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/storage/shared_prefs_cache.dart';

import '../core/net/net_guard.dart';
import '../core/net/paged_query.dart';
import '../core/perf/perf_tracer.dart';
import '../core/net/stream_download.dart';
import '../models/document.dart';
import '../services/storage_stats_service.dart';
import 'wallet_tables.dart';

/// Thrown when an upload would cause the user's storage to exceed the 5 GB quota.
class StorageQuotaExceededException implements Exception {
  final String message;
  const StorageQuotaExceededException([
    this.message =
        'Storage limit of 5 GB reached. Please delete some documents to continue uploading.',
  ]);

  @override
  String toString() => message;
}

/// The ONLY place in the app that reads/writes wallet records.
///
/// Screens go through this repository instead of querying Supabase directly -
/// the same pattern as [UserRepository]. RLS guarantees a user only ever
/// touches their own rows, so we never pass a user id: every table fills
/// `auth_user_id` from `auth.uid()` automatically.
///
/// Since the 20260727 migration each wallet has its OWN table (see
/// [WalletTables]). Writes therefore need to know which wallet a record belongs
/// to; reads that span wallets go through the read-only `documents` view.
class DocumentRepository {
  DocumentRepository._();
  static final DocumentRepository instance = DocumentRepository._();

  /// The Supabase client (created in main.dart at startup).
  SupabaseClient get _client => Supabase.instance.client;

  static const String _bucket = 'documents';

  /// Hidden wallet that holds PROCESSED SHARE COPIES (black & white / grayscale /
  /// compressed-PDF images produced for a QR share). They live as real document
  /// rows so the existing `share` Edge Function can serve them by id - exactly
  /// like any other document - but sit in their own table, so they never appear
  /// in the user's wallets, search, dashboards or exports.
  static const String shareCacheWallet = '__ino_share_cache__';

  /// The table backing [wallet].
  String _tableFor(String wallet) => WalletTables.slugFor(wallet);

  /// The signed-in user's id, or null when signed out.
  String? get _uid => _client.auth.currentUser?.id;

  /// Bumped every time the document set changes (create / delete / upload) so
  /// listeners - e.g. the Profile storage meter - can refresh automatically
  /// without polling.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static void _bump() {
    instance.clearCache();
    revision.value++;
  }

  // --- In-memory cache & request deduplication ------------------------------
  static const Duration _cacheTtl = Duration(minutes: 2);
  List<Document>? _cachedAll;
  DateTime? _cachedAllTime;
  Future<List<Document>>? _inFlightAll;

  final Map<String, List<Document>> _cachedWallet = {};
  final Map<String, DateTime> _cachedWalletTime = {};
  final Map<String, Future<List<Document>>> _inFlightWallet = {};

  /// Clears the document cache (automatically called when documents are modified).
  void clearCache() {
    _cachedAll = null;
    _cachedAllTime = null;
    _cachedWallet.clear();
    _cachedWalletTime.clear();
  }

  // --- Disk persistence layer for offline-first hydration -------------------
  static const String _diskCachePrefix = 'ino_doc_cache';

  Future<void> _persistDiskCache(String userId, List<Document> list) async {
    try {
      final prefs = await SharedPrefsCache.instance.prefsAsync;
      final key = '${_diskCachePrefix}_$userId';
      final jsonList = list.map((d) => d.toMap()).toList();
      await prefs.setString(key, jsonEncode(jsonList));
      developer.log('[DOC_CACHE] Disk cache saved count=${list.length} key=$key', name: 'documents');
    } catch (e) {
      developer.log('failed to persist document disk cache: $e', name: 'documents');
    }
  }

  Future<List<Document>> _readDiskCache(String userId) async {
    try {
      final prefs = await SharedPrefsCache.instance.prefsAsync;
      final key = '${_diskCachePrefix}_$userId';
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return const [];
      final List decoded = jsonDecode(raw) as List;
      final docs = decoded.map((e) => Document.fromMap(e as Map<String, dynamic>)).toList();
      developer.log('[DOC_CACHE] Disk cache loaded count=${docs.length} key=$key', name: 'documents');
      return docs;
    } catch (e) {
      developer.log('failed to read document disk cache: $e', name: 'documents');
      return const [];
    }
  }

  /// Uploads a local image/PDF to the `documents` Storage bucket and returns
  /// its object path (which you save in the row's `file_path`).
  ///
  /// The path starts with the user's id folder (`<uid>/<timestamp>.ext`), which
  /// is what the Storage RLS policies require. Only succeeds while signed in.
  Future<String> uploadFile(String localPath) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw const AuthException('You must be signed in to upload a document.');
    }

    final file = File(localPath);
    if (await file.exists()) {
      final uploadSize = await file.length();
      final usage = await StorageStatsService.instance.load();
      if (usage.usedBytes + uploadSize > StorageUsage.defaultQuotaBytes) {
        throw const StorageQuotaExceededException();
      }
    }

    final ext = localPath.contains('.') ? localPath.split('.').last : 'jpg';
    final objectPath = '$userId/${DateTime.now().millisecondsSinceEpoch}.$ext';
    final stored = await _client.storage
        .from(_bucket)
        .upload(objectPath, file)
        .timeout(NetGuard.storage);
    // `upload` returns the full "<bucket>/<path>" key on success; the value we
    // persist and read back is the object path (without the bucket prefix).
    developer.log(
      'uploaded to bucket=$_bucket path=$objectPath (key=$stored)',
      name: 'storage',
    );
    _bump();
    return objectPath;
  }

  /// A temporary, signed URL for viewing a stored file (private bucket).
  Future<String> signedUrl(String objectPath, {int expiresInSeconds = 3600}) async {
    developer.log('createSignedUrl bucket=$_bucket path=$objectPath', name: 'storage');
    final url = await _client.storage
        .from(_bucket)
        .createSignedUrl(objectPath, expiresInSeconds)
        .timeout(NetGuard.query);
    return url;
  }

  /// Downloads the raw bytes of a stored file (private bucket). Throws if the
  /// object no longer exists.
  ///
  /// Prefer [downloadToFile] when the destination is disk (backups, exports,
  /// save-to-device): it streams in chunks instead of materialising the whole
  /// file in RAM. This byte form remains for viewers, which need the bytes in
  /// memory to render anyway.
  Future<Uint8List> download(String objectPath) {
    developer.log('download bucket=$_bucket path=$objectPath', name: 'storage');
    return _client.storage
        .from(_bucket)
        .download(objectPath)
        .timeout(NetGuard.storage);
  }

  /// Streams a stored file straight to [dest] without ever holding the full
  /// contents in memory - chunked through a signed URL. Use for any path whose
  /// end state is a file on disk; large PDFs no longer spike RAM this way.
  Future<void> downloadToFile(String objectPath, File dest) async {
    developer.log('downloadToFile bucket=$_bucket path=$objectPath',
        name: 'storage');
    final url = await signedUrl(objectPath, expiresInSeconds: 600);
    await streamUrlToFile(
      url,
      dest,
      onError: (code) =>
          StorageException('Download failed (HTTP $code) for $objectPath'),
    );
  }

  /// Renames a document (updates the `name` column).
  Future<void> rename(String id, String name, {required String wallet}) =>
      update(id, {'name': name.trim()}, wallet: wallet);

  /// Moves a document to a different wallet.
  ///
  /// A wallet is now a table, not a column, so this copies the core columns
  /// across and deletes the original. The id is carried over deliberately:
  /// document protection flags and live share links reference it, and letting a
  /// move mint a new id would silently break both.
  ///
  /// Only the columns every wallet shares travel. Wallet-specific detail (a
  /// property's registration data, a card's last4) does NOT survive a move,
  /// because the destination table has nowhere to put it.
  Future<void> move(String id,
      {required String fromWallet, required String toWallet}) async {
    final userId = _uid;
    if (userId == null) {
      throw const AuthException('You must be signed in to move a document.');
    }
    if (WalletTables.slugFor(fromWallet) == WalletTables.slugFor(toWallet)) {
      return;
    }

    final row = await _client
        .from(_tableFor(fromWallet))
        .select()
        .eq('id', id)
        .eq('auth_user_id', userId)
        .single()
        .timeout(NetGuard.query);

    await _client.from(_tableFor(toWallet)).insert({
      'id': row['id'],
      'auth_user_id': userId,
      'name': row['name'],
      'category': row['category'],
      'record_number': row['record_number'],
      'status': row['status'],
      'tags': row['tags'],
      'notes': row['notes'],
      'is_favorite': row['is_favorite'],
      'expires_at': row['expires_at'],
      'file_path': row['file_path'],
      'created_at': row['created_at'],
      // A move is not a new save - carry the original row's consent forward.
      'consent': row['consent'] ?? false,
    }).timeout(NetGuard.mutation);

    await _client
        .from(_tableFor(fromWallet))
        .delete()
        .eq('id', id)
        .eq('auth_user_id', userId)
        .timeout(NetGuard.mutation);
    _bump();
  }

  /// Inserts a new document row into [wallet]'s table and returns it.
  ///
  /// Only sends the columns we own; the database fills the rest (`id`,
  /// `auth_user_id`, timestamps) from the DEFAULTs in the schema.
  ///
  /// RLS note: only succeeds while the user is signed in, because the INSERT
  /// policy requires `auth.uid() = auth_user_id`.
  Future<Document> create({
    required String wallet,
    required String name,
    String? category,
    String? recordNumber,
    String status = 'active',
    List<String> tags = const [],
    String? notes,
    bool isFavorite = false,
    DateTime? expiresAt,
    String? filePath,
    String? doctorName,
  }) async {
    final userId = _uid;
    if (userId == null) {
      throw const AuthException('You must be signed in to add a document.');
    }
    final insertData = <String, dynamic>{
      'auth_user_id': userId,
      'name': name,
      'category': category,
      'record_number': recordNumber,
      'status': status,
      'tags': tags,
      'notes': notes,
      'is_favorite': isFavorite,
      'expires_at': expiresAt == null ? null : _dateOnly(expiresAt),
      'file_path': filePath,
      'consent': true,
    };
    if (WalletTables.slugFor(wallet) == 'w_health_wallet') {
      insertData['doctor_name'] = doctorName;
    }
    final row = await _client
        .from(_tableFor(wallet))
        .insert(insertData)
        .select() // ask Supabase to return the inserted row
        .single() // expect exactly one row back
        .timeout(NetGuard.mutation);
    _bump();
    return Document.fromMap(row, wallet: wallet);
  }

  /// Fast 2-second timeout for document query network fetches so offline detection is instant.
  static const Duration _queryOfflineTimeout = Duration(seconds: 2);

  /// All documents in one wallet, newest first. Reads the wallet's own table
  /// rather than the union view, so it never scans the other wallets.
  Future<List<Document>> listForWallet(String wallet, {bool forceRefresh = false}) =>
      PerfTracer.traceQuery('DocumentRepository.listForWallet($wallet)', () async {
    final userId = _uid;
    if (userId == null) return const [];

    final now = DateTime.now();
    if (!forceRefresh &&
        _cachedWallet.containsKey(wallet) &&
        _cachedWalletTime.containsKey(wallet) &&
        now.difference(_cachedWalletTime[wallet]!) < _cacheTtl) {
      return _cachedWallet[wallet]!;
    }

    if (_inFlightWallet.containsKey(wallet)) {
      return _inFlightWallet[wallet]!;
    }

    final future = () async {
      try {
        final rows = await fetchAllPaged(
          (from, to) => _client
              .from(_tableFor(wallet))
              .select()
              .eq('auth_user_id', userId)
              .order('created_at', ascending: false)
              .order('id', ascending: false)
              .range(from, to)
              .timeout(_queryOfflineTimeout),
          label: 'listForWallet($wallet)',
        );
        final list = [for (final r in rows) Document.fromMap(r, wallet: wallet)];
        _cachedWallet[wallet] = list;
        _cachedWalletTime[wallet] = DateTime.now();
        developer.log('[DOC_CACHE] Network sync success wallet=$wallet count=${list.length}', name: 'documents');
        return list;
      } catch (e) {
        developer.log('[DOC_CACHE] Network sync failed using cache wallet=$wallet error: $e', name: 'documents');
        if (_cachedWallet.containsKey(wallet)) {
          return _cachedWallet[wallet]!;
        }
        final allDocs = _cachedAll ?? await _readDiskCache(userId);
        final walletDocs = allDocs.where((d) => WalletTables.slugFor(d.wallet) == WalletTables.slugFor(wallet)).toList();
        _cachedWallet[wallet] = walletDocs;
        return walletDocs;
      } finally {
        _inFlightWallet.remove(wallet);
      }
    }();

    _inFlightWallet[wallet] = future;
    return future;
  });

  /// Every document belonging to the signed-in user, newest first, across every
  /// wallet - so this reads the `documents` union view. Excludes the hidden
  /// [shareCacheWallet] copies so processed share images never surface in
  /// search / dashboards / exports.
  Future<List<Document>> listAll({bool forceRefresh = false}) =>
      PerfTracer.traceQuery('DocumentRepository.listAll', () async {
    final userId = _uid;
    if (userId == null) return const [];

    final now = DateTime.now();
    if (!forceRefresh &&
        _cachedAll != null &&
        _cachedAllTime != null &&
        now.difference(_cachedAllTime!) < _cacheTtl) {
      return _cachedAll!;
    }

    if (_inFlightAll != null) {
      return _inFlightAll!;
    }

    // Hydrate disk cache into RAM if memory cache is null for instant offline rendering
    var hasLocalDiskData = false;
    if (_cachedAll == null) {
      final diskDocs = await _readDiskCache(userId);
      if (diskDocs.isNotEmpty) {
        _cachedAll = diskDocs;
        _cachedAllTime = DateTime.now();
        hasLocalDiskData = true;
      }
    }

    final fetchFuture = () async {
      try {
        final rows = await fetchAllPaged(
          (from, to) => _client
              .from(WalletTables.documentsView)
              .select()
              .eq('auth_user_id', userId)
              .neq('wallet', shareCacheWallet)
              .order('created_at', ascending: false)
              .order('id', ascending: false)
              .range(from, to)
              .timeout(_queryOfflineTimeout),
          label: 'listAll',
        );
        final list = [for (final r in rows) Document.fromMap(r)];
        _cachedAll = list;
        _cachedAllTime = DateTime.now();
        developer.log('[DOC_CACHE] Network sync success count=${list.length}', name: 'documents');
        unawaited(_persistDiskCache(userId, list));
        return list;
      } catch (e) {
        developer.log('[DOC_CACHE] Network sync failed using cache error: $e', name: 'documents');
        final fallback = _cachedAll ?? await _readDiskCache(userId);
        _cachedAll = fallback;
        return fallback;
      } finally {
        _inFlightAll = null;
      }
    }();

    _inFlightAll = fetchFuture;

    // If we have valid local disk data, fire-and-forget network sync in background so UI renders instantly!
    if (hasLocalDiskData && !forceRefresh) {
      unawaited(fetchFuture);
      return _cachedAll!;
    }

    return fetchFuture;
  });

  /// The processed share copies (hidden [shareCacheWallet] rows), newest first.
  Future<List<Document>> listShareCopies() => listForWallet(shareCacheWallet);

  /// Best-effort cleanup of processed share copies older than [olderThan] (past
  /// the maximum share TTL, so their QR links have already expired). Removes both
  /// the row and its Storage object. Never throws - cleanup is opportunistic.
  Future<void> pruneShareCopies(
      {Duration olderThan = const Duration(days: 8)}) async {
    try {
      final copies = await listShareCopies();
      if (copies.isEmpty) return;
      final cutoff = DateTime.now().subtract(olderThan);
      final stalePaths = <String>[];
      for (final d in copies) {
        if (d.createdAt.isBefore(cutoff)) {
          final p = d.filePath;
          if (p != null && p.isNotEmpty) stalePaths.add(p);
          await delete(d.id, wallet: shareCacheWallet);
        }
      }
      if (stalePaths.isNotEmpty) await removeObjects(stalePaths);
    } catch (e) {
      developer.log('pruneShareCopies (non-fatal): $e', name: 'storage');
    }
  }

  /// Fresh row for [id] in [wallet], bypassing the list cache.
  ///
  /// Used by Share via QR to re-hydrate `file_path` when the in-memory wallet
  /// list is stale (e.g. offline cache, older add flow, repaired path).
  /// Falls back to the `documents` union view when the row isn't in [wallet]
  /// (e.g. after a move).
  Future<Document?> getById(String id, {required String wallet}) async {
    final userId = _uid;
    if (userId == null) return null;
    try {
      final row = await _client
          .from(_tableFor(wallet))
          .select()
          .eq('id', id)
          .eq('auth_user_id', userId)
          .maybeSingle()
          .timeout(NetGuard.query);
      if (row != null) return Document.fromMap(row, wallet: wallet);

      final any = await _client
          .from(WalletTables.documentsView)
          .select()
          .eq('id', id)
          .eq('auth_user_id', userId)
          .maybeSingle()
          .timeout(NetGuard.query);
      if (any == null) return null;
      return Document.fromMap(any);
    } catch (e, st) {
      developer.log('getById($id, $wallet) failed: $e',
          name: 'docs', error: e, stackTrace: st);
      return null;
    }
  }

  /// Updates a few columns on an existing row (e.g. favourite / status).
  /// RLS guarantees the user can only touch their own rows; the explicit
  /// auth_user_id filter is defense-in-depth so ownership is verified here too.
  Future<void> update(String id, Map<String, dynamic> fields,
      {required String wallet}) async {
    final userId = _uid;
    if (userId == null) {
      throw const AuthException('You must be signed in to edit a document.');
    }
    await _client
        .from(_tableFor(wallet))
        .update(fields)
        .eq('id', id)
        .eq('auth_user_id', userId)
        .timeout(NetGuard.mutation);
  }

  /// Deletes a document row by id (only if it belongs to the signed-in user).
  Future<void> delete(String id, {required String wallet}) async {
    final userId = _uid;
    if (userId == null) {
      throw const AuthException('You must be signed in to delete a document.');
    }
    await _client
        .from(_tableFor(wallet))
        .delete()
        .eq('id', id)
        .eq('auth_user_id', userId)
        .timeout(NetGuard.mutation);
    _bump();
  }

  // ---- Storage introspection / account deletion ---------------------------

  /// Lists the raw Storage objects under the signed-in user's folder - used by
  /// the storage meter (sizes) and account deletion (cleanup). Returns an empty
  /// list when signed out. [subFolder] targets e.g. the `backups` sub-folder.
  Future<List<FileObject>> listUserObjects({String? subFolder}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const [];
    final path = subFolder == null ? userId : '$userId/$subFolder';
    final objects = await _client.storage
        .from(_bucket)
        .list(path: path)
        .timeout(NetGuard.query);
    // Storage returns folder entries with a null id; keep only real files.
    return objects.where((o) => o.id != null).toList();
  }

  /// Removes Storage objects by their full object paths (`<uid>/<file>`).
  Future<void> removeObjects(List<String> objectPaths) async {
    if (objectPaths.isEmpty) return;
    await _client.storage
        .from(_bucket)
        .remove(objectPaths)
        .timeout(NetGuard.mutation);
    developer.log('removed ${objectPaths.length} object(s)', name: 'storage');
  }

  /// Deletes every document row belonging to the signed-in user, in every
  /// wallet. RLS already scopes this to their own rows; the explicit filter
  /// satisfies Supabase's "delete needs a filter" guard.
  ///
  /// Each table is cleared independently: one wallet failing must not leave the
  /// remaining wallets' rows behind on an account deletion.
  Future<void> deleteAllRowsForUser() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    final slugs = await WalletTables.allSlugs();
    Object? firstError;
    for (final slug in slugs) {
      try {
        await _client
            .from(slug)
            .delete()
            .eq('auth_user_id', userId)
            .timeout(NetGuard.mutation);
      } catch (e) {
        developer.log('deleteAllRowsForUser: $slug failed: $e', name: 'storage');
        firstError ??= e;
      }
    }
    _bump();
    if (firstError != null) throw firstError;
  }

  /// Uploads arbitrary bytes to an object path (used for JSON cloud backups).
  /// Overwrites any existing object at that path.
  Future<void> uploadBytes(
    String objectPath,
    Uint8List bytes, {
    String contentType = 'application/octet-stream',
  }) async {
    await _client.storage
        .from(_bucket)
        .uploadBinary(
          objectPath,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        )
        .timeout(NetGuard.storage);
    developer.log('uploaded ${bytes.length}B to $objectPath', name: 'storage');
  }

  String _dateOnly(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
