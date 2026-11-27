import 'dart:io';
import 'dart:isolate';
import 'dart:ui' show Offset;

import 'package:document_scan/document_scan.dart';
import 'package:image/image.dart' as img;

import 'document_crop_service.dart';

/// Finishes a shutter press: find the page on the still (or use the live
/// outline), then perspective-crop in **full color**.
///
/// Important: we deliberately crop with [DocumentCropService] (color JPEG) and
/// never run document_scan's "enhance" filters here — those desaturate to a
/// B&W/scan look. Filters stay a user choice in the scanner UI.
class ScanCaptureProcessor {
  ScanCaptureProcessor._();

  static final DocumentDetector _detector = DocumentDetector();

  /// Returns a high-quality color JPEG path for the upright cropped page.
  static Future<String> process({
    required String capturePath,
    List<Offset>? liveOutline,
  }) async {
    // Prefer still re-detect, but never hang the scanner (iOS Vision can stall).
    final stillCorners = await _detectCornersOnStill(capturePath)
        .timeout(const Duration(seconds: 4), onTimeout: () => null);
    if (stillCorners != null) {
      final cropped =
          await DocumentCropService.rectify(capturePath, stillCorners);
      if (cropped != null) return cropped;
    }

    if (liveOutline != null && liveOutline.length == 4) {
      final cropped =
          await DocumentCropService.rectify(capturePath, liveOutline);
      if (cropped != null) return cropped;
    }

    // No document lock — bake EXIF so the stack thumb isn't sideways.
    return uprightJpeg(capturePath);
  }

  static Future<List<Offset>?> _detectCornersOnStill(String path) async {
    try {
      final corners = await _detector.detect(
        ScanInput.file(path),
        sensitivity: DetectionSensitivity.lenient,
        minimumAspectRatio: 0.12,
      );
      if (corners == null || !corners.isConvex) return null;
      return [
        Offset(corners.topLeft.x, corners.topLeft.y),
        Offset(corners.topRight.x, corners.topRight.y),
        Offset(corners.bottomRight.x, corners.bottomRight.y),
        Offset(corners.bottomLeft.x, corners.bottomLeft.y),
      ];
    } catch (_) {
      return null;
    }
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
      // Keep full RGB — never collapse to grayscale on the default path.
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
