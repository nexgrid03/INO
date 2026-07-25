import 'dart:io';

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
/// share pipeline's single-page PDF wrap.
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
        final image = pw.MemoryImage(bytes);
        doc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
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

    final dir = await getTemporaryDirectory();
    final name =
        fileName ?? 'ino_scan_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final out = '${dir.path}/$name';
    await File(out).writeAsBytes(await doc.save());
    return out;
  }
}
