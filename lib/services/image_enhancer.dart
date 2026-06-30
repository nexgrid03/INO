import 'dart:io';

import 'package:image/image.dart' as img;

/// Applies a lightweight "document" enhancement to a captured image using the
/// `image` package: grayscale + a contrast/brightness lift that makes text
/// crisper. Writes a sibling file and returns its path; on any failure it
/// returns the original path unchanged so the flow never breaks.
class ImageEnhancer {
  ImageEnhancer._();

  static Future<String> enhance(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return path;

      var out = img.grayscale(decoded);
      out = img.adjustColor(out, contrast: 1.18, brightness: 1.04);

      final dir = File(path).parent.path;
      final outPath =
          '$dir/ino_enhanced_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await File(outPath).writeAsBytes(img.encodeJpg(out, quality: 92));
      return outPath;
    } catch (_) {
      return path;
    }
  }
}
