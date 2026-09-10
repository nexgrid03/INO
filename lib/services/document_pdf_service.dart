import 'dart:developer' as developer;
import 'dart:io';
import 'dart:ui';

import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../models/wallet_detail_models.dart';
import '../services/document_file_service.dart';
import '../services/image_enhancer.dart';
import '../services/offline_document_store.dart';

/// Converts documents to PDF with 100% original color and applied filters intact,
/// and presents the native platform share sheet (WhatsApp, Email, etc.).
class DocumentPdfService {
  DocumentPdfService._();
  static final DocumentPdfService instance = DocumentPdfService._();

  /// Sanitizes document name for a safe file system name.
  static String sanitizeFileName(String name) {
    final clean = name.replaceAll(RegExp(r'[^a-zA-Z0-9 ._-]'), '').trim();
    return clean.isEmpty ? 'document' : clean;
  }

  /// Converts a single [record] into a high-quality PDF file.
  /// If the document is an image, embeds the exact image (with the original colors
  /// and any user-applied enhancement filter) onto an A4 page without alteration.
  /// If already a PDF, copies it with a clean user-friendly filename.
  Future<File?> generatePdfForDocument(DocumentRecord record) async {
    final filePath = record.filePath;
    if (filePath == null || filePath.trim().isEmpty) return null;

    try {
      // 1. Resolve local file (from offline store if saved, or download/cache/local)
      File? sourceFile;
      if (OfflineDocumentStore.instance.isSaved(record.id)) {
        final offlineDoc = OfflineDocumentStore.instance.byId(record.id);
        if (offlineDoc != null) {
          sourceFile = await OfflineDocumentStore.instance.getDecryptedFile(offlineDoc);
        }
      }
      if (sourceFile == null) {
        if (File(filePath).existsSync()) {
          sourceFile = File(filePath);
        } else {
          sourceFile = await DocumentFileService.instance.ensureLocal(filePath);
        }
      }

      if (!await sourceFile.exists() || await sourceFile.length() == 0) {
        return null;
      }

      final ext = DocumentFileService.extensionOf(filePath);
      final safeName = sanitizeFileName(record.name);
      final tmp = await getTemporaryDirectory();

      // If already a PDF, return a clean named copy
      if (ext == 'pdf') {
        final target = File('${tmp.path}/$safeName.pdf');
        await sourceFile.copy(target.path);
        return target;
      }

      // For image documents: optimize orientation/resolution in a background isolate
      // while preserving 100% full original RGB colors and saved filters.
      final optimizedPath = await ImageEnhancer.optimizeForPdf(sourceFile.path);
      final imageBytes = await File(optimizedPath).readAsBytes();
      final pdfImage = pw.MemoryImage(imageBytes);

      final doc = pw.Document();
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(16),
          build: (pw.Context context) {
            return pw.Center(
              child: pw.Image(pdfImage, fit: pw.BoxFit.contain),
            );
          },
        ),
      );

      // Clean up temporary optimized image copy if a separate one was created
      if (optimizedPath != sourceFile.path) {
        try {
          File(optimizedPath).deleteSync();
        } catch (_) {}
      }

      final target = File('${tmp.path}/$safeName.pdf');
      await target.writeAsBytes(await doc.save());
      return target;
    } catch (e) {
      developer.log('generatePdfForDocument failed: $e', name: 'pdf');
      return null;
    }
  }

  /// Converts multiple documents into either a single combined multi-page PDF
  /// or returns multiple PDF files.
  Future<List<File>> generatePdfsForDocuments(List<DocumentRecord> records) async {
    final results = <File>[];
    for (final record in records) {
      final pdf = await generatePdfForDocument(record);
      if (pdf != null && await pdf.exists()) {
        results.add(pdf);
      }
    }
    return results;
  }

  /// Converts a single document [record] to PDF and opens the system share sheet
  /// (e.g. WhatsApp, Gmail, Messages, Telegram).
  Future<bool> shareDocumentAsPdf(
    DocumentRecord record, {
    Rect? sharePositionOrigin,
  }) async {
    final pdf = await generatePdfForDocument(record);
    if (pdf == null || !await pdf.exists()) return false;

    final safeName = sanitizeFileName(record.name);

    await Share.shareXFiles(
      [
        XFile(
          pdf.path,
          mimeType: 'application/pdf',
          name: '$safeName.pdf',
        ),
      ],
      subject: record.name,
      sharePositionOrigin: sharePositionOrigin,
    );
    return true;
  }

  /// Converts multiple documents to PDF and opens the system share sheet.
  Future<bool> shareMultipleDocumentsAsPdf(
    List<DocumentRecord> records, {
    Rect? sharePositionOrigin,
  }) async {
    if (records.isEmpty) return false;

    final pdfFiles = await generatePdfsForDocuments(records);
    if (pdfFiles.isEmpty) return false;

    final xFiles = pdfFiles
        .map((f) => XFile(
              f.path,
              mimeType: 'application/pdf',
              name: f.path.split(Platform.pathSeparator).last,
            ))
        .toList();

    await Share.shareXFiles(
      xFiles,
      subject: records.length == 1 ? records.first.name : 'Shared Documents (${records.length})',
      sharePositionOrigin: sharePositionOrigin,
    );
    return true;
  }
}
