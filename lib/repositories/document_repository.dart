import 'dart:io';

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
    await _client.storage.from(_bucket).upload(objectPath, File(localPath));
    return objectPath;
  }

  /// A temporary, signed URL for viewing a stored file (private bucket).
  Future<String> signedUrl(String objectPath, {int expiresInSeconds = 3600}) {
    return _client.storage.from(_bucket).createSignedUrl(objectPath, expiresInSeconds);
  }

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

  /// Deletes a document row by id.
  Future<void> delete(String id) async {
    await _client.from(_table).delete().eq('id', id);
  }

  String _dateOnly(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
