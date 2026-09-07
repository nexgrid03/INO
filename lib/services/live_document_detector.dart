import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import 'package:camera/camera.dart';

/// One real-time reading of what the camera is looking at.
class DocumentSignal {
  const DocumentSignal(this.confidence, this.steady, {this.bounds, this.corners});

  /// 0..1 - how "document-like" the framed subject is right now (a sharp,
  /// high-contrast page fills the centre with edges; empty/blurry scenes score
  /// low).
  final double confidence;

  /// True when the frame is holding still (low frame-to-frame change) - the
  /// signal used to decide the document is stable enough to scan.
  final bool steady;

  /// Where the document sits, as a rect normalised to the raw camera frame
  /// (0..1 of `image.width` × `image.height`, i.e. still in *sensor*
  /// coordinates - the caller rotates it to display space).
  ///
  /// Null when no plausible document region could be isolated this frame.
  final Rect? bounds;

  /// The document's four corners - top-left, top-right, bottom-right,
  /// bottom-left - in the same normalised sensor coordinates as [bounds].
  ///
  /// This is the shape the on-screen border traces: a page held at an angle is
  /// a skewed quadrilateral on the sensor, and outlining it with [bounds]'
  /// upright rectangle would sit visibly wide of the page on two corners.
  /// Null whenever no convincing quad could be fitted.
  final List<Offset>? corners;

  static const DocumentSignal none = DocumentSignal(0, false);
}

/// A lightweight, dependency-free document presence detector fed by the live
/// camera image stream.
///
/// It does NOT pretend to be a full edge/rectangle detector (ML Kit owns that
/// on the capture path). Instead it derives three honest, cheap signals from
/// the luminance (Y) plane of each frame, sampled on a small fixed grid over
/// the scanner region:
///
///   • confidence - mean local gradient (edge energy) over the central area. A
///     document page with text/borders on a contrasting surface produces far
///     more edge energy than an empty wall or a blurry, out-of-focus view.
///   • steady     - mean absolute difference against the previous frame's
///     samples. Low movement ⇒ the user is holding the document still.
///   • bounds     - the bounding box of the cells carrying that edge energy,
///     which is what the on-screen highlight border traces.
///
/// Only ~[_grid]² pixels are read per frame regardless of resolution, so this
/// stays cheap even at high capture presets. Thresholds live in the scanner
/// screen so they can be tuned without touching this math.
class LiveDocumentDetector {
  /// Sampling grid density over the sampled region (40×40 = 1600 reads/frame).
  static const int _grid = 40;

  /// The slice of the frame that is sampled (4%..96%). Wider than the central
  /// region the confidence uses, so a document that fills most of the viewport
  /// still gets a bounding box that hugs it instead of clipping at the guide.
  static const double _regionStart = 0.04;
  static const double _regionEnd = 0.96;

  /// Grid indices bounding the central 15%..85% window that feeds [confidence]
  /// - the same area the previous central-only sampling covered, so detection
  /// thresholds keep their meaning.
  static final int _coreLo =
      (((0.15 - _regionStart) / (_regionEnd - _regionStart)) * _grid).floor();
  static final int _coreHi =
      (((0.85 - _regionStart) / (_regionEnd - _regionStart)) * _grid).ceil();

  /// Converts mean gradient (0..255) into 0..1 confidence. ~22 of average
  /// neighbour contrast maps to full confidence - enough to separate a framed
  /// document from a flat background, without needing a pristine scan.
  static const double _focusNorm = 22.0;

  /// A cell counts as "document" when its edge energy clears this fraction of
  /// the frame's strong-edge level (the 95th percentile), floored by
  /// [_minCellEnergy] so a flat wall's sensor noise never forms a box.
  static const double _boundsEnergyFraction = 0.24;
  static const int _minCellEnergy = 10;

  /// A row/column joins the box once this fraction of its cells are active -
  /// isolated specks (dust, a pen on the desk) can't stretch the border.
  static const double _boundsRowFill = 0.10;

  /// A believable document fills at least this fraction of the frame on both
  /// axes; anything smaller is treated as clutter rather than a page.
  static const double _minBoundsExtent = 0.16;

  /// A cell can only anchor a corner when at least this many of its eight
  /// neighbours are active too - one hot pixel on the desk is not a corner.
  static const int _minCornerNeighbours = 2;

  /// The fitted quad is pushed this far out from its own centroid, in units of
  /// its half-diagonal, so the stroke frames the page instead of cutting it.
  static const double _quadPad = 0.045;

  /// Scratch buffers, reused across frames so the analysis loop allocates
  /// nothing per frame. [_samples] and [_prev] are double-buffered: each frame
  /// writes into [_samples] and then swaps, so last frame's readings survive
  /// for the motion estimate without a copy.
  List<int> _samples = List<int>.filled(_grid * _grid, 0);
  List<int> _prev = List<int>.filled(_grid * _grid, 0);
  final List<int> _energy = List<int>.filled(_grid * _grid, 0);
  final List<int> _rowHits = List<int>.filled(_grid, 0);
  final List<int> _colHits = List<int>.filled(_grid, 0);
  final List<int> _histogram = List<int>.filled(256, 0);

  /// True once [_prev] holds a real frame - until then there is nothing to
  /// measure motion against.
  bool _hasPrev = false;

  /// Forget history (call when the stream stops / camera is freed).
  void reset() => _hasPrev = false;

  DocumentSignal analyze(CameraImage image) {
    if (image.planes.isEmpty) return DocumentSignal.none;
    final plane = image.planes.first; // Y (luminance) plane for YUV420.
    final bytes = plane.bytes;
    final int w = image.width;
    final int h = image.height;
    if (w == 0 || h == 0 || bytes.isEmpty) return DocumentSignal.none;

    final int rowStride = plane.bytesPerRow;
    final int pixStride = plane.bytesPerPixel ?? 1;

    final int x0 = (w * _regionStart).floor();
    final int x1 = (w * _regionEnd).floor();
    final int y0 = (h * _regionStart).floor();
    final int y1 = (h * _regionEnd).floor();
    final int rw = x1 - x0;
    final int rh = y1 - y0;
    if (rw <= _grid || rh <= _grid) return DocumentSignal.none;

    final samples = _samples;
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

    // Edge energy per cell: absolute gradient to the right & lower neighbours.
    // The central window's mean feeds `confidence`; the whole grid feeds the
    // bounding box.
    final energy = _energy;
    int coreGrad = 0;
    int coreCount = 0;
    for (int gy = 0; gy < _grid; gy++) {
      final bool coreRow = gy >= _coreLo && gy < _coreHi;
      for (int gx = 0; gx < _grid; gx++) {
        final int i = gy * _grid + gx;
        final int v = samples[i];
        int cell = 0;
        if (gx < _grid - 1) {
          final int d = (v - samples[i + 1]).abs();
          cell += d;
          if (coreRow && gx >= _coreLo && gx < _coreHi) {
            coreGrad += d;
            coreCount++;
          }
        }
        if (gy < _grid - 1) {
          final int d = (v - samples[i + _grid]).abs();
          cell += d;
          if (coreRow && gx >= _coreLo && gx < _coreHi) {
            coreGrad += d;
            coreCount++;
          }
        }
        energy[i] = cell;
      }
    }
    final double focus = coreCount == 0 ? 0.0 : coreGrad / coreCount;
    final double confidence = (focus / _focusNorm).clamp(0.0, 1.0);

    // Temporal steadiness vs the previous frame's samples.
    bool steady = false;
    if (_hasPrev) {
      final prev = _prev;
      int diff = 0;
      for (int i = 0; i < samples.length; i++) {
        diff += (samples[i] - prev[i]).abs();
      }
      final double motion = diff / samples.length;
      steady = motion < 6.0; // < ~6/255 average change ⇒ effectively still.
    }
    // Swap the buffers: this frame's readings become next frame's history, and
    // the buffer they displace is what the next frame samples into.
    _samples = _prev;
    _prev = samples;
    _hasPrev = true;

    final shape = _shape(x0 / w, y0 / h, rw / w, rh / h);
    return DocumentSignal(
      confidence,
      steady,
      bounds: shape?.bounds,
      corners: shape?.corners,
    );
  }

  /// The document's outline: an upright bounding box plus the four-corner quad
  /// that actually hugs it.
  ///
  /// [rx]/[ry] are the sampled region's normalised origin and [rw]/[rh] its
  /// normalised size, so grid indices can be projected straight into 0..1
  /// frame coordinates.
  _DocumentShape? _shape(double rx, double ry, double rw, double rh) {
    final energy = _energy;

    // Strong-edge level: the 95th percentile, so one specular highlight can't
    // drag the threshold up and erase the whole document.
    final int strong = _percentile(energy, 0.95);
    final int threshold =
        math.max(_minCellEnergy, (strong * _boundsEnergyFraction).round());

    final rowHits = _rowHits;
    final colHits = _colHits;
    rowHits.fillRange(0, _grid, 0);
    colHits.fillRange(0, _grid, 0);
    for (int gy = 0; gy < _grid; gy++) {
      for (int gx = 0; gx < _grid; gx++) {
        if (energy[gy * _grid + gx] >= threshold) {
          rowHits[gy]++;
          colHits[gx]++;
        }
      }
    }

    final int minFill = math.max(2, (_grid * _boundsRowFill).round());
    final int top = _firstAbove(rowHits, minFill, forward: true);
    if (top < 0) return null;
    final int bottom = _firstAbove(rowHits, minFill, forward: false);
    final int left = _firstAbove(colHits, minFill, forward: true);
    if (left < 0) return null;
    final int right = _firstAbove(colHits, minFill, forward: false);

    // Half-open on the far edge, plus a cell of breathing room so the border
    // reads as sitting *around* the document rather than cutting into it.
    const double pad = 1.5;
    final double cellW = rw / _grid;
    final double cellH = rh / _grid;
    final double l = (rx + (left - pad) * cellW).clamp(0.0, 1.0);
    final double t = (ry + (top - pad) * cellH).clamp(0.0, 1.0);
    final double r = (rx + (right + 1 + pad) * cellW).clamp(0.0, 1.0);
    final double b = (ry + (bottom + 1 + pad) * cellH).clamp(0.0, 1.0);

    if (r - l < _minBoundsExtent || b - t < _minBoundsExtent) return null;
    final bounds = Rect.fromLTRB(l, t, r, b);

    final corners = _corners(
      rx: rx,
      ry: ry,
      cellW: cellW,
      cellH: cellH,
      threshold: threshold,
      left: left,
      top: top,
      right: right,
      bottom: bottom,
    );
    // No convincing quad (a sliver, a bow-tie) - fall back to the upright box
    // rather than drawing a shape the detector cannot actually justify.
    return _DocumentShape(bounds, corners ?? _rectCorners(bounds));
  }

  /// Fits the document's four corners by taking, among the active cells inside
  /// the bounding box, the extreme cell along each of the four diagonals:
  /// min(x+y) is the top-left, max(x-y) the top-right, and so on.
  ///
  /// This is the cheap standard trick for recovering a rotated rectangle from a
  /// mask, and it is exactly right for the case that matters here - a page or
  /// card lying at an angle, whose sensor footprint is a convex quad.
  List<Offset>? _corners({
    required double rx,
    required double ry,
    required double cellW,
    required double cellH,
    required int threshold,
    required int left,
    required int top,
    required int right,
    required int bottom,
  }) {
    final energy = _energy;

    // Running extremes: [sum-min, diff-max, sum-max, diff-min] → TL, TR, BR, BL.
    var bestSumLo = double.infinity;
    var bestDiffHi = -double.infinity;
    var bestSumHi = -double.infinity;
    var bestDiffLo = double.infinity;
    Offset? tl, tr, br, bl;

    for (int gy = top; gy <= bottom; gy++) {
      for (int gx = left; gx <= right; gx++) {
        if (energy[gy * _grid + gx] < threshold) continue;
        if (_neighbourCount(gx, gy, threshold) < _minCornerNeighbours) continue;

        final double nx = rx + (gx + 0.5) * cellW;
        final double ny = ry + (gy + 0.5) * cellH;
        final double sum = nx + ny;
        final double diff = nx - ny;
        if (sum < bestSumLo) {
          bestSumLo = sum;
          tl = Offset(nx, ny);
        }
        if (diff > bestDiffHi) {
          bestDiffHi = diff;
          tr = Offset(nx, ny);
        }
        if (sum > bestSumHi) {
          bestSumHi = sum;
          br = Offset(nx, ny);
        }
        if (diff < bestDiffLo) {
          bestDiffLo = diff;
          bl = Offset(nx, ny);
        }
      }
    }
    if (tl == null || tr == null || br == null || bl == null) return null;

    final quad = <Offset>[tl, tr, br, bl];
    // A quad that has collapsed (a thin band, or every extreme landing on the
    // same few cells) is not a document outline.
    if (_area(quad) < _minBoundsExtent * _minBoundsExtent) return null;

    // Push each corner out from the centroid so the stroke frames the page.
    final cx = quad.map((p) => p.dx).reduce((a, b) => a + b) / 4;
    final cy = quad.map((p) => p.dy).reduce((a, b) => a + b) / 4;
    return [
      for (final p in quad)
        Offset(
          (p.dx + (p.dx - cx) * _quadPad).clamp(0.0, 1.0),
          (p.dy + (p.dy - cy) * _quadPad).clamp(0.0, 1.0),
        ),
    ];
  }

  /// How many of a cell's eight neighbours are active.
  int _neighbourCount(int gx, int gy, int threshold) {
    final energy = _energy;
    int n = 0;
    for (int dy = -1; dy <= 1; dy++) {
      final int y = gy + dy;
      if (y < 0 || y >= _grid) continue;
      for (int dx = -1; dx <= 1; dx++) {
        if (dx == 0 && dy == 0) continue;
        final int x = gx + dx;
        if (x < 0 || x >= _grid) continue;
        if (energy[y * _grid + x] >= threshold) n++;
      }
    }
    return n;
  }

  /// Shoelace area of a quad, in normalised frame units.
  static double _area(List<Offset> q) {
    var a = 0.0;
    for (int i = 0; i < q.length; i++) {
      final p = q[i];
      final n = q[(i + 1) % q.length];
      a += p.dx * n.dy - n.dx * p.dy;
    }
    return a.abs() / 2;
  }

  /// The upright fallback quad, in the same TL/TR/BR/BL order.
  static List<Offset> _rectCorners(Rect r) =>
      [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft];

  /// First index (from either end) whose value reaches [minValue], or -1.
  static int _firstAbove(List<int> hits, int minValue, {required bool forward}) {
    if (forward) {
      for (int i = 0; i < hits.length; i++) {
        if (hits[i] >= minValue) return i;
      }
    } else {
      for (int i = hits.length - 1; i >= 0; i--) {
        if (hits[i] >= minValue) return i;
      }
    }
    return -1;
  }

  /// Approximate percentile via a 256-bucket histogram - O(n) and allocation
  /// free, versus sorting 1600 ints every frame. Energy is clamped into the
  /// bucket range because two gradients can sum past 255.
  int _percentile(List<int> values, double fraction) {
    final hist = _histogram;
    hist.fillRange(0, 256, 0);
    for (final v in values) {
      hist[v > 255 ? 255 : (v < 0 ? 0 : v)]++;
    }
    final int target = (values.length * fraction).floor();
    int seen = 0;
    for (int i = 0; i < 256; i++) {
      seen += hist[i];
      if (seen > target) return i;
    }
    return 255;
  }
}

/// The detector's read on where the document is: an upright bounding box and
/// the four-corner quad that hugs it.
class _DocumentShape {
  const _DocumentShape(this.bounds, this.corners);

  final Rect bounds;
  final List<Offset> corners;
}
