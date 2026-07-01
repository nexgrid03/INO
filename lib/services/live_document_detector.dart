import 'package:camera/camera.dart';

/// One real-time reading of what the camera is looking at.
class DocumentSignal {
  const DocumentSignal(this.confidence, this.steady);

  /// 0..1 — how "document-like" the framed subject is right now (a sharp,
  /// high-contrast page fills the centre with edges; empty/blurry scenes score
  /// low).
  final double confidence;

  /// True when the frame is holding still (low frame-to-frame change) — the
  /// signal used to decide the document is stable enough to scan.
  final bool steady;

  static const DocumentSignal none = DocumentSignal(0, false);
}

/// A lightweight, dependency-free document presence detector fed by the live
/// camera image stream.
///
/// It does NOT pretend to be a full edge/rectangle detector (ML Kit owns that
/// on the capture path). Instead it derives two honest, cheap signals from the
/// luminance (Y) plane of each frame, sampled on a small fixed grid over the
/// central scanner region:
///
///   • confidence — mean local gradient (edge energy). A document page with
///     text/borders on a contrasting surface produces far more edge energy than
///     an empty wall or a blurry, out-of-focus view.
///   • steady     — mean absolute difference against the previous frame's
///     samples. Low movement ⇒ the user is holding the document still.
///
/// Only ~[_grid]² pixels are read per frame regardless of resolution, so this
/// stays cheap even at high capture presets. Thresholds live in the scanner
/// screen so they can be tuned without touching this math.
class LiveDocumentDetector {
  /// Sampling grid density over the central region (32×32 = 1024 reads/frame).
  static const int _grid = 32;

  /// Converts mean gradient (0..255) into 0..1 confidence. ~22 of average
  /// neighbour contrast maps to full confidence — enough to separate a framed
  /// document from a flat background, without needing a pristine scan.
  static const double _focusNorm = 22.0;

  /// Previous frame's luminance samples, for the motion (steadiness) estimate.
  List<int>? _prev;

  /// Forget history (call when the stream stops / camera is freed).
  void reset() => _prev = null;

  DocumentSignal analyze(CameraImage image) {
    if (image.planes.isEmpty) return DocumentSignal.none;
    final plane = image.planes.first; // Y (luminance) plane for YUV420.
    final bytes = plane.bytes;
    final int w = image.width;
    final int h = image.height;
    if (w == 0 || h == 0 || bytes.isEmpty) return DocumentSignal.none;

    final int rowStride = plane.bytesPerRow;
    final int pixStride = plane.bytesPerPixel ?? 1;

    // Central region only (15%..85%) — matches where the frame guide sits, so
    // background clutter at the edges doesn't trip detection.
    final int x0 = (w * 0.15).floor();
    final int x1 = (w * 0.85).floor();
    final int y0 = (h * 0.15).floor();
    final int y1 = (h * 0.85).floor();
    final int rw = x1 - x0;
    final int rh = y1 - y0;
    if (rw <= _grid || rh <= _grid) return DocumentSignal.none;

    final samples = List<int>.filled(_grid * _grid, 0);
    for (int gy = 0; gy < _grid; gy++) {
      final int py = y0 + (gy * rh ~/ _grid);
      final int rowBase = py * rowStride;
      for (int gx = 0; gx < _grid; gx++) {
        final int px = x0 + (gx * rw ~/ _grid);
        final int idx = rowBase + px * pixStride;
        samples[gy * _grid + gx] =
            (idx >= 0 && idx < bytes.length) ? bytes[idx] : 0;
      }
    }

    // Edge energy: mean absolute gradient to the right & lower neighbours.
    int grad = 0;
    int count = 0;
    for (int gy = 0; gy < _grid; gy++) {
      for (int gx = 0; gx < _grid; gx++) {
        final int v = samples[gy * _grid + gx];
        if (gx < _grid - 1) {
          grad += (v - samples[gy * _grid + gx + 1]).abs();
          count++;
        }
        if (gy < _grid - 1) {
          grad += (v - samples[(gy + 1) * _grid + gx]).abs();
          count++;
        }
      }
    }
    final double focus = count == 0 ? 0.0 : grad / count;
    final double confidence = (focus / _focusNorm).clamp(0.0, 1.0);

    // Temporal steadiness vs the previous frame's samples.
    bool steady = false;
    final prev = _prev;
    if (prev != null && prev.length == samples.length) {
      int diff = 0;
      for (int i = 0; i < samples.length; i++) {
        diff += (samples[i] - prev[i]).abs();
      }
      final double motion = diff / samples.length;
      steady = motion < 6.0; // < ~6/255 average change ⇒ effectively still.
    }
    _prev = samples;

    return DocumentSignal(confidence, steady);
  }
}
