import 'dart:io';

import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';

/// Wraps Google ML Kit's on-device document scanner - the engine that performs
/// real auto edge detection (live boundary highlight), perspective correction,
/// auto-crop and enhancement. This is the same technology class behind the
/// WhatsApp / Google Drive scanner experience, and it is the PRIMARY capture
/// path for the Scan flow (see ScanFlowScreen).
///
/// ML Kit's document scanner is Android-only and presents its own full-screen
/// capture UI, so callers should check [isSupported] and fall back to the
/// in-app camera capture on other platforms.
class DocumentScannerService {
  DocumentScannerService._();
  static final DocumentScannerService instance = DocumentScannerService._();

  /// True where the native document scanner is available (Android only).
  bool get isSupported => Platform.isAndroid;

  /// Launches the scanner for a MULTI-PAGE session (up to [pageLimit] pages -
  /// the user taps "add page" inside the scanner UI) and returns the scanned
  /// page paths in order, or `null` if the user cancelled. Throws on a genuine
  /// scanning failure so the caller can fall back to the in-app camera.
  Future<List<String>?> scanPages({
    int pageLimit = 10,
    bool allowGalleryImport = true,
  }) async {
    final scanner = DocumentScanner(
      options: DocumentScannerOptions(
        documentFormats: const {DocumentFormat.jpeg},
        mode: ScannerMode.full, // auto-capture + crop + perspective + enhance
        pageLimit: pageLimit,
        isGalleryImport: allowGalleryImport,
      ),
    );
    try {
      final result = await scanner.scanDocument();
      final images = result.images;
      if (images == null || images.isEmpty) return null; // cancelled
      return List<String>.from(images);
    } finally {
      await scanner.close();
    }
  }

  /// Launches the scanner and returns the file path of the first scanned page,
  /// or `null` if the user cancelled. Throws on a genuine scanning failure so
  /// the caller can surface an error. (Single-page convenience used by the
  /// Add Document "Scan" source.)
  Future<String?> scan({bool allowGalleryImport = true}) async {
    final pages = await scanPages(
      pageLimit: 1,
      allowGalleryImport: allowGalleryImport,
    );
    return (pages == null || pages.isEmpty) ? null : pages.first;
  }
}
