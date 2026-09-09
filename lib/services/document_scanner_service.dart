import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show PlatformException;
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
  /// Never touches `dart:io` Platform on web.
  bool get isSupported => !kIsWeb && Platform.isAndroid;

  /// Returns true if [error] corresponds to user cancellation (e.g. back button
  /// or cancel tapped in native ML Kit document scanner activity).
  static bool isUserCancelled(dynamic error) {
    if (error is PlatformException) {
      final msg = error.message?.toLowerCase() ?? '';
      final code = error.code.toLowerCase();
      return msg.contains('cancel') || code.contains('cancel');
    }
    final str = error.toString().toLowerCase();
    return str.contains('cancel');
  }

  /// Launches the scanner for a MULTI-PAGE session (up to [pageLimit] pages -
  /// the user taps "add page" inside the scanner UI) and returns the scanned
  /// page paths in order, or `null` if the user cancelled. Throws on a genuine
  /// scanning failure so the caller can fall back to the in-app camera.
  Future<List<String>?> scanPages({
    int pageLimit = 10,
    bool allowGalleryImport = true,
    ScannerMode mode = ScannerMode.base,
  }) async {
    final scanner = DocumentScanner(
      options: DocumentScannerOptions(
        documentFormats: const {DocumentFormat.jpeg},
        mode: mode,
        pageLimit: pageLimit,
        isGalleryImport: allowGalleryImport,
      ),
    );
    try {
      final result = await scanner.scanDocument();
      final images = result.images;
      if (images == null || images.isEmpty) return null; // cancelled
      return List<String>.from(images);
    } on PlatformException catch (e) {
      if (isUserCancelled(e)) return null; // user pressed back / cancelled
      rethrow;
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
