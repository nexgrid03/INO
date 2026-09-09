import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:image/image.dart' as img;
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
    // Streamed straight to disk in chunks. The destination is a file, so there
    // is no reason to materialise a 50 MB PDF as a Uint8List first - that peak
    // is what turns "open a few big documents" into an OOM under stress.
    // downloadToFile also deletes a half-written file when a transfer fails, so
    // the `length > 0` check above can never hand back a truncated cache entry.
    await DocumentRepository.instance.downloadToFile(objectPath, file);
    return file;
  }

  /// Optimizes a local image (caps dimension to 2048px and compresses to quality 85)
  /// in a background isolate to make network upload fast.
  Future<String> optimizeForUpload(String localPath) async {
    final ext = extensionOf(localPath);
    if (!const ['jpg', 'jpeg', 'png', 'webp', 'bmp'].contains(ext)) {
      return localPath;
    }
    final file = File(localPath);
    if (!await file.exists()) return localPath;
    final length = await file.length();
    // If already small (< 500 KB), no need to compress further
    if (length < 500 * 1024) return localPath;

    try {
      final outPath = await Isolate.run(() => _compressImageSync(localPath));
      return outPath ?? localPath;
    } catch (_) {
      return localPath;
    }
  }

  static String? _compressImageSync(String srcPath) {
    try {
      final bytes = File(srcPath).readAsBytesSync();
      var image = img.decodeImage(bytes);
      if (image == null) return null;
      image = img.bakeOrientation(image);
      const maxDim = 2048;
      final longest = math.max(image.width, image.height);
      if (longest > maxDim) {
        image = image.width >= image.height
            ? img.copyResize(image,
                width: maxDim, interpolation: img.Interpolation.linear)
            : img.copyResize(image,
                height: maxDim, interpolation: img.Interpolation.linear);
      }
      final dir = File(srcPath).parent.path;
      final outPath =
          '$dir/ino_upload_${DateTime.now().microsecondsSinceEpoch}.jpg';
      final jpgBytes = img.encodeJpg(image, quality: 85);
      File(outPath).writeAsBytesSync(jpgBytes);
      return outPath;
    } catch (_) {
      return null;
    }
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

  /// Purges all temporary document cache files on sign-out.
  Future<void> clearCache() async {
    try {
      final dir = await _cacheDir();
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
      _dir = null;
    } catch (_) {}
  }
}

