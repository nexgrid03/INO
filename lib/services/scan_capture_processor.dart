import 'dart:io';
import 'dart:isolate';
import 'dart:ui' show Offset;

import 'package:document_scan/document_scan.dart';
import 'package:image/image.dart' as img;

import 'document_crop_service.dart';

/// Product-grade capture finish: re-detect the page on the still photo, then
/// perspective-crop. Live overlay corners are only a fallback — the still and
/// its corners always share the same pixel space, which is what stops scans
/// coming out sideways or "crossed".
class ScanCaptureProcessor {
  ScanCaptureProcessor._();

  static final DocumentDetector _detector = DocumentDetector();
  static const DocumentProcessor _processor = DocumentProcessor();

  /// Returns a JPEG path for the upright cropped page.
  static Future<String> process({
    required String capturePath,
    List<Offset>? liveOutline,
  }) async {
    final fromStill = await _cropFromStill(capturePath);
    if (fromStill != null) return fromStill;

    if (liveOutline != null && liveOutline.length == 4) {
      final cropped =
          await DocumentCropService.rectify(capturePath, liveOutline);
      if (cropped != null) return cropped;
    }

    // No document lock — at least bake EXIF so the thumbnail isn't sideways.
    return uprightJpeg(capturePath);
  }

  static Future<String?> _cropFromStill(String path) async {
    try {
      final corners = await _detector.detect(
        ScanInput.file(path),
        sensitivity: DetectionSensitivity.lenient,
        minimumAspectRatio: 0.12,
      );
      if (corners == null || !corners.isConvex) return null;

      final scan = await _processor.crop(
        ScanInput.file(path),
        corners,
        filter: ScanFilter.none,
        output: const ScanOutputFormat.jpegAt(92),
        background: true,
      );
      if (scan == null || scan.bytes.isEmpty) return null;

      final outPath =
          '${File(path).parent.path}/ino_scan_${DateTime.now().microsecondsSinceEpoch}.jpg';
      await File(outPath).writeAsBytes(scan.bytes, flush: true);
      return outPath;
    } catch (_) {
      return null;
    }
  }

  /// Rewrites [path] with EXIF orientation baked into pixels (upright JPEG).
  static Future<String> uprightJpeg(String path) {
    return Isolate.run(() => _uprightJpegSync(path));
  }

  static Future<String> _uprightJpegSync(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      var decoded = img.decodeImage(bytes);
      if (decoded == null) return path;
      decoded = img.bakeOrientation(decoded);
      final outPath =
          '${File(path).parent.path}/ino_upright_${DateTime.now().microsecondsSinceEpoch}.jpg';
      await File(outPath).writeAsBytes(img.encodeJpg(decoded, quality: 92));
      return outPath;
    } catch (_) {
      return path;
    }
  }
}
