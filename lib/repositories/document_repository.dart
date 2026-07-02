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
    final row = await _client
        .from(_table)
        .insert({
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
    final rows = await _client
        .from(_table)
        .select()
        .eq('wallet', wallet)
        .order('created_at', ascending: false);
    return [for (final r in rows) Document.fromMap(r)];
  }

  /// Every document belonging to the signed-in user, newest first.
  Future<List<Document>> listAll() async {
    final rows =
        await _client.from(_table).select().order('created_at', ascending: false);
    return [for (final r in rows) Document.fromMap(r)];
  }

  /// Updates a few columns on an existing row (e.g. favourite / status).
  /// RLS guarantees the user can only touch their own rows.
  Future<void> update(String id, Map<String, dynamic> fields) async {
    await _client.from(_table).update(fields).eq('id', id);
  }

  /// Deletes a document row by id.
  Future<void> delete(String id) async {
    await _client.from(_table).delete().eq('id', id);
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
