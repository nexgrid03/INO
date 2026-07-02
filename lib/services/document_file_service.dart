import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../repositories/document_repository.dart';

/// Downloads document files from Storage and caches them on disk (temp dir), so
/// recently viewed / shared / opened files aren't re-fetched. Keyed by the
/// Storage object path, so a fresh signed URL isn't needed each time and the
/// file works offline after the first view.
class DocumentFileService {
  DocumentFileService._();
  static final DocumentFileService instance = DocumentFileService._();

  Directory? _dir;

  Future<Directory> _cacheDir() async {
    final existing = _dir;
    if (existing != null) return existing;
    final tmp = await getTemporaryDirectory();
    final dir = Directory('${tmp.path}/ino_documents');
    if (!await dir.exists()) await dir.create(recursive: true);
    _dir = dir;
    return dir;
  }

  static String extensionOf(String objectPath) =>
      objectPath.contains('.') ? objectPath.split('.').last.toLowerCase() : 'bin';

  String _cacheKey(String objectPath) {
    final key = objectPath.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    return '$key.${extensionOf(objectPath)}';
  }

  /// Returns a local [File] for [objectPath], downloading + caching if needed.
  /// Throws if the object no longer exists / the download fails (the viewer
  /// turns that into a friendly error).
  Future<File> ensureLocal(String objectPath) async {
    final dir = await _cacheDir();
    final file = File('${dir.path}/${_cacheKey(objectPath)}');
    if (await file.exists() && await file.length() > 0) return file;
    final bytes = await DocumentRepository.instance.download(objectPath);
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// A copy of [source] named with the real document name (nice for Share /
  /// Download so the file isn't the opaque storage key).
  Future<File> namedCopy(
      File source, String displayName, String objectPath) async {
    final safe =
        displayName.replaceAll(RegExp(r'[^a-zA-Z0-9 ._-]'), '').trim();
    final base = safe.isEmpty ? 'document' : safe;
    final dir = await _cacheDir();
    final target = File('${dir.path}/$base.${extensionOf(objectPath)}');
    await source.copy(target.path);
    return target;
  }
}
