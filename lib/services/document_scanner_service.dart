import 'dart:io';

import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';

/// Wraps Google ML Kit's on-device document scanner — the engine that performs
/// real auto edge detection, perspective correction, auto-crop and enhancement.
///
/// ML Kit's document scanner is Android-only and presents its own full-screen
/// capture UI, so callers should check [isSupported] and fall back to a plain
/// camera still capture on other platforms.
class DocumentScannerService {
  DocumentScannerService._();
  static final DocumentScannerService instance = DocumentScannerService._();

  /// True where the native document scanner is available (Android only).
  bool get isSupported => Platform.isAndroid;

  /// Launches the scanner and returns the file path of the first scanned page,
  /// or `null` if the user cancelled. Throws on a genuine scanning failure so
  /// the caller can surface an error.
  Future<String?> scan({bool allowGalleryImport = true}) async {
    final scanner = DocumentScanner(
      options: DocumentScannerOptions(
        documentFormats: const {DocumentFormat.jpeg},
        mode: ScannerMode.full, // auto-capture + crop + perspective + enhance
        pageLimit: 1,
        isGalleryImport: allowGalleryImport,
      ),
    );
    try {
      final result = await scanner.scanDocument();
      final images = result.images;
      if (images == null || images.isEmpty) return null; // cancelled
      return images.first;
    } finally {
      await scanner.close();
    }
  }
}
