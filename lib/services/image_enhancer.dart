import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// The copy style a scanned page can be saved in (the WhatsApp / Adobe Scan
/// filter set). [ImageEnhancer.applyColorMode] renders each of these.
enum ScanColorMode { original, enhanced, blackWhite, grayscale }

extension ScanColorModeX on ScanColorMode {
  /// Localization key for the mode's chip label.
  String get labelKey => switch (this) {
        ScanColorMode.original => 'original',
        ScanColorMode.enhanced => 'enhance',
        ScanColorMode.blackWhite => 'blackWhite',
        ScanColorMode.grayscale => 'grayscale',
      };
}

/// The result of a preprocessing step: the output file path plus the produced
/// image's pixel dimensions and encoded file size - surfaced so the caller can
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
///      is fully reclaimed when it exits - so the UI isolate never holds the big
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

  /// Interpolation used to deskew an OCR candidate.
  ///
  /// This is the single biggest performance lever in the pipeline - see the
  /// measured comparison in [_buildCandidateSync]. If a recognition regression
  /// is ever traced to deskewed captures, changing this one value back to
  /// [img.Interpolation.cubic] restores the previous behaviour exactly, at a
  /// cost of roughly 2.7 seconds per candidate build.
  ///
  /// Applies to the OCR path only. The user-facing Rotate tool ([rotate90])
  /// deliberately keeps cubic: that output is what the user actually looks at.
  static const img.Interpolation kDeskewInterpolation =
      img.Interpolation.linear;

  /// Interpolation used to upscale a small OCR candidate.
  ///
  /// The most expensive single operation in the pipeline before this was
  /// changed - see the measured comparison in [_buildCandidateSync]. Revert to
  /// [img.Interpolation.cubic] to restore the previous behaviour exactly, at a
  /// cost of roughly 3.7 seconds per candidate build.
  static const img.Interpolation kUpscaleInterpolation =
      img.Interpolation.linear;

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
      return await _writeJpg(path, out, 'enhanced', 90);
    } catch (_) {
      return path;
    }
  }

  /// Renders [path] in the given copy [mode] - the document-grade processing
  /// set shared with the share pipeline (see [DocumentProcessor]):
  ///
  ///  • **original**   - untouched, returns [path] as-is;
  ///  • **enhanced**   - colour kept: tonal normalization (auto brightness /
  ///    contrast / shadow lift) + a gentle sharpen;
  ///  • **grayscale**  - photocopy-clean grayscale (normalize + small lift);
  ///  • **blackWhite** - crisp scanner-style B&W via contrast normalization,
  ///    brightness balancing, denoise and a LOCAL (Bradley–Roth) adaptive
  ///    threshold, so shadows never crush text into black blobs.
  ///
  /// Runs in a background isolate. Returns a sibling file path, or the
  /// original path on any failure.
  static Future<String> applyColorMode(String path, ScanColorMode mode) {
    if (mode == ScanColorMode.original) return Future.value(path);
    return Isolate.run(() => _applyColorModeSync(path, mode.index));
  }

  static Future<String> _applyColorModeSync(String path, int modeIdx) async {
    try {
      final bytes = await File(path).readAsBytes();
      var im = img.decodeImage(bytes);
      if (im == null) return path;
      im = _capLongestSide(im, _kMaxDim);
      final img.Image out;
      if (modeIdx == ScanColorMode.blackWhite.index) {
        out = scanBinarize(im);
      } else if (modeIdx == ScanColorMode.grayscale.index) {
        out = documentGrayscale(im);
      } else {
        // Enhanced: keep colour; normalize tone, lift shadows, light sharpen.
        var e = img.normalize(im, min: 0, max: 255);
        e = img.adjustColor(e, contrast: 1.10, brightness: 1.04);
        e = img.convolution(
          e,
          filter: const [0, -1, 0, -1, 6, -1, 0, -1, 0], // gentle unsharp
          div: 2,
        );
        out = e;
      }
      return await _writeJpg(
          path, out, ScanColorMode.values[modeIdx].name, 90);
    } catch (_) {
      return path;
    }
  }

  /// Downscales (≤[_kMaxDim]) and re-encodes [path] as a compact JPEG suitable
  /// for embedding in a PDF page. Returns the optimized sibling path, or the
  /// original on failure. Runs in a background isolate.
  static Future<String> optimizeForPdf(String path) =>
      Isolate.run(() => _optimizeForPdfSync(path));

  static Future<String> _optimizeForPdfSync(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      var im = img.decodeImage(bytes);
      if (im == null) return path;
      im = img.bakeOrientation(im);
      im = _capLongestSide(im, _kMaxDim);
      return await _writeJpg(path, im, 'pdfpage', 86);
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
      return await _writeJpg(path, rotated, 'rot', 95);
    } catch (_) {
      return path;
    }
  }

  // ─────────────────────────── OCR preprocessing ───────────────────────────

  /// Bakes EXIF orientation and caps the resolution, producing the canonical
  /// upright base every OCR pass is built from. Runs in a background isolate.
  ///
  /// [maxDim] / [quality] default to the ID-document settings (2000 px, q90).
  /// The receipt/plain-text path passes a smaller, more compressed target
  /// ([kTextMaxDim] / [kTextQuality]) - a receipt only needs enough pixels for
  /// the recognizer, so a smaller JPEG means a faster decode here AND a faster
  /// ML Kit pass downstream (the single biggest OCR win).
  static Future<ProcessedImage> bakeBase(
    String path, {
    int maxDim = _kMaxDim,
    int quality = 90,
  }) async {
    final r = await Isolate.run(() => _bakeBaseSync(path, maxDim, quality));
    return ProcessedImage(
        path: r.$1, width: r.$2, height: r.$3, fileBytes: r.$4);
  }

  /// Downscale target for the receipt/plain-text OCR path (max longest side).
  static const int kTextMaxDim = 1600;

  /// JPEG quality for the receipt/plain-text OCR path.
  static const int kTextQuality = 70;

  /// (path, width, height, fileBytes)
  static Future<(String, int, int, int)> _bakeBaseSync(
      String path, int maxDim, int quality) async {
    final bytes = await File(path).readAsBytes();
    var im = img.decodeImage(bytes);
    if (im == null) return (path, 0, 0, bytes.length);
    im = img.bakeOrientation(im); // EXIF rotation correction
    im = _capLongestSide(im, maxDim); // caps *longest* side, not just width
    final out = _outPath(path, 'base');
    final encoded = img.encodeJpg(im, quality: quality);
    await File(out).writeAsBytes(encoded);
    return (out, im.width, im.height, encoded.length);
  }

  /// Builds an OCR candidate from [basePath]: crop to the text region, deskew,
  /// upscale, grayscale/contrast/denoise/sharpen, and an optional adaptive
  /// threshold. Runs entirely in a background isolate - the heavy buffers live
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

    // 2. Deskew - only for a meaningful, plausible tilt.
    //
    // Interpolation is LINEAR, not cubic, and that single choice is the largest
    // performance factor in the whole OCR pipeline. Measured on a 2000x1500
    // base (test/ocr_substep_bench_test.dart):
    //
    //     cubic    3253 ms   <- 61% of the entire enhanced pass
    //     linear    506 ms
    //     nearest   107 ms
    //
    // Cubic samples 16 neighbours per output pixel, linear 4. On document text
    // that has already been through a q90 JPEG encode and is about to be
    // unsharp-masked in step 4, the extra taps buy no recognisable detail - but
    // they cost ~2.7 seconds on every candidate build. Nearest is rejected: it
    // aliases glyph edges badly enough to actually hurt recognition.
    if (deskewDegrees != null &&
        deskewDegrees.abs() >= 1.0 &&
        deskewDegrees.abs() <= 30.0) {
      im = img.copyRotate(im,
          angle: -deskewDegrees, interpolation: kDeskewInterpolation);
    }

    // 3. Upscale small captures so glyphs have more pixels…
    //
    // This is the single most expensive operation in the pipeline, and it fires
    // on nearly every run: a portrait phone capture bakes down to ~1500x2000,
    // which is under [targetWidth], so the upscale happens whether or not the
    // capture is skewed. Measured on exactly that shape:
    //
    //     cubic     3960 ms   <- the bulk of the whole enhanced pass
    //     linear     223 ms
    //
    // Cubic is 17x the cost for an upscale of about 7%. Bicubic's advantage is
    // smoother gradients on large magnifications; over this ratio, on text that
    // is unsharp-masked two lines below, it buys nothing a recognizer can use.
    // (Interpolation.average is deliberately not used here - it is a box filter
    // meant for DOWNscaling and would soften glyph edges.)
    if (im.width < targetWidth && im.width > 0) {
      im = img.copyResize(im,
          width: targetWidth, interpolation: kUpscaleInterpolation);
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

  // ───────────────────── Document-grade colour modes (shared) ─────────────────────
  // These are the single source of truth for "scan look" processing, used by
  // BOTH the scan review copy modes and the share pipeline (DocumentProcessor).

  /// A clean, readable grayscale scan: normalize contrast + a small brightness
  /// lift so the page reads like a photocopy rather than a dim photo.
  static img.Image documentGrayscale(img.Image src) {
    var im = img.grayscale(src);
    im = img.normalize(im, min: 0, max: 255);
    return img.adjustColor(im, contrast: 1.08, brightness: 1.03);
  }

  /// Turns a photo of a document into a crisp, printer-friendly "scan" - the
  /// look Adobe Scan / Microsoft Lens / CamScanner produce - instead of a harsh
  /// global threshold that crushes shadows into black blobs and drops faint
  /// text.
  ///
  /// Pipeline: grayscale → contrast normalization + brightness balance → light
  /// Gaussian denoise → LOCAL (Bradley–Roth) adaptive threshold whose window
  /// scales with the image. The adaptive step compares each pixel to the mean
  /// of its neighbourhood, so uneven lighting and shadows no longer swallow the
  /// text - edges stay sharp and small print stays legible.
  static img.Image scanBinarize(img.Image src) {
    var im = img.grayscale(src);
    // Stretch the tonal range, then a gentle contrast/brightness lift so faint
    // ink separates cleanly from the paper before thresholding.
    im = img.normalize(im, min: 0, max: 255);
    im = img.adjustColor(im, contrast: 1.15, brightness: 1.05);
    // Light denoise so paper grain / JPEG noise doesn't speckle the result.
    im = img.gaussianBlur(im, radius: 1);
    return adaptiveThresholdScaled(im);
  }

  /// The share pipeline's Black & White: the scan look, minus the flood.
  ///
  /// [scanBinarize] is right for the scanner - its output feeds OCR and print -
  /// but shared IDs and receipts often carry photos, seals and tinted panels
  /// that a hard threshold crushes into solid black, so shared copies read far
  /// too dark. Here the threshold only decides what counts as paper: paper goes
  /// clean white, and everything else keeps its grayscale detail, gently
  /// deepened so text still reads as ink.
  static img.Image shareBlackWhite(img.Image src) {
    // Explicit copy first: the filters underneath both helpers mutate their
    // input in place, so without it the detail layer and the mask would end up
    // being the same binarized image.
    final gray = documentGrayscale(img.Image.from(src));
    final mask = scanBinarize(src);
    for (final p in gray) {
      if (mask.getPixel(p.x, p.y).r > 127) {
        p
          ..r = 255
          ..g = 255
          ..b = 255;
      } else {
        // 70% of the grayscale value: dark enough to read as ink, light
        // enough that photos and shading keep their detail.
        final v = (p.r * 0.7).round();
        p
          ..r = v
          ..g = v
          ..b = v;
      }
    }
    return gray;
  }

  /// Bradley–Roth adaptive threshold with an image-scaled window: ~8% of the
  /// shorter side (odd, clamped 15–51) - big enough to span a glyph's
  /// neighbourhood, small enough to track local lighting.
  static img.Image adaptiveThresholdScaled(img.Image src, {double t = 0.15}) {
    var window = (math.min(src.width, src.height) * 0.08).round();
    if (window < 15) window = 15;
    if (window > 51) window = 51;
    return _adaptiveThreshold(src, window: window, t: t);
  }

  /// Bradley–Roth adaptive threshold. Uses a `Uint8List` luminance buffer
  /// (1 byte/px) and an `Int32List` integral image (4 bytes/px) instead of two
  /// 64-bit `List<int>`s - roughly 6–8× less memory. At the capped resolution
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
  /// This is the key memory guard - it bounds every downstream buffer.
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
