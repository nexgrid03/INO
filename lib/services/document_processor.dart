import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/share_settings.dart';
import 'image_enhancer.dart';

/// The output of [DocumentProcessor.process]: a temporary processed copy of a
/// document, ready to share.
class ProcessedShareFile {
  const ProcessedShareFile({required this.path, required this.isPdf});

  final String path;
  final bool isPdf;
}

/// Thrown when a processed copy could not be produced (so the caller never
/// silently falls back to sharing the untouched original).
class DocumentProcessException implements Exception {
  const DocumentProcessException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Produces a PROCESSED TEMPORARY COPY of a document for sharing — the chosen
/// copy style (Original / Black & White / Grayscale / Compressed PDF) — without
/// ever touching the original stored file.
///
/// Images are transformed pixel-by-pixel in a background isolate (mirroring
/// [ImageEnhancer]'s memory discipline). PDFs cannot be pixel-processed with the
/// current toolchain, so they are copied as-is (the Share Settings screen
/// disables the pixel options for PDFs).
class DocumentProcessor {
  DocumentProcessor._();
  static final DocumentProcessor instance = DocumentProcessor._();

  static const int _maxDim = 2000;

  /// Builds a processed copy of [sourcePath] per [settings]. Throws
  /// [DocumentProcessException] on failure.
  Future<ProcessedShareFile> process({
    required String sourcePath,
    required bool sourceIsPdf,
    required ShareSettings settings,
  }) async {
    // PDFs: no pixel processing available — hand back a plain temp copy. (The
    // Share Settings screen disables the colour options for PDFs, so nothing is
    // silently dropped here.)
    if (sourceIsPdf) {
      final out = await _tempPath('pdf');
      await File(sourcePath).copy(out);
      return ProcessedShareFile(path: out, isPdf: true);
    }

    // Original Color → a plain copy of the original image (no pixel change).
    if (!settings.requiresImageProcessing) {
      final ext = _extOf(sourcePath, fallback: 'jpg');
      final out = await _tempPath(ext);
      await File(sourcePath).copy(out);
      return ProcessedShareFile(path: out, isPdf: false);
    }

    // 1) Bake EXIF orientation + cap resolution to a clean upright base.
    final ProcessedImage base;
    try {
      base = await ImageEnhancer.bakeBase(sourcePath);
    } catch (_) {
      throw const DocumentProcessException(
          'Could not read the document image to process it.');
    }
    final bakedBytes = await File(base.path).readAsBytes();

    // 2) Pixel transforms (colour mode + optional compression) in a background
    //    isolate.
    final colorIdx = settings.colorMode.index;
    final compress = settings.colorMode == ShareColorMode.compressedPdf;
    Uint8List processed;
    try {
      processed = await Isolate.run(
          () => _processImageSync(bakedBytes, colorIdx, compress));
    } catch (_) {
      throw const DocumentProcessException(
          'Could not generate the processed copy.');
    }

    // 3) Wrap into a compressed PDF, or write the JPEG.
    if (settings.wrapsInPdf) {
      final pdfBytes = await _wrapJpegInPdf(processed);
      final out = await _tempPath('pdf');
      await File(out).writeAsBytes(pdfBytes);
      return ProcessedShareFile(path: out, isPdf: true);
    }
    final out = await _tempPath('jpg');
    await File(out).writeAsBytes(processed);
    return ProcessedShareFile(path: out, isPdf: false);
  }

  // ---- Isolate: pixel transforms -------------------------------------------

  /// Runs (optional downscale →) colour mode → encode, entirely in a background
  /// isolate. Throws if the image can't be decoded.
  static Uint8List _processImageSync(
    Uint8List bytes,
    int colorIdx,
    bool compress,
  ) {
    var im = img.decodeImage(bytes);
    if (im == null) {
      throw const DocumentProcessException('Unreadable image.');
    }

    // 1) Downscale (compress mode goes smaller; others just honour the cap).
    if (compress) {
      final longest = math.max(im.width, im.height);
      if (longest > 1400) {
        im = im.width >= im.height
            ? img.copyResize(im, width: 1400)
            : img.copyResize(im, height: 1400);
      }
    } else {
      final longest = math.max(im.width, im.height);
      if (longest > _maxDim) {
        im = im.width >= im.height
            ? img.copyResize(im, width: _maxDim)
            : img.copyResize(im, height: _maxDim);
      }
    }

    // 2) Colour mode. (index: 0 original, 1 b&w, 2 grayscale, 3 compressedPdf)
    if (colorIdx == ShareColorMode.grayscale.index ||
        colorIdx == ShareColorMode.compressedPdf.index) {
      // A clean, readable grayscale scan: normalize contrast + a small
      // brightness lift so the page reads like a photocopy rather than a dim
      // photo.
      im = img.grayscale(im);
      im = img.normalize(im, min: 0, max: 255);
      im = img.adjustColor(im, contrast: 1.08, brightness: 1.03);
    } else if (colorIdx == ShareColorMode.blackWhite.index) {
      im = _scanBinarize(im);
    }

    final quality = compress ? 42 : 88;
    return img.encodeJpg(im, quality: quality);
  }

  // ---- Document-grade black & white ----------------------------------------

  /// Turns a photo of a document into a crisp, printer-friendly "scan" — the
  /// look Adobe Scan / Microsoft Lens / CamScanner produce — instead of a harsh
  /// global threshold that crushes shadows into black blobs and drops faint text.
  ///
  /// Pipeline: grayscale → contrast normalization + brightness balance → light
  /// Gaussian denoise → LOCAL adaptive threshold. The adaptive step compares each
  /// pixel to the mean of its neighbourhood, so uneven lighting and shadows no
  /// longer swallow the text — edges stay sharp and small print stays legible.
  static img.Image _scanBinarize(img.Image src) {
    var im = img.grayscale(src);
    // Stretch the tonal range, then a gentle contrast/brightness lift so faint
    // ink separates cleanly from the paper before thresholding.
    im = img.normalize(im, min: 0, max: 255);
    im = img.adjustColor(im, contrast: 1.15, brightness: 1.05);
    // Light denoise so paper grain / JPEG noise doesn't speckle the result.
    im = img.gaussianBlur(im, radius: 1);
    return _adaptiveThreshold(im);
  }

  /// Bradley–Roth adaptive (local mean) threshold. Uses a `Uint8List` luminance
  /// buffer + an `Int32List` integral image (≈6–8× less memory than 64-bit
  /// lists; overflow-safe at the ≤2000 px cap). The window scales with the image
  /// so the neighbourhood is document-appropriate at any resolution.
  static img.Image _adaptiveThreshold(img.Image src, {double t = 0.15}) {
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

    // ~8% of the shorter side (odd, clamped) — big enough to span a glyph's
    // neighbourhood, small enough to track local lighting.
    var window = (math.min(w, h) * 0.08).round();
    if (window < 15) window = 15;
    if (window > 51) window = 51;
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

  // ---- PDF wrap -------------------------------------------------------------

  Future<Uint8List> _wrapJpegInPdf(Uint8List jpeg) async {
    final doc = pw.Document();
    final image = pw.MemoryImage(jpeg);
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(16),
        build: (context) => pw.Center(
          child: pw.Image(image, fit: pw.BoxFit.contain),
        ),
      ),
    );
    return doc.save();
  }

  // ---- Helpers --------------------------------------------------------------

  Future<String> _tempPath(String ext) async {
    final dir = await getTemporaryDirectory();
    final micros = DateTime.now().microsecondsSinceEpoch;
    return '${dir.path}/ino_share_$micros.$ext';
  }

  String _extOf(String path, {required String fallback}) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return fallback;
    final ext = path.substring(dot + 1).toLowerCase();
    return ext.length <= 5 ? ext : fallback;
  }
}
