import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// The result of a preprocessing step: the output file path plus the produced
/// image's pixel dimensions and encoded file size — surfaced so the caller can
/// log exactly what each step produced (useful for diagnosing memory issues).
class ProcessedImage {
  const ProcessedImage({
    required this.path,
    required this.width,
    required this.height,
    required this.fileBytes,
  });
  final String path;
  final int width;
  final int height;
  final int fileBytes;
}

/// Image preprocessing for the scan flow.
///
/// **Memory safety is the priority here.** Full-resolution camera captures are
/// huge (a 12 MP photo decodes to ~48 MB of RGBA), and stacking several such
/// buffers plus an integral image on the UI isolate previously exhausted the
/// Dart heap and hard-crashed the app during OCR. Every heavy operation now:
///
///   1. **caps the longest side to [_kMaxDim]** so no buffer is oversized;
///   2. **runs in a short-lived background isolate** ([Isolate.run]) whose heap
///      is fully reclaimed when it exits — so the UI isolate never holds the big
///      buffers, and even an out-of-memory in the worker surfaces as a catchable
///      error instead of killing the whole app;
///   3. uses **typed lists** (`Uint8List` / `Int32List`) for the adaptive
///      threshold instead of 64-bit `List<int>` (≈8× smaller, overflow-safe at
///      the capped size).
class ImageEnhancer {
  ImageEnhancer._();

  /// Hard cap on the longest side of any processed image. 2000 px keeps small
  /// document text legible for ML Kit while bounding peak memory (~21 MB per
  /// RGBA buffer) and ML Kit's native bitmap allocation.
  static const int _kMaxDim = 2000;

  /// Upscale target (width) for the cropped "enhanced" candidate.
  static const int _kCandidateTargetWidth = 1600;

  // ─────────────────────────── Review-screen tools ───────────────────────────

  /// A lightweight "document" enhancement for the review screen: grayscale + a
  /// contrast/brightness lift. Runs in a background isolate so a large capture
  /// can't OOM the UI isolate. Returns a sibling file path, or the original on
  /// any failure.
  static Future<String> enhance(String path) =>
      Isolate.run(() => _enhanceSync(path));

  static Future<String> _enhanceSync(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      var im = img.decodeImage(bytes);
      if (im == null) return path;
      im = _capLongestSide(im, _kMaxDim);
      var out = img.grayscale(im);
      out = img.adjustColor(out, contrast: 1.18, brightness: 1.04);
      return _writeJpg(path, out, 'enhanced', 90);
    } catch (_) {
      return path;
    }
  }

  /// Bakes a real 90° clockwise rotation into the image (review Rotate tool).
  /// Runs in a background isolate. Returns the new path, or the original on
  /// failure.
  static Future<String> rotate90(String path) =>
      Isolate.run(() => _rotate90Sync(path));

  static Future<String> _rotate90Sync(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      var im = img.decodeImage(bytes);
      if (im == null) return path;
      im = _capLongestSide(im, _kMaxDim);
      final rotated =
          img.copyRotate(im, angle: 90, interpolation: img.Interpolation.cubic);
      return _writeJpg(path, rotated, 'rot', 95);
    } catch (_) {
      return path;
    }
  }

  // ─────────────────────────── OCR preprocessing ───────────────────────────

  /// Bakes EXIF orientation and caps the resolution, producing the canonical
  /// upright base every OCR pass is built from. Runs in a background isolate.
  static Future<ProcessedImage> bakeBase(String path) async {
    final r = await Isolate.run(() => _bakeBaseSync(path));
    return ProcessedImage(
        path: r.$1, width: r.$2, height: r.$3, fileBytes: r.$4);
  }

  /// (path, width, height, fileBytes)
  static Future<(String, int, int, int)> _bakeBaseSync(String path) async {
    final bytes = await File(path).readAsBytes();
    var im = img.decodeImage(bytes);
    if (im == null) return (path, 0, 0, bytes.length);
    im = img.bakeOrientation(im); // EXIF rotation correction
    im = _capLongestSide(im, _kMaxDim); // caps *longest* side, not just width
    final out = _outPath(path, 'base');
    final encoded = img.encodeJpg(im, quality: 90);
    await File(out).writeAsBytes(encoded);
    return (out, im.width, im.height, encoded.length);
  }

  /// Builds an OCR candidate from [basePath]: crop to the text region, deskew,
  /// upscale, grayscale/contrast/denoise/sharpen, and an optional adaptive
  /// threshold. Runs entirely in a background isolate — the heavy buffers live
  /// and die there, never on the UI isolate.
  static Future<ProcessedImage> buildCandidate(
    String basePath, {
    double? deskewDegrees,
    int? cropX,
    int? cropY,
    int? cropW,
    int? cropH,
    bool binarize = false,
    int targetWidth = _kCandidateTargetWidth,
  }) async {
    final r = await Isolate.run(() => _buildCandidateSync(
          basePath,
          deskewDegrees,
          cropX,
          cropY,
          cropW,
          cropH,
          binarize,
          targetWidth,
        ));
    return ProcessedImage(
        path: r.$1, width: r.$2, height: r.$3, fileBytes: r.$4);
  }

  static Future<(String, int, int, int)> _buildCandidateSync(
    String basePath,
    double? deskewDegrees,
    int? cropX,
    int? cropY,
    int? cropW,
    int? cropH,
    bool binarize,
    int targetWidth,
  ) async {
    final bytes = await File(basePath).readAsBytes();
    var im = img.decodeImage(bytes);
    if (im == null) return (basePath, 0, 0, bytes.length);

    // 1. Crop to the text region (guarded: skip tiny/degenerate rects).
    if (cropX != null &&
        cropY != null &&
        cropW != null &&
        cropH != null &&
        cropW > 48 &&
        cropH > 48) {
      im = img.copyCrop(im, x: cropX, y: cropY, width: cropW, height: cropH);
    }

    // 2. Deskew — only for a meaningful, plausible tilt.
    if (deskewDegrees != null &&
        deskewDegrees.abs() >= 1.0 &&
        deskewDegrees.abs() <= 30.0) {
      im = img.copyRotate(im,
          angle: -deskewDegrees, interpolation: img.Interpolation.cubic);
    }

    // 3. Upscale small captures so glyphs have more pixels…
    if (im.width < targetWidth && im.width > 0) {
      im = img.copyResize(im,
          width: targetWidth, interpolation: img.Interpolation.cubic);
    }
    // …but never exceed the memory cap.
    im = _capLongestSide(im, _kMaxDim);

    // 4. Grayscale + contrast + denoise + sharpen.
    var out = img.grayscale(im);
    out = img.adjustColor(out, contrast: 1.3, brightness: 1.03);
    out = img.gaussianBlur(out, radius: 1); // noise reduction
    out = img.convolution(
      out,
      filter: const [0, -1, 0, -1, 5, -1, 0, -1, 0], // unsharp 3×3
      div: 1,
    );

    // 5. Optional adaptive threshold (binarization).
    if (binarize) {
      out = _adaptiveThreshold(out);
    }

    final path = _outPath(basePath, binarize ? 'bin' : 'enh');
    final encoded = img.encodeJpg(out, quality: 90);
    await File(path).writeAsBytes(encoded);
    return (path, out.width, out.height, encoded.length);
  }

  /// Bradley–Roth adaptive threshold. Uses a `Uint8List` luminance buffer
  /// (1 byte/px) and an `Int32List` integral image (4 bytes/px) instead of two
  /// 64-bit `List<int>`s — roughly 6–8× less memory. At the capped resolution
  /// (≤ 2000 px longest side) the maximum integral sum (255 × w × h) stays below
  /// 2³¹, so `Int32List` cannot overflow.
  static img.Image _adaptiveThreshold(img.Image src,
      {int window = 25, double t = 0.15}) {
    final w = src.width;
    final h = src.height;
    if (w < 3 || h < 3) return src;
    final n = w * h;

    final lum = Uint8List(n);
    for (final p in src) {
      lum[p.y * w + p.x] = p.luminance.round().clamp(0, 255);
    }

    final integral = Int32List(n);
    for (var x = 0; x < w; x++) {
      var colSum = 0;
      for (var y = 0; y < h; y++) {
        colSum += lum[y * w + x];
        integral[y * w + x] = (x == 0 ? 0 : integral[y * w + x - 1]) + colSum;
      }
    }

    final half = window ~/ 2;
    for (final p in src) {
      final x = p.x;
      final y = p.y;
      final x1 = math.max(0, x - half);
      final y1 = math.max(0, y - half);
      final x2 = math.min(w - 1, x + half);
      final y2 = math.min(h - 1, y + half);
      final count = (x2 - x1 + 1) * (y2 - y1 + 1);
      final sum = integral[y2 * w + x2] -
          (x1 > 0 ? integral[y2 * w + x1 - 1] : 0) -
          (y1 > 0 ? integral[(y1 - 1) * w + x2] : 0) +
          (x1 > 0 && y1 > 0 ? integral[(y1 - 1) * w + x1 - 1] : 0);
      final threshold = (sum / count) * (1.0 - t);
      final v = lum[y * w + x] < threshold ? 0 : 255;
      p
        ..r = v
        ..g = v
        ..b = v;
    }
    return src;
  }

  // ─────────────────────────── helpers ───────────────────────────

  /// Downscales [im] so its longest side is at most [maxDim] (aspect preserved).
  /// This is the key memory guard — it bounds every downstream buffer.
  static img.Image _capLongestSide(img.Image im, int maxDim) {
    final longest = math.max(im.width, im.height);
    if (longest <= maxDim) return im;
    return im.width >= im.height
        ? img.copyResize(im,
            width: maxDim, interpolation: img.Interpolation.average)
        : img.copyResize(im,
            height: maxDim, interpolation: img.Interpolation.average);
  }

  static String _outPath(String srcPath, String tag) =>
      '${File(srcPath).parent.path}/ino_${tag}_${DateTime.now().microsecondsSinceEpoch}.jpg';

  static Future<String> _writeJpg(
      String srcPath, img.Image im, String tag, int quality) async {
    final out = _outPath(srcPath, tag);
    await File(out).writeAsBytes(img.encodeJpg(im, quality: quality));
    return out;
  }
}
