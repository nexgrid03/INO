import 'dart:io';
import 'dart:isolate';
import 'dart:ui' show Offset;

import 'package:document_scan/document_scan.dart';
import 'package:image/image.dart' as img;

import 'document_crop_service.dart';

/// Finishes a shutter press: find the page on the still (or use the live
/// outline), then perspective-crop in **full color** with a proper homography.
///
/// Uses [DocumentScanner] / [DocumentProcessor] (same engine as the package
/// demo) so iOS Vision corners map cleanly into an upright color JPEG — not a
/// soft/wrong desk crop. Filters stay a user choice in the scanner UI.
class ScanCaptureProcessor {
  ScanCaptureProcessor._();

  static final DocumentScanner _scanner = DocumentScanner();
  static const DocumentProcessor _processor = DocumentProcessor();

  /// Returns a high-quality color JPEG path for the upright cropped page.
  static Future<String> process({
    required String capturePath,
    List<Offset>? liveOutline,
  }) async {
    final input = ScanInput.file(capturePath);
    final liveCorners = _toDocumentCorners(liveOutline);

    // 1) Fast path: crop with the locked live outline (no second Vision pass).
    if (liveCorners != null) {
      try {
        final cropped = await _processor
            .crop(
              input,
              liveCorners,
              filter: ScanFilter.none,
              output: const ScanOutputFormat.jpegAt(92),
              maxDimension: 2400,
              background: true,
            )
            .timeout(const Duration(seconds: 3), onTimeout: () => null);
        if (cropped != null) return _writeScan(cropped, capturePath);
      } catch (_) {}

      final fallback =
          await DocumentCropService.rectify(capturePath, liveOutline!);
      if (fallback != null) return fallback;
    }

    // 2) No live lock — detect on the still (slower, but recovers the page).
    try {
      final still = await _scanner
          .scan(
            input,
            filter: ScanFilter.none,
            output: const ScanOutputFormat.jpegAt(92),
            maxDimension: 2400,
            background: true,
            sensitivity: DetectionSensitivity.balanced,
            minimumAspectRatio: 0.14,
          )
          .timeout(const Duration(seconds: 3), onTimeout: () => null);
      if (still != null) {
        return _writeScan(still, capturePath);
      }
    } catch (_) {}

    // No document lock — bake EXIF so the stack thumb isn't sideways.
    return uprightJpeg(capturePath);
  }

  static DocumentCorners? _toDocumentCorners(List<Offset>? outline) {
    if (outline == null || outline.length != 4) return null;
    final corners = DocumentCorners.fromUnordered([
      (x: outline[0].dx, y: outline[0].dy),
      (x: outline[1].dx, y: outline[1].dy),
      (x: outline[2].dx, y: outline[2].dy),
      (x: outline[3].dx, y: outline[3].dy),
    ]);
    if (!corners.isConvex || corners.area < 0.06) return null;
    return corners;
  }

  static Future<String> _writeScan(
    ScannedDocument scan,
    String capturePath,
  ) async {
    final dir = File(capturePath).parent.path;
    final outPath =
        '$dir/ino_scan_${DateTime.now().microsecondsSinceEpoch}.jpg';
    await File(outPath).writeAsBytes(scan.bytes);
    return outPath;
  }

  /// Rewrites [path] with EXIF orientation baked into pixels (color JPEG).
  static Future<String> uprightJpeg(String path) {
    return Isolate.run(() => _uprightJpegSync(path));
  }

  static Future<String> _uprightJpegSync(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      var decoded = img.decodeImage(bytes);
      if (decoded == null) return path;
      decoded = img.bakeOrientation(decoded);
      if (decoded.numChannels < 3) {
        decoded = decoded.convert(numChannels: 3);
      }
      final outPath =
          '${File(path).parent.path}/ino_upright_${DateTime.now().microsecondsSinceEpoch}.jpg';
      await File(outPath).writeAsBytes(img.encodeJpg(decoded, quality: 95));
      return outPath;
    } catch (_) {
      return path;
    }
  }
}
