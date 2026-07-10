import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/share_config.dart';
import '../models/document_share.dart';
import '../models/public_share.dart';

/// A user-facing failure in the sharing flow. [message] is safe to show in a
/// snackbar; [cause] carries the underlying error for logs.
class ShareException implements Exception {
  const ShareException(this.message, {this.cause});
  final String message;
  final Object? cause;
  @override
  String toString() => 'ShareException: $message';
}

/// Thrown when the sharing backend hasn't been deployed to Supabase yet — i.e.
/// the `create_document_share` RPC / `document_shares` table are missing.
/// Surfaced to the user as "QR Sharing Backend Not Configured" instead of a
/// generic failure, so the fix (deploy the migration + Edge Function) is clear.
class ShareBackendNotConfiguredException extends ShareException {
  const ShareBackendNotConfiguredException([Object? cause])
      : super('QR Sharing Backend Not Configured', cause: cause);
}

/// The ONLY place in the app that reads/writes the `document_shares` table.
///
/// Mirrors [DocumentRepository]'s design: a singleton over `Supabase.instance`,
/// with RLS scoping every query to the signed-in owner. Creation goes through
/// the `create_document_share` RPC, which server-side verifies that every
/// document actually belongs to the caller before minting the share — so the
/// client can never share an id it doesn't own.
///
/// The *public* side (anonymous recipients scanning the QR) never touches this
/// repository at all: that is served entirely by the `share` Edge Function.
class ShareRepository {
  ShareRepository._();
  static final ShareRepository instance = ShareRepository._();

  SupabaseClient get _client => Supabase.instance.client;

  static const String _table = 'document_shares';

  /// The signed-in owner's id, or null when signed out.
  String? get _uid => _client.auth.currentUser?.id;

  /// Bumped whenever a share is created or revoked, so any open list can
  /// refresh itself without polling.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  static void _bump() => revision.value++;

  /// Creates a share for [documentIds] that expires after [duration], and
  /// returns the new [DocumentShare] (with its `share_id` and `expires_at`).
  ///
  /// Throws:
  ///   • [ShareException] when signed out / nothing selected, or when the RPC
  ///     rejects the request (the exact Postgres message is preserved);
  ///   • [ShareBackendNotConfiguredException] when the `create_document_share`
  ///     RPC is missing (the migration hasn't been deployed).
  /// Never throws a raw Supabase error to the UI.
  Future<DocumentShare> createShare({
    required List<String> documentIds,
    required ShareDuration duration,
  }) async {
    if (_client.auth.currentUser == null) {
      throw const ShareException('You must be signed in to share documents.');
    }
    if (documentIds.isEmpty) {
      throw const ShareException('Select at least one document to share.');
    }

    final payload = <String, dynamic>{
      'p_document_ids': documentIds,
      'p_ttl_seconds': duration.seconds,
    };
    developer.log(
      'RPC create_document_share → REQUEST\n'
      '  documentIds (${documentIds.length}): $documentIds\n'
      '  duration: ${duration.label} (${duration.seconds}s)\n'
      '  payload: $payload',
      name: 'share',
    );

    try {
      final row =
          await _client.rpc('create_document_share', params: payload);
      developer.log('RPC create_document_share → RESPONSE: $row', name: 'share');

      // The RPC returns the inserted row (a JSON object, or a 1-element list).
      final map = (row is List ? (row.isEmpty ? null : row.first) : row)
          as Map<String, dynamic>?;
      if (map == null) {
        throw const ShareException(
            'The server did not return a share. Please try again.');
      }
      final share = DocumentShare.fromMap(map);
      developer.log(
        'create_document_share OK → id=${share.shareId} url=${share.url} '
        'expires=${share.expiresAt.toIso8601String()}',
        name: 'share',
      );
      _bump();
      return share;
    } on PostgrestException catch (e, st) {
      developer.log(
        'RPC create_document_share FAILED → '
        'code=${e.code} message="${e.message}" details=${e.details} '
        'hint=${e.hint}',
        name: 'share',
        error: e,
        stackTrace: st,
      );
      if (_isMissingFunction(e)) {
        throw ShareBackendNotConfiguredException(e);
      }
      // Preserve the exact Postgres error (e.g. "One or more documents are not
      // yours to share", "Invalid expiry duration").
      throw ShareException(e.message, cause: e);
    } on AuthException catch (e, st) {
      developer.log('create_document_share auth error: ${e.message}',
          name: 'share', error: e, stackTrace: st);
      throw ShareException(e.message, cause: e);
    } catch (e, st) {
      developer.log('create_document_share unexpected error: $e',
          name: 'share', error: e, stackTrace: st);
      if (e is ShareException) rethrow;
      throw ShareException(
          'Could not generate the share. Please try again.', cause: e);
    }
  }

  /// PostgREST reports a missing RPC as PGRST202 ("Could not find the function
  /// … in the schema cache"). Used to distinguish "backend not deployed" from
  /// a genuine request rejection.
  bool _isMissingFunction(PostgrestException e) {
    if (e.code == 'PGRST202') return true;
    final m = e.message.toLowerCase();
    return m.contains('could not find the function') ||
        m.contains('create_document_share');
  }

  /// Every share the signed-in user has created, newest first.
  Future<List<DocumentShare>> listMyShares() async {
    final uid = _uid;
    if (uid == null) return const [];
    final rows = await _client
        .from(_table)
        .select()
        .eq('owner_id', uid) // defense-in-depth with the owner RLS policy
        .order('created_at', ascending: false);
    return [for (final r in rows) DocumentShare.fromMap(r)];
  }

  /// Re-fetches a single share (for up-to-date analytics / status).
  Future<DocumentShare?> fetch(String shareId) async {
    final uid = _uid;
    if (uid == null) return null;
    final row = await _client
        .from(_table)
        .select()
        .eq('share_id', shareId)
        .eq('owner_id', uid) // only the owner can read their own share
        .maybeSingle();
    return row == null ? null : DocumentShare.fromMap(row);
  }

  /// Revokes a share: all future scans become invalid immediately. RLS ensures
  /// a user can only revoke their own shares.
  Future<void> revoke(String shareId) async {
    developer.log('revoke → REQUEST share_id=$shareId', name: 'share');
    final uid = _uid;
    if (uid == null) {
      throw const ShareException('You must be signed in to revoke a share.');
    }
    try {
      await _client
          .from(_table)
          .update({'status': 'revoked'})
          .eq('share_id', shareId)
          .eq('owner_id', uid); // only the owner can revoke their own share
      developer.log('revoke OK → $shareId', name: 'share');
      _bump();
    } on PostgrestException catch (e, st) {
      developer.log(
        'revoke FAILED → code=${e.code} message="${e.message}"',
        name: 'share',
        error: e,
        stackTrace: st,
      );
      throw ShareException(e.message, cause: e);
    }
  }

  /// Permanently deletes a share row (and cascades its analytics).
  Future<void> delete(String shareId) async {
    final uid = _uid;
    if (uid == null) {
      throw const ShareException('You must be signed in to delete a share.');
    }
    await _client
        .from(_table)
        .delete()
        .eq('share_id', shareId)
        .eq('owner_id', uid); // only the owner can delete their own share
    _bump();
  }

  // ---- Public (recipient) side --------------------------------------------
  // These hit the anonymous `share` Edge Function over plain HTTP — recipients
  // have no Supabase session, and the private tables are never queried directly.

  /// Fetches the public metadata for [shareId] from the Edge Function. Returns a
  /// [PublicShare] whose [PublicShare.status] tells the viewer what to render
  /// (active / expired / revoked / notFound / error). Never throws — a network
  /// failure resolves to [PublicShare.errored].
  Future<PublicShare> fetchPublicShare(String token) async {
    final uri = Uri.parse('${ShareConfig.apiUrl(token)}?format=json');
    developer.log('fetchPublicShare → GET $uri', name: 'share');
    try {
      // Ask for JSON explicitly — the Edge Function content-negotiates and
      // returns the branded HTML page to browsers, JSON to the app.
      final res = await http.get(uri, headers: const {'accept': 'application/json'});
      developer.log(
        'fetchPublicShare ← ${res.statusCode} '
        '${res.body.length > 500 ? '${res.body.substring(0, 500)}…' : res.body}',
        name: 'share',
      );
      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) return PublicShare.errored;
      return PublicShare.fromJson(decoded);
    } catch (e, st) {
      developer.log('fetchPublicShare failed: $e',
          name: 'share', error: e, stackTrace: st);
      return PublicShare.errored;
    }
  }

  /// Downloads a shared document's bytes through the Edge Function proxy (so the
  /// storage path / signed URL are never exposed to the client). [download]
  /// selects the `download` disposition; `view` opens inline. Throws
  /// [ShareException] on any non-200 response.
  Future<SharedFile> fetchSharedFile(
    String token,
    SharedDoc doc, {
    required bool download,
  }) async {
    final uri = Uri.parse(
      '${ShareConfig.apiUrl(token)}/file/${doc.id}'
      '?mode=${download ? 'download' : 'view'}',
    );
    developer.log('fetchSharedFile → GET $uri', name: 'share');
    final res = await http.get(uri);
    developer.log(
      'fetchSharedFile ← ${res.statusCode} '
      'type=${res.headers['content-type']} bytes=${res.bodyBytes.length}',
      name: 'share',
    );
    if (res.statusCode != 200) {
      // The Edge Function returns a small JSON error body on failure.
      String message = 'Could not open this document.';
      try {
        final body = jsonDecode(res.body);
        if (body is Map && body['error'] is String) {
          message = body['error'] as String;
        } else if (body is Map && body['message'] is String) {
          message = body['message'] as String;
        }
      } catch (_) {/* non-JSON body — keep the default message */}
      throw ShareException(message);
    }
    final mime = res.headers['content-type'] ?? 'application/octet-stream';
    return SharedFile(
      bytes: res.bodyBytes,
      filename: _filenameFrom(res.headers['content-disposition'], doc, mime),
      mimeType: mime.split(';').first.trim(),
    );
  }

  /// Derives a safe local filename from the response's `content-disposition`
  /// header, falling back to the document name + an extension guessed from the
  /// MIME type.
  String _filenameFrom(String? disposition, SharedDoc doc, String mime) {
    if (disposition != null) {
      final m = RegExp('filename="?([^"]+)"?').firstMatch(disposition);
      final name = m?.group(1)?.trim();
      if (name != null && name.isNotEmpty) return _sanitize(name);
    }
    final base = _sanitize(doc.name);
    if (RegExp(r'\.[A-Za-z0-9]{1,5}$').hasMatch(base)) return base;
    return '$base${_extFromMime(mime)}';
  }

  String _sanitize(String name) =>
      name.replaceAll(RegExp(r'[\\/:*?"<>|\r\n]'), '_').trim();

  String _extFromMime(String mime) {
    if (mime.contains('pdf')) return '.pdf';
    if (mime.contains('png')) return '.png';
    if (mime.contains('jpeg') || mime.contains('jpg')) return '.jpg';
    if (mime.contains('webp')) return '.webp';
    if (mime.contains('heic')) return '.heic';
    return '';
  }
}
