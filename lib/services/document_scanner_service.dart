import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
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
        // BASE, deliberately — not `full`.
        //
        // All three ML Kit modes do the part we actually want: live edge
        // detection, auto-capture, auto-crop and perspective correction. What
        // `full` / `filter` add on top is ML Kit's own *filter* stage
        // (grayscale / auto-enhance), and that filter is **sticky** — Google's
        // scanner UI remembers the last one the user picked and silently
        // reapplies it to every future scan.
        //
        // That was the bug behind "I scanned a colour document and it saved in
        // black and white". Once a user tried the B&W filter, ML Kit baked it
        // into the JPEG before INO ever received the file, so the Original chip
        // on the review screen had no colour left to restore — it was already
        // gone upstream.
        //
        // INO offers its own colour modes downstream (ScanColorMode: original /
        // enhanced / grayscale / B&W in ScanReviewScreen), so ML Kit's filter
        // was both redundant and destructive. BASE returns the geometrically
        // corrected capture with its colour intact, which makes "Original"
        // genuinely original and every other mode reversible.
        mode: ScannerMode.base, // auto-capture + crop + perspective, no filter
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
