import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import 'package:camera/camera.dart';

/// One real-time reading of what the camera is looking at.
class DocumentSignal {
  const DocumentSignal(this.confidence, this.steady, {this.bounds, this.corners});

  /// 0..1 - how "document-like" the framed subject is right now.
  final double confidence;

  /// True when the frame is holding still (low frame-to-frame change).
  final bool steady;

  /// Document bounds normalised to the raw camera frame (0..1 sensor space).
  final Rect? bounds;

  /// Four corners TL → TR → BR → BL in the same normalised sensor coordinates.
  final List<Offset>? corners;

  static const DocumentSignal none = DocumentSignal(0, false);
}

/// Live document edge detector for the in-app scanner preview.
///
/// Finds the **page silhouette against the background** (the real paper /
/// book / screen border), not interior text texture. That is what Photos /
/// Lens lock onto: contrast between the sheet and the desk, then the outer
/// contour of that sheet as a four-corner quad.
///
/// Pipeline (all on a fixed [_grid]² luminance sample - cheap every frame):
///   1. Estimate background from the frame's outer ring.
///   2. Build a solid foreground mask (page vs desk), close small holes.
///   3. Keep only the largest blob so desk clutter cannot steal the outline.
///   4. Fit corners from the **silhouette boundary** (cells that touch
///      background) - interior ink cannot bend the quad.
///   5. Score confidence from silhouette contrast so blank white pages still
///      detect, not only busy text pages.
class LiveDocumentDetector {
  static const int _grid = 48;

  static const double _regionStart = 0.03;
  static const double _regionEnd = 0.97;

  static final int _coreLo =
      (((0.15 - _regionStart) / (_regionEnd - _regionStart)) * _grid).floor();
  static final int _coreHi =
      (((0.85 - _regionStart) / (_regionEnd - _regionStart)) * _grid).ceil();

  /// Interior edge energy → confidence (textured pages).
  static const double _focusNorm = 20.0;

  /// |page − desk| contrast → confidence (blank pages on a desk).
  static const double _contrastNorm = 48.0;

  /// Minimum |luma − background| to count as page/foreground.
  static const int _fgContrast = 22;

  /// Minimum strong edge response to reinforce a silhouette cell.
  static const int _edgeBoost = 18;

  static const double _minBoundsExtent = 0.14;
  static const double _minAspect = 0.42;
  static const double _maxAspect = 2.35;

  /// Tiny outward pad so the stroke sits on the paper edge, not inside it.
  static const double _quadPad = 0.018;

  /// Largest blob must cover at least this fraction of the sample grid.
  static const double _minBlobFill = 0.045;

  List<int> _samples = List<int>.filled(_grid * _grid, 0);
  List<int> _prev = List<int>.filled(_grid * _grid, 0);
  final List<int> _energy = List<int>.filled(_grid * _grid, 0);
  final List<int> _mask = List<int>.filled(_grid * _grid, 0);
  final List<int> _scratch = List<int>.filled(_grid * _grid, 0);
  final List<int> _labels = List<int>.filled(_grid * _grid, 0);
  final List<int> _queue = List<int>.filled(_grid * _grid, 0);
  final List<int> _borderLuma = List<int>.filled(_grid * 4, 0);

  _DocumentShape? _prevShape;
  int _shapeHold = 0;
  static const int _kShapeHoldFrames = 6;
  static const double _lockDeadband = 0.016;

  bool _hasPrev = false;

  void reset() {
    _hasPrev = false;
    _prevShape = null;
    _shapeHold = 0;
  }

  DocumentSignal analyze(CameraImage image) {
    if (image.planes.isEmpty) return DocumentSignal.none;
    final plane = image.planes.first;
    final bytes = plane.bytes;
    final int w = image.width;
    final int h = image.height;
    if (w == 0 || h == 0 || bytes.isEmpty) return DocumentSignal.none;

    final int rowStride = plane.bytesPerRow;
    final bool bgra = image.format.group == ImageFormatGroup.bgra8888;
    final int pixStride = bgra
        ? (plane.bytesPerPixel ?? 4)
        : (plane.bytesPerPixel ?? 1);

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
        samples[gy * _grid + gx] = bgra
            ? _bgraLuma(bytes, idx)
            : (idx >= 0 && idx < bytes.length)
                ? bytes[idx]
                : 0;
      }
    }

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

    final int bg = _backgroundLuma(samples);
    final shape = _shapeFromSilhouette(
      samples: samples,
      energy: energy,
      bg: bg,
      rx: x0 / w,
      ry: y0 / h,
      rw: rw / w,
      rh: rh / h,
    );

    // Confidence: strongest of interior texture OR page-vs-desk contrast so
    // blank sheets still light up the border.
    final double texture =
        coreCount == 0 ? 0.0 : (coreGrad / coreCount) / _focusNorm;
    final double contrast = shape == null
        ? 0.0
        : (shape.contrast / _contrastNorm).clamp(0.0, 1.0);
    final double confidence = math.max(texture, contrast).clamp(0.0, 1.0);

    bool steady = false;
    if (_hasPrev) {
      final prev = _prev;
      int diff = 0;
      for (int i = 0; i < samples.length; i++) {
        diff += (samples[i] - prev[i]).abs();
      }
      steady = (diff / samples.length) < 8.0;
    }
    _samples = _prev;
    _prev = samples;
    _hasPrev = true;

    List<Offset>? finalCorners = shape?.corners;
    Rect? finalBounds = shape?.bounds;
    if (finalCorners != null && finalCorners.length == 4) {
      finalCorners = orderClockwise(finalCorners);
      final prev = _prevShape;
      if (prev != null && prev.corners.length == 4) {
        final aligned = alignCorners(prev.corners, finalCorners);
        double totalDist = 0;
        for (int i = 0; i < 4; i++) {
          totalDist += (aligned[i] - prev.corners[i]).distance;
        }
        final avgDist = totalDist / 4.0;

        if (avgDist < _lockDeadband) {
          finalCorners = prev.corners;
          finalBounds = prev.bounds;
        } else if (avgDist > 0.10) {
          // Clearly better / reframed reading - snap to the real border.
          finalCorners = aligned;
          finalBounds = shape!.bounds;
        } else if (steady) {
          finalCorners = [
            for (int i = 0; i < 4; i++)
              Offset.lerp(prev.corners[i], aligned[i], 0.22)!,
          ];
          finalBounds = Rect.lerp(prev.bounds, shape!.bounds, 0.22);
        } else {
          finalCorners = [
            for (int i = 0; i < 4; i++)
              Offset.lerp(prev.corners[i], aligned[i], 0.40)!,
          ];
          finalBounds = Rect.lerp(prev.bounds, shape!.bounds, 0.40);
        }
      }
      _prevShape = _DocumentShape(
        finalBounds ?? shape!.bounds,
        finalCorners,
        shape?.contrast ?? prev?.contrast ?? 0,
      );
      _shapeHold = _kShapeHoldFrames;
    } else if (_prevShape != null && _shapeHold > 0) {
      _shapeHold--;
      finalCorners = _prevShape!.corners;
      finalBounds = _prevShape!.bounds;
    } else {
      _prevShape = null;
      _shapeHold = 0;
      finalCorners = null;
      finalBounds = null;
    }

    return DocumentSignal(
      confidence,
      steady,
      bounds: finalBounds,
      corners: finalCorners,
    );
  }

  static List<Offset> orderClockwise(List<Offset> corners) {
    if (corners.length != 4) return corners;
    final cx =
        (corners[0].dx + corners[1].dx + corners[2].dx + corners[3].dx) /
            4.0;
    final cy =
        (corners[0].dy + corners[1].dy + corners[2].dy + corners[3].dy) /
            4.0;
    final c = Offset(cx, cy);

    final sorted = List<Offset>.from(corners);
    sorted.sort((a, b) {
      final angleA = math.atan2(a.dy - c.dy, a.dx - c.dx);
      final angleB = math.atan2(b.dy - c.dy, b.dx - c.dx);
      return angleA.compareTo(angleB);
    });

    int tlIndex = 0;
    double minSum = double.infinity;
    for (int i = 0; i < 4; i++) {
      final sum = sorted[i].dx + sorted[i].dy;
      if (sum < minSum) {
        minSum = sum;
        tlIndex = i;
      }
    }

    return [
      sorted[tlIndex],
      sorted[(tlIndex + 1) % 4],
      sorted[(tlIndex + 2) % 4],
      sorted[(tlIndex + 3) % 4],
    ];
  }

  static List<Offset> alignCorners(
      List<Offset> reference, List<Offset> candidate) {
    if (reference.length != 4 || candidate.length != 4) return candidate;
    double bestDist = double.infinity;
    int bestShift = 0;
    for (int shift = 0; shift < 4; shift++) {
      double d = 0;
      for (int i = 0; i < 4; i++) {
        d += (reference[i] - candidate[(i + shift) % 4]).distanceSquared;
      }
      if (d < bestDist) {
        bestDist = d;
        bestShift = shift;
      }
    }
    return [for (int i = 0; i < 4; i++) candidate[(i + bestShift) % 4]];
  }

  static int _bgraLuma(List<int> bytes, int i) {
    if (i < 0 || i + 2 >= bytes.length) return 0;
    final b = bytes[i];
    final g = bytes[i + 1];
    final r = bytes[i + 2];
    return (r * 77 + g * 150 + b * 29) >> 8;
  }

  /// Median luminance of the outer ring - that is the desk / wall, not the page.
  int _backgroundLuma(List<int> samples) {
    final border = _borderLuma;
    int n = 0;
    for (int gx = 0; gx < _grid; gx++) {
      border[n++] = samples[gx];
      border[n++] = samples[(_grid - 1) * _grid + gx];
    }
    for (int gy = 1; gy < _grid - 1; gy++) {
      border[n++] = samples[gy * _grid];
      border[n++] = samples[gy * _grid + (_grid - 1)];
    }
    // Partial sort for median of the ring we filled.
    final values = border.sublist(0, n)..sort();
    return values[n ~/ 2];
  }

  _DocumentShape? _shapeFromSilhouette({
    required List<int> samples,
    required List<int> energy,
    required int bg,
    required double rx,
    required double ry,
    required double rw,
    required double rh,
  }) {
    final mask = _mask;
    // 1) Seed foreground from contrast vs desk background.
    for (int i = 0; i < _grid * _grid; i++) {
      final int d = (samples[i] - bg).abs();
      mask[i] = (d >= _fgContrast || energy[i] >= _edgeBoost * 2) ? 1 : 0;
    }

    // 1b) Reinforce real page edges: a strong gradient between a desk-like
    // cell and a page-like cell is the border Photos/Lens lock onto.
    for (int gy = 0; gy < _grid; gy++) {
      for (int gx = 0; gx < _grid - 1; gx++) {
        final int i = gy * _grid + gx;
        final int a = samples[i];
        final int b = samples[i + 1];
        if ((a - b).abs() < _edgeBoost) continue;
        final bool aBg = (a - bg).abs() < _fgContrast;
        final bool bBg = (b - bg).abs() < _fgContrast;
        if (aBg == bBg) continue;
        mask[i] = 1;
        mask[i + 1] = 1;
      }
    }
    for (int gy = 0; gy < _grid - 1; gy++) {
      for (int gx = 0; gx < _grid; gx++) {
        final int i = gy * _grid + gx;
        final int a = samples[i];
        final int b = samples[i + _grid];
        if ((a - b).abs() < _edgeBoost) continue;
        final bool aBg = (a - bg).abs() < _fgContrast;
        final bool bBg = (b - bg).abs() < _fgContrast;
        if (aBg == bBg) continue;
        mask[i] = 1;
        mask[i + _grid] = 1;
      }
    }

    // 2) Close holes (ink gaps / faint print) so the page is one solid sheet.
    _dilate(mask, _scratch);
    _dilate(_scratch, mask);
    _erode(mask, _scratch);
    _erode(_scratch, mask);

    // 3) Keep the largest connected blob - reject desk clutter / hands.
    final kept = _keepLargestBlob(mask);
    if (kept < (_grid * _grid * _minBlobFill).round()) return null;

    // 4) Bounding box of the page blob.
    int left = _grid, right = -1, top = _grid, bottom = -1;
    int fgSum = 0;
    int fgCount = 0;
    for (int gy = 0; gy < _grid; gy++) {
      for (int gx = 0; gx < _grid; gx++) {
        final int i = gy * _grid + gx;
        if (mask[i] == 0) continue;
        if (gx < left) left = gx;
        if (gx > right) right = gx;
        if (gy < top) top = gy;
        if (gy > bottom) bottom = gy;
        fgSum += samples[i];
        fgCount++;
      }
    }
    if (right < left || bottom < top || fgCount == 0) return null;

    final double cellW = rw / _grid;
    final double cellH = rh / _grid;
    // Half-cell pad only - hug the real edge, do not balloon past it.
    const double pad = 0.55;
    final double l = (rx + (left - pad) * cellW).clamp(0.0, 1.0);
    final double t = (ry + (top - pad) * cellH).clamp(0.0, 1.0);
    final double r = (rx + (right + 1 + pad) * cellW).clamp(0.0, 1.0);
    final double b = (ry + (bottom + 1 + pad) * cellH).clamp(0.0, 1.0);

    final double bw = r - l;
    final double bh = b - t;
    if (bw < _minBoundsExtent || bh < _minBoundsExtent) return null;
    final double aspect = bw / bh;
    if (aspect < _minAspect || aspect > _maxAspect) return null;

    final bounds = Rect.fromLTRB(l, t, r, b);
    final corners = _silhouetteCorners(
      mask: mask,
      rx: rx,
      ry: ry,
      cellW: cellW,
      cellH: cellH,
      left: left,
      top: top,
      right: right,
      bottom: bottom,
    );
    if (corners == null) return null;

    final double contrast = (fgSum / fgCount - bg).abs().toDouble();
    return _DocumentShape(bounds, corners, contrast);
  }

  /// Corners from silhouette **boundary** cells only (touch background).
  /// Interior text never participates, so the quad cannot bend inward.
  List<Offset>? _silhouetteCorners({
    required List<int> mask,
    required double rx,
    required double ry,
    required double cellW,
    required double cellH,
    required int left,
    required int top,
    required int right,
    required int bottom,
  }) {
    var bestSumLo = double.infinity;
    var bestDiffHi = -double.infinity;
    var bestSumHi = -double.infinity;
    var bestDiffLo = double.infinity;
    Offset? tl, tr, br, bl;
    int boundaryCount = 0;

    for (int gy = top; gy <= bottom; gy++) {
      for (int gx = left; gx <= right; gx++) {
        final int i = gy * _grid + gx;
        if (mask[i] == 0) continue;
        if (!_isBoundary(mask, gx, gy)) continue;
        boundaryCount++;

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
    if (boundaryCount < 12) return null;

    final ordered = orderClockwise([tl, tr, br, bl]);
    if (_area(ordered) < _minBoundsExtent * _minBoundsExtent) return null;

    // Reject self-intersecting / collapsed quads (bent bow-ties).
    if (!_isConvexQuad(ordered)) {
      return _rectCorners(Rect.fromPoints(
        Offset(
          math.min(tl.dx, math.min(tr.dx, math.min(br.dx, bl.dx))),
          math.min(tl.dy, math.min(tr.dy, math.min(br.dy, bl.dy))),
        ),
        Offset(
          math.max(tl.dx, math.max(tr.dx, math.max(br.dx, bl.dx))),
          math.max(tl.dy, math.max(tr.dy, math.max(br.dy, bl.dy))),
        ),
      ));
    }

    final cx = ordered.map((p) => p.dx).reduce((a, b) => a + b) / 4;
    final cy = ordered.map((p) => p.dy).reduce((a, b) => a + b) / 4;
    return [
      for (final p in ordered)
        Offset(
          (p.dx + (p.dx - cx) * _quadPad).clamp(0.0, 1.0),
          (p.dy + (p.dy - cy) * _quadPad).clamp(0.0, 1.0),
        ),
    ];
  }

  bool _isBoundary(List<int> mask, int gx, int gy) {
    for (int dy = -1; dy <= 1; dy++) {
      for (int dx = -1; dx <= 1; dx++) {
        if (dx == 0 && dy == 0) continue;
        final int x = gx + dx;
        final int y = gy + dy;
        if (x < 0 || x >= _grid || y < 0 || y >= _grid) return true;
        if (mask[y * _grid + x] == 0) return true;
      }
    }
    return false;
  }

  void _dilate(List<int> src, List<int> dst) {
    for (int gy = 0; gy < _grid; gy++) {
      for (int gx = 0; gx < _grid; gx++) {
        int v = 0;
        for (int dy = -1; dy <= 1 && v == 0; dy++) {
          final int y = gy + dy;
          if (y < 0 || y >= _grid) continue;
          for (int dx = -1; dx <= 1; dx++) {
            final int x = gx + dx;
            if (x < 0 || x >= _grid) continue;
            if (src[y * _grid + x] != 0) {
              v = 1;
              break;
            }
          }
        }
        dst[gy * _grid + gx] = v;
      }
    }
  }

  void _erode(List<int> src, List<int> dst) {
    for (int gy = 0; gy < _grid; gy++) {
      for (int gx = 0; gx < _grid; gx++) {
        // Out-of-bounds neighbours are ignored so a page that fills the
        // sample region is not eaten away at the frame edge.
        int v = src[gy * _grid + gx] == 0 ? 0 : 1;
        if (v == 0) {
          dst[gy * _grid + gx] = 0;
          continue;
        }
        for (int dy = -1; dy <= 1 && v == 1; dy++) {
          final int y = gy + dy;
          if (y < 0 || y >= _grid) continue;
          for (int dx = -1; dx <= 1; dx++) {
            final int x = gx + dx;
            if (x < 0 || x >= _grid) continue;
            if (src[y * _grid + x] == 0) {
              v = 0;
              break;
            }
          }
        }
        dst[gy * _grid + gx] = v;
      }
    }
  }

  /// Flood-label blobs; keep only the largest. Returns its cell count.
  int _keepLargestBlob(List<int> mask) {
    final labels = _labels;
    labels.fillRange(0, labels.length, 0);
    int nextLabel = 0;
    int bestLabel = 0;
    int bestCount = 0;
    final queue = _queue;

    for (int start = 0; start < mask.length; start++) {
      if (mask[start] == 0 || labels[start] != 0) continue;
      nextLabel++;
      int count = 0;
      int head = 0;
      int tail = 0;
      queue[tail++] = start;
      labels[start] = nextLabel;

      while (head < tail) {
        final int i = queue[head++];
        count++;
        final int gx = i % _grid;
        final int gy = i ~/ _grid;
        for (int dy = -1; dy <= 1; dy++) {
          for (int dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) continue;
            final int x = gx + dx;
            final int y = gy + dy;
            if (x < 0 || x >= _grid || y < 0 || y >= _grid) continue;
            final int j = y * _grid + x;
            if (mask[j] == 0 || labels[j] != 0) continue;
            labels[j] = nextLabel;
            queue[tail++] = j;
          }
        }
      }
      if (count > bestCount) {
        bestCount = count;
        bestLabel = nextLabel;
      }
    }

    if (bestLabel == 0) {
      mask.fillRange(0, mask.length, 0);
      return 0;
    }
    for (int i = 0; i < mask.length; i++) {
      mask[i] = labels[i] == bestLabel ? 1 : 0;
    }
    return bestCount;
  }

  static double _area(List<Offset> q) {
    var a = 0.0;
    for (int i = 0; i < q.length; i++) {
      final p = q[i];
      final n = q[(i + 1) % q.length];
      a += p.dx * n.dy - n.dx * p.dy;
    }
    return a.abs() / 2;
  }

  static bool _isConvexQuad(List<Offset> q) {
    if (q.length != 4) return false;
    bool? prevPositive;
    for (int i = 0; i < 4; i++) {
      final a = q[i];
      final b = q[(i + 1) % 4];
      final c = q[(i + 2) % 4];
      final cross =
          (b.dx - a.dx) * (c.dy - b.dy) - (b.dy - a.dy) * (c.dx - b.dx);
      if (cross.abs() < 1e-9) continue;
      final positive = cross > 0;
      if (prevPositive != null && positive != prevPositive) return false;
      prevPositive = positive;
    }
    return prevPositive != null;
  }

  static List<Offset> _rectCorners(Rect r) =>
      [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft];
}

class _DocumentShape {
  const _DocumentShape(this.bounds, this.corners, this.contrast);

  final Rect bounds;
  final List<Offset> corners;
  final double contrast;
}
