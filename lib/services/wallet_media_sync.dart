import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../repositories/document_repository.dart';

/// Keeps wallet-record media — a property's photo, a deed, an investment
/// statement — in Supabase Storage instead of only on the phone.
///
/// **The bug this exists to fix.** The property and investment forms saved
/// whatever path the gallery/file picker handed back:
/// `/data/user/0/com.ino/cache/image_picker_1757.jpg`. That string was written
/// to `w_property_wallet.image_path` and into the `attachments` jsonb and it
/// synced perfectly — but it names a file on ONE device, inside a cache
/// directory the OS is free to empty. So the row survived a reinstall and the
/// picture did not, and on a second device every property showed the fallback
/// tile. The record looked saved because the text round-tripped; the content
/// was never uploaded at all.
///
/// Everything here is therefore about one question: is this path a local file
/// that still needs uploading, or an object already in the bucket?
///
/// Uploads go to the same `documents` bucket and the same `<uid>/<ts>.<ext>`
/// layout as wallet documents, so the storage RLS policies, the quota check and
/// the Family Vault's share policy all apply unchanged.
class WalletMediaSync {
  WalletMediaSync._();
  static final WalletMediaSync instance = WalletMediaSync._();

  final _docs = DocumentRepository.instance;

  /// `<uuid>/<something>` — the shape [DocumentRepository.uploadFile] returns.
  static final RegExp _objectPath = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+$',
  );

  /// True when [path] names an object in the bucket rather than a device file.
  static bool isRemote(String? path) {
    final p = path?.trim();
    if (p == null || p.isEmpty) return false;
    if (p.startsWith('http://') || p.startsWith('https://')) return true;
    final clean = p.startsWith('documents/') ? p.substring('documents/'.length) : p;
    return _objectPath.hasMatch(clean);
  }

  /// True when [path] is a file that still exists on this device.
  static bool isLocalFile(String? path) {
    final p = path?.trim();
    if (p == null || p.isEmpty || isRemote(p)) return false;
    try {
      return File(p).existsSync();
    } catch (_) {
      return false;
    }
  }

  /// Uploads [path] if it is still a local file and returns the object path to
  /// store on the record. Anything already remote is returned untouched.
  ///
  /// Returns the ORIGINAL path on failure rather than throwing. A failed upload
  /// must not cost the user the property they just filled in — the row still
  /// saves with the local path, exactly as it behaved before, and the next edit
  /// retries. The one thing it must never do is silently drop the reference.
  Future<String?> ensureUploaded(String? path) async {
    final p = path?.trim();
    if (p == null || p.isEmpty) return null;
    if (isRemote(p)) return p;
    if (!isLocalFile(p)) {
      // Neither an object nor a file that exists: a stale path from a previous
      // install. Keep it — the UI already renders a fallback for it, and
      // blanking it would destroy the only record of what was attached.
      return p;
    }
    try {
      final objectPath = await _docs.uploadFile(p);
      // Seed the download cache with the copy we already have, so the very
      // next render is instant instead of a round trip for bytes that are
      // sitting right here.
      unawaited(_seedCache(objectPath, File(p)));
      developer.log('wallet media uploaded: $p -> $objectPath', name: 'wallet');
      return objectPath;
    } catch (e) {
      developer.log('wallet media upload failed for $p: $e', name: 'wallet');
      return p;
    }
  }

  /// [ensureUploaded] for a list, preserving order. Uploads run sequentially on
  /// purpose: a property can carry a dozen attachments and firing a dozen
  /// concurrent multipart uploads from a phone on mobile data is how you get
  /// timeouts on all of them instead of progress on one.
  Future<List<String?>> ensureAllUploaded(Iterable<String?> paths) async {
    final out = <String?>[];
    for (final p in paths) {
      out.add(await ensureUploaded(p));
    }
    return out;
  }

  // ---- Reading back ---------------------------------------------------------

  Directory? _cacheDir;
  final Map<String, Future<File?>> _inFlight = {};

  Future<Directory> _dir() async {
    final cached = _cacheDir;
    if (cached != null) return cached;
    final base = await getTemporaryDirectory();
    final dir = Directory('${base.path}/wallet_media');
    if (!await dir.exists()) await dir.create(recursive: true);
    _cacheDir = dir;
    return dir;
  }

  String _cacheName(String objectPath) =>
      objectPath.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');

  Future<void> _seedCache(String objectPath, File source) async {
    try {
      final dest = File('${(await _dir()).path}/${_cacheName(objectPath)}');
      if (!await dest.exists()) await source.copy(dest.path);
    } catch (_) {
      // Purely an optimisation; a miss just means one download.
    }
  }

  /// The bytes of [path] as a local file, downloading and caching them when the
  /// path names a storage object. Null when there is nothing to show.
  ///
  /// Concurrent calls for the same object share one download — a grid of
  /// thumbnails mounts many tiles at once, and without this each one starts its
  /// own request for the same file.
  Future<File?> resolve(String? path) {
    final p = path?.trim();
    if (p == null || p.isEmpty) return Future.value(null);
    if (!isRemote(p)) {
      try {
        final f = File(p);
        return Future.value(f.existsSync() ? f : null);
      } catch (_) {
        return Future.value(null);
      }
    }
    final existing = _inFlight[p];
    if (existing != null) return existing;
    final future = _download(p).whenComplete(() => _inFlight.remove(p));
    _inFlight[p] = future;
    return future;
  }

  Future<File?> _download(String objectPath) async {
    try {
      final dest = File('${(await _dir()).path}/${_cacheName(objectPath)}');
      if (await dest.exists() && await dest.length() > 0) return dest;
      await _docs.downloadToFile(objectPath, dest);
      return await dest.exists() ? dest : null;
    } catch (e) {
      developer.log('wallet media download failed for $objectPath: $e',
          name: 'wallet');
      return null;
    }
  }

  /// Drops the on-disk cache (sign-out).
  Future<void> clearCache() async {
    try {
      final dir = _cacheDir ?? Directory('${(await getTemporaryDirectory()).path}/wallet_media');
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {
      // Best-effort.
    }
    _cacheDir = null;
    _inFlight.clear();
  }
}
