import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:image/image.dart' as img;

/// Applies a real 4-corner perspective crop to a document image.
///
/// Given the four corners of the document (as fractions of the image, in the
/// order top-left, top-right, bottom-right, bottom-left), it maps that
/// quadrilateral onto a straight rectangle using [img.copyRectify] — the same
/// perspective correction Adobe Scan / Microsoft Lens perform — and writes the
/// result to a new JPEG. The output is sized to the corrected page's real edge
/// lengths so the aspect ratio stays natural.
///
/// The decode + rectify (large buffer allocations) run in a **background
/// isolate** and the working image is capped to [_kMaxDim] — so a full-
/// resolution capture can't exhaust the UI isolate's heap and crash the app.
class DocumentCropService {
  DocumentCropService._();

  /// Longest-side cap for the cropped output, to bound memory.
  static const int _kMaxDim = 2600;

  /// [corners] are normalized (0..1) in image space, ordered TL, TR, BR, BL.
  /// Returns the new file path, or null on failure.
  static Future<String?> rectify(String srcPath, List<Offset> corners) {
    if (corners.length != 4) return Future.value(null);
    // Pass plain doubles (guaranteed isolate-sendable) instead of Offsets.
    final flat = <double>[
      for (final c in corners) ...[c.dx, c.dy],
    ];
    return Isolate.run(() => _rectifySync(srcPath, flat));
  }

  static Future<String?> _rectifySync(
      String srcPath, List<double> flat) async {
    try {
      final bytes = await File(srcPath).readAsBytes();
      var src = img.decodeImage(bytes);
      if (src == null) return null;

      // Cap the working resolution so the rectified destination buffer stays
      // bounded (aspect preserved; normalized corners are resolution-agnostic).
      final longest = math.max(src.width, src.height);
      if (longest > _kMaxDim) {
        src = src.width >= src.height
            ? img.copyResize(src,
                width: _kMaxDim, interpolation: img.Interpolation.average)
            : img.copyResize(src,
                height: _kMaxDim, interpolation: img.Interpolation.average);
      }

      final w = src.width;
      final h = src.height;

      Offset corner(int i) => Offset(flat[i * 2], flat[i * 2 + 1]);
      final tl = corner(0);
      final tr = corner(1);
      final br = corner(2);
      final bl = corner(3);

      img.Point toPixel(Offset o) =>
          img.Point((o.dx * w).clamp(0, w - 1), (o.dy * h).clamp(0, h - 1));

      double edge(Offset a, Offset b) {
        final dx = (a.dx - b.dx) * w;
        final dy = (a.dy - b.dy) * h;
        return math.sqrt(dx * dx + dy * dy);
      }

      // Output size = the longer of each opposing pair of edges (bounded).
      final outW =
          math.max(edge(tl, tr), edge(bl, br)).round().clamp(16, _kMaxDim);
      final outH =
          math.max(edge(tl, bl), edge(tr, br)).round().clamp(16, _kMaxDim);

      final dst = img.Image(width: outW, height: outH);
      final rectified = img.copyRectify(
        src,
        topLeft: toPixel(tl),
        topRight: toPixel(tr),
        bottomLeft: toPixel(bl),
        bottomRight: toPixel(br),
        interpolation: img.Interpolation.linear,
        toImage: dst,
      );

      final dir = File(srcPath).parent.path;
      final outPath =
          '$dir/ino_crop_${DateTime.now().microsecondsSinceEpoch}.jpg';
      await File(outPath).writeAsBytes(img.encodeJpg(rectified, quality: 92));
      return outPath;
    } catch (_) {
      return null;
    }
  }
}
