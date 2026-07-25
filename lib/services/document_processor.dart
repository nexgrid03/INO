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
    // Both looks come from the SHARED document-grade implementations in
    // [ImageEnhancer] — the same pixels the scan review's copy modes produce.
    if (colorIdx == ShareColorMode.grayscale.index ||
        colorIdx == ShareColorMode.compressedPdf.index) {
      im = ImageEnhancer.documentGrayscale(im);
    } else if (colorIdx == ShareColorMode.blackWhite.index) {
      im = ImageEnhancer.scanBinarize(im);
    }

    final quality = compress ? 42 : 88;
    return img.encodeJpg(im, quality: quality);
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
