import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/document.dart';

/// The ONLY place in the app that reads/writes the `public.documents` table.
///
/// Screens go through this repository instead of querying Supabase directly —
/// the same pattern as [UserRepository]. RLS guarantees a user only ever
/// touches their own rows, so we never pass a user id: the table fills
/// `auth_user_id` from `auth.uid()` automatically.
class DocumentRepository {
  DocumentRepository._();
  static final DocumentRepository instance = DocumentRepository._();

  /// The Supabase client (created in main.dart at startup).
  SupabaseClient get _client => Supabase.instance.client;

  static const String _table = 'documents';
  static const String _bucket = 'documents';

  /// Hidden wallet that holds PROCESSED SHARE COPIES (black & white / grayscale /
  /// compressed-PDF images produced for a QR share). They live as real
  /// `documents` rows so the existing `share` Edge Function can serve them by id
  /// — exactly like any other document — but are filtered out of [listAll] so
  /// they never appear in the user's wallets, search, dashboards or exports.
  static const String shareCacheWallet = '__ino_share_cache__';

  /// The signed-in user's id, or null when signed out.
  String? get _uid => _client.auth.currentUser?.id;

  /// Bumped every time the document set changes (create / delete / upload) so
  /// listeners — e.g. the Profile storage meter — can refresh automatically
  /// without polling.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static void _bump() => revision.value++;

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
    final ext = localPath.contains('.') ? localPath.split('.').last : 'jpg';
    final objectPath = '$userId/${DateTime.now().millisecondsSinceEpoch}.$ext';
    final stored =
        await _client.storage.from(_bucket).upload(objectPath, File(localPath));
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
        .createSignedUrl(objectPath, expiresInSeconds);
    return url;
  }

  /// Downloads the raw bytes of a stored file (private bucket). Throws if the
  /// object no longer exists.
  Future<Uint8List> download(String objectPath) {
    developer.log('download bucket=$_bucket path=$objectPath', name: 'storage');
    return _client.storage.from(_bucket).download(objectPath);
  }

  /// Renames a document (updates the `name` column).
  Future<void> rename(String id, String name) =>
      update(id, {'name': name.trim()});

  /// Moves a document to a different wallet.
  Future<void> move(String id, String wallet) => update(id, {'wallet': wallet});

  /// Inserts a new document row and returns it.
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
  }) async {
    final userId = _uid;
    if (userId == null) {
      throw const AuthException('You must be signed in to add a document.');
    }
    final row = await _client
        .from(_table)
        .insert({
          // Stamp the owner explicitly (the column also defaults to auth.uid()
          // and RLS enforces it) so no document is ever created without an owner.
          'auth_user_id': userId,
          'wallet': wallet,
          'name': name,
          'category': category,
          'record_number': recordNumber,
          'status': status,
          'tags': tags,
          'notes': notes,
          'is_favorite': isFavorite,
          // `expires_at` is a DATE column — send YYYY-MM-DD, not a timestamp.
          'expires_at': expiresAt == null ? null : _dateOnly(expiresAt),
          'file_path': filePath,
        })
        .select() // ask Supabase to return the inserted row
        .single(); // expect exactly one row back
    _bump();
    return Document.fromMap(row);
  }

  /// All documents in one wallet, newest first.
  Future<List<Document>> listForWallet(String wallet) async {
    final userId = _uid;
    if (userId == null) return const [];
    final rows = await _client
        .from(_table)
        .select()
        .eq('auth_user_id', userId) // defense-in-depth with RLS
        .eq('wallet', wallet)
        .order('created_at', ascending: false);
    return [for (final r in rows) Document.fromMap(r)];
  }

  /// Every document belonging to the signed-in user, newest first. Excludes the
  /// hidden [shareCacheWallet] copies so processed share images never surface in
  /// search / dashboards / exports.
  Future<List<Document>> listAll() async {
    final userId = _uid;
    if (userId == null) return const [];
    final rows = await _client
        .from(_table)
        .select()
        .eq('auth_user_id', userId) // defense-in-depth with RLS
        .neq('wallet', shareCacheWallet)
        .order('created_at', ascending: false);
    return [for (final r in rows) Document.fromMap(r)];
  }

  /// The processed share copies (hidden [shareCacheWallet] rows), newest first.
  Future<List<Document>> listShareCopies() async {
    final userId = _uid;
    if (userId == null) return const [];
    final rows = await _client
        .from(_table)
        .select()
        .eq('auth_user_id', userId)
        .eq('wallet', shareCacheWallet)
        .order('created_at', ascending: false);
    return [for (final r in rows) Document.fromMap(r)];
  }

  /// Best-effort cleanup of processed share copies older than [olderThan] (past
  /// the maximum share TTL, so their QR links have already expired). Removes both
  /// the row and its Storage object. Never throws — cleanup is opportunistic.
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
          await delete(d.id);
        }
      }
      if (stalePaths.isNotEmpty) await removeObjects(stalePaths);
    } catch (e) {
      developer.log('pruneShareCopies (non-fatal): $e', name: 'storage');
    }
  }

  /// Updates a few columns on an existing row (e.g. favourite / status).
  /// RLS guarantees the user can only touch their own rows; the explicit
  /// auth_user_id filter is defense-in-depth so ownership is verified here too.
  Future<void> update(String id, Map<String, dynamic> fields) async {
    final userId = _uid;
    if (userId == null) {
      throw const AuthException('You must be signed in to edit a document.');
    }
    await _client.from(_table).update(fields).eq('id', id).eq('auth_user_id', userId);
  }

  /// Deletes a document row by id (only if it belongs to the signed-in user).
  Future<void> delete(String id) async {
    final userId = _uid;
    if (userId == null) {
      throw const AuthException('You must be signed in to delete a document.');
    }
    await _client.from(_table).delete().eq('id', id).eq('auth_user_id', userId);
    _bump();
  }

  // ---- Storage introspection / account deletion ---------------------------

  /// Lists the raw Storage objects under the signed-in user's folder — used by
  /// the storage meter (sizes) and account deletion (cleanup). Returns an empty
  /// list when signed out. [subFolder] targets e.g. the `backups` sub-folder.
  Future<List<FileObject>> listUserObjects({String? subFolder}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const [];
    final path = subFolder == null ? userId : '$userId/$subFolder';
    final objects = await _client.storage.from(_bucket).list(path: path);
    // Storage returns folder entries with a null id; keep only real files.
    return objects.where((o) => o.id != null).toList();
  }

  /// Removes Storage objects by their full object paths (`<uid>/<file>`).
  Future<void> removeObjects(List<String> objectPaths) async {
    if (objectPaths.isEmpty) return;
    await _client.storage.from(_bucket).remove(objectPaths);
    developer.log('removed ${objectPaths.length} object(s)', name: 'storage');
  }

  /// Deletes every document row belonging to the signed-in user. RLS already
  /// scopes this to their own rows; the explicit filter satisfies Supabase's
  /// "delete needs a filter" guard.
  Future<void> deleteAllRowsForUser() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    await _client.from(_table).delete().eq('auth_user_id', userId);
    _bump();
  }

  /// Uploads arbitrary bytes to an object path (used for JSON cloud backups).
  /// Overwrites any existing object at that path.
  Future<void> uploadBytes(
    String objectPath,
    Uint8List bytes, {
    String contentType = 'application/octet-stream',
  }) async {
    await _client.storage.from(_bucket).uploadBinary(
          objectPath,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );
    developer.log('uploaded ${bytes.length}B to $objectPath', name: 'storage');
  }

  String _dateOnly(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
