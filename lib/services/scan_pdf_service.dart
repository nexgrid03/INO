import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'image_enhancer.dart';

/// Assembles a multi-page scan into ONE optimized PDF (the WhatsApp / Adobe
/// Scan "Scan Page 1 … Page N → single PDF" behaviour).
///
/// Every page is first optimized for embedding - orientation baked, longest
/// side capped, recompressed (see [ImageEnhancer.optimizeForPdf]) - so a
/// 5-page scan stays a sensible file size instead of embedding five full-res
/// camera captures. Pages are laid out on A4 with a small margin, matching the
/// share pipeline's single-page PDF wrap. Both portrait and landscape documents
/// are supported.
class ScanPdfService {
  ScanPdfService._();
  static final ScanPdfService instance = ScanPdfService._();

  /// Builds a single PDF from [pagePaths] (in order) and returns its file
  /// path. Throws when no page could be embedded.
  Future<String> buildPdf(List<String> pagePaths, {String? fileName}) async {
    final doc = pw.Document();
    var embedded = 0;

    for (final path in pagePaths) {
      try {
        // Optimize in a background isolate: bake orientation + cap + q86.
        final optimized = await ImageEnhancer.optimizeForPdf(path);
        final bytes = await File(optimized).readAsBytes();

        // Check dimensions to support portrait and landscape documents seamlessly
        final decoded = img.decodeImage(bytes);
        final isLandscape = decoded != null && decoded.width > decoded.height;
        final pageFormat =
            isLandscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4;

        final image = pw.MemoryImage(bytes);
        doc.addPage(
          pw.Page(
            pageFormat: pageFormat,
            margin: const pw.EdgeInsets.all(16),
            build: (context) => pw.Center(
              child: pw.Image(image, fit: pw.BoxFit.contain),
            ),
          ),
        );
        embedded++;
        // Clean the optimized temp copy (the PDF holds its own bytes now).
        if (optimized != path) {
          try {
            File(optimized).deleteSync();
          } catch (_) {}
        }
      } catch (_) {
        // Skip an unreadable page rather than failing the whole document.
      }
    }

    if (embedded == 0) {
      throw const FileSystemException('No scanned page could be embedded');
    }

    String tempPath;
    try {
      final dir = await getTemporaryDirectory();
      tempPath = dir.path;
    } catch (_) {
      tempPath = Directory.systemTemp.path;
    }

    final name =
        fileName ?? 'ino_scan_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final out = '$tempPath/$name';
    await File(out).writeAsBytes(await doc.save());
    return out;
  }
}

