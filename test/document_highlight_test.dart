import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/services/live_document_detector.dart';
import 'package:inoapp/widgets/scan/document_highlight.dart';

/// Covers the two halves of the live "blue border around the document"
/// highlight: the detector that decides where the document is in the raw
/// camera frame, and the projection that puts that outline on screen over a
/// rotated, `BoxFit.cover`-cropped preview.

const int _w = 640;
const int _h = 480;

/// Builds a single-plane (luminance) [CameraImage] from a pixel painter.
CameraImage _frame(int Function(int x, int y) luma) {
  final bytes = Uint8List(_w * _h);
  for (int y = 0; y < _h; y++) {
    final row = y * _w;
    for (int x = 0; x < _w; x++) {
      bytes[row + x] = luma(x, y) & 0xFF;
    }
  }
  return CameraImage.fromPlatformInterface(
    CameraImageData(
      format: const CameraImageFormat(ImageFormatGroup.yuv420, raw: 35),
      width: _w,
      height: _h,
      planes: <CameraImagePlane>[
        CameraImagePlane(bytes: bytes, bytesPerRow: _w, bytesPerPixel: 1),
      ],
    ),
  );
}

/// A bright page carrying text-like rows, on a flat mid-grey desk, shaped as an
/// arbitrary quad - so a document held at an angle renders exactly as the
/// sensor would see it.
CameraImage _quadFrame(List<Offset> corners) {
  final px = [for (final c in corners) Offset(c.dx * _w, c.dy * _h)];
  final minY = px.map((p) => p.dy).reduce(math.min);

  bool inside(double x, double y) {
    // Even-odd ray cast - no convexity assumed.
    var hit = false;
    for (var i = 0, j = px.length - 1; i < px.length; j = i++) {
      final a = px[i];
      final b = px[j];
      if ((a.dy > y) != (b.dy > y) &&
          x < (b.dx - a.dx) * (y - a.dy) / (b.dy - a.dy) + a.dx) {
        hit = !hit;
      }
    }
    return hit;
  }

  return _frame((x, y) {
    final fx = x.toDouble();
    final fy = y.toDouble();
    if (!inside(fx, fy)) return 90; // desk
    // A quiet margin just inside the edge, then text lines - the structure a
    // real page has, and what gives the detector its edge energy.
    final nearEdge = !inside(fx - 14, fy) ||
        !inside(fx + 14, fy) ||
        !inside(fx, fy - 14) ||
        !inside(fx, fy + 14);
    if (nearEdge) return 225; // paper margin
    if ((y - minY.round()) % 12 < 4) return 30; // ink
    return 225; // paper
  });
}

CameraImage _documentFrame(Rect doc) => _quadFrame(
      [doc.topLeft, doc.topRight, doc.bottomRight, doc.bottomLeft],
    );

/// Distance from [p] to the nearest of [corners], in normalised units.
double _nearestCorner(Offset p, List<Offset> corners) =>
    corners.map((c) => (c - p).distance).reduce(math.min);

void main() {
  group('LiveDocumentDetector outline', () {
    test('traces a framed document and ignores an empty scene', () {
      const doc = Rect.fromLTRB(0.25, 0.30, 0.75, 0.72);
      final detector = LiveDocumentDetector();
      final signal = detector.analyze(_documentFrame(doc));

      expect(signal.confidence, greaterThan(0.5),
          reason: 'a texted page should read as a document');
      final bounds = signal.bounds;
      expect(bounds, isNotNull);
      expect(signal.corners, hasLength(4));

      // The box pads outward slightly, so it should surround the page closely
      // without ever cutting into it.
      const tolerance = 0.08;
      expect(bounds!.left, closeTo(doc.left, tolerance));
      expect(bounds.top, closeTo(doc.top, tolerance));
      expect(bounds.right, closeTo(doc.right, tolerance));
      expect(bounds.bottom, closeTo(doc.bottom, tolerance));
      expect(bounds.left, lessThanOrEqualTo(doc.left));
      expect(bounds.right, greaterThanOrEqualTo(doc.right));
    });

    test('a flat scene yields no outline at all', () {
      final detector = LiveDocumentDetector();
      final signal = detector.analyze(_frame((x, y) => 120));

      expect(signal.confidence, lessThan(0.35));
      expect(signal.bounds, isNull,
          reason: 'an empty wall must never draw a highlight border');
      expect(signal.corners, isNull);
    });

    test('a page held at an angle yields a skewed quad, not an upright box',
        () {
      // The case from the report: a document photographed off-square. Its
      // corners must follow the page, so the outline leans with it.
      const quad = [
        Offset(0.20, 0.24),
        Offset(0.82, 0.16),
        Offset(0.86, 0.70),
        Offset(0.24, 0.78),
      ];
      final corners = LiveDocumentDetector().analyze(_quadFrame(quad)).corners;

      expect(corners, hasLength(4));
      for (final truth in quad) {
        expect(_nearestCorner(truth, corners!), lessThan(0.12),
            reason: 'no detected corner landed near $truth');
      }

      // The giveaway that this is a real quad and not a bounding box: the top
      // edge rises left-to-right and the bottom edge leans, matching the page.
      expect(corners![1].dy, lessThan(corners[0].dy - 0.02));
      expect(corners[2].dx, greaterThan(corners[3].dx + 0.02));
    });

    test('a square-on page still yields a near-upright quad', () {
      const doc = Rect.fromLTRB(0.22, 0.26, 0.78, 0.74);
      final corners =
          LiveDocumentDetector().analyze(_documentFrame(doc)).corners;

      expect(corners, hasLength(4));
      // Top two corners level, bottom two level: no phantom skew.
      expect((corners![0].dy - corners[1].dy).abs(), lessThan(0.05));
      expect((corners[2].dy - corners[3].dy).abs(), lessThan(0.05));
    });

    test('follows the document as it moves across the frame', () {
      final detector = LiveDocumentDetector();
      final left = detector
          .analyze(_documentFrame(const Rect.fromLTRB(0.08, 0.3, 0.48, 0.7)))
          .bounds;
      final right = detector
          .analyze(_documentFrame(const Rect.fromLTRB(0.52, 0.3, 0.92, 0.7)))
          .bounds;

      expect(left, isNotNull);
      expect(right, isNotNull);
      expect(left!.center.dx, lessThan(right!.center.dx - 0.3));
    });

    test('reports steadiness only once the frame stops changing', () {
      const doc = Rect.fromLTRB(0.25, 0.3, 0.75, 0.7);
      final detector = LiveDocumentDetector();
      detector.analyze(_documentFrame(doc));
      expect(detector.analyze(_documentFrame(doc)).steady, isTrue);
      expect(
        detector
            .analyze(_documentFrame(const Rect.fromLTRB(0.1, 0.1, 0.6, 0.6)))
            .steady,
        isFalse,
      );
    });
  });

  group('projection', () {
    // A 1280x720 sensor frame shown portrait-swapped, covering a 400x800 view.
    const source = Size(720, 1280);
    const canvas = Size(400, 800);

    Rect project(Rect bounds, {int turns = 1, bool mirror = false}) =>
        projectDocumentBounds(
          bounds: bounds,
          sourceSize: source,
          canvasSize: canvas,
          quarterTurns: turns,
          mirror: mirror,
        )!;

    Offset point(Offset p, {int turns = 1, bool mirror = false}) =>
        projectDocumentPoint(
          point: p,
          sourceSize: source,
          canvasSize: canvas,
          quarterTurns: turns,
          mirror: mirror,
        )!;

    test('a centred rect stays centred', () {
      final out = project(const Rect.fromLTRB(0.25, 0.25, 0.75, 0.75));
      expect(out.center.dx, closeTo(canvas.width / 2, 0.001));
      expect(out.center.dy, closeTo(canvas.height / 2, 0.001));
    });

    test('90 degrees clockwise: the sensor left edge becomes the screen top',
        () {
      final out = project(const Rect.fromLTRB(0.0, 0.3, 0.2, 0.7));
      expect(out.top, lessThan(canvas.height * 0.1));
      expect(out.bottom, lessThan(canvas.height * 0.35));
    });

    test('90 degrees clockwise: the sensor top edge becomes the screen right',
        () {
      final out = project(const Rect.fromLTRB(0.3, 0.0, 0.7, 0.2));
      expect(out.right, greaterThan(canvas.width * 0.9));
    });

    test('270 degrees mirrors 90 across both axes', () {
      const r = Rect.fromLTRB(0.1, 0.2, 0.4, 0.6);
      final a = project(r, turns: 1);
      final b = project(r, turns: 3);
      expect(a.center.dx + b.center.dx, closeTo(canvas.width, 0.001));
      expect(a.center.dy + b.center.dy, closeTo(canvas.height, 0.001));
    });

    test('a front camera flips horizontally, never vertically', () {
      const r = Rect.fromLTRB(0.1, 0.2, 0.4, 0.6);
      final plain = project(r);
      final flipped = project(r, mirror: true);
      expect(plain.center.dx + flipped.center.dx, closeTo(canvas.width, 0.001));
      expect(plain.center.dy, closeTo(flipped.center.dy, 0.001));
    });

    test('cover crops the overflowing axis instead of squashing it', () {
      // source 720x1280 (0.5625) into 400x800 (0.5) - width overflows and is
      // cropped, so a full-frame rect must extend past the canvas sideways
      // while fitting exactly top to bottom.
      final full = project(const Rect.fromLTRB(0, 0, 1, 1));
      expect(full.top, closeTo(0, 0.001));
      expect(full.bottom, closeTo(canvas.height, 0.001));
      expect(full.left, lessThan(0));
      expect(full.right, greaterThan(canvas.width));
    });

    test('a skewed quad stays skewed through the projection', () {
      // Four corners that are NOT an upright rectangle must not come out as
      // one - that is the whole point of moving off a bounding box.
      const quad = [
        Offset(0.20, 0.24),
        Offset(0.82, 0.16),
        Offset(0.86, 0.70),
        Offset(0.24, 0.78),
      ];
      final mapped = [for (final c in quad) point(c)];

      // Under a 90 degrees turn the sensor's top edge maps to the screen's
      // right, so the quad's "top" pair must differ in x on screen.
      expect((mapped[0].dx - mapped[1].dx).abs(), greaterThan(1),
          reason: 'the tilt must survive rotation, not flatten out');
      // All four corners stay distinct - no collapse into a line.
      for (var i = 0; i < 4; i++) {
        for (var j = i + 1; j < 4; j++) {
          expect((mapped[i] - mapped[j]).distance, greaterThan(1));
        }
      }
    });

    test('rotateSensorPoint is the transform projection is built on', () {
      // The capture path crops using rotateSensorPoint alone (a still is the
      // whole frame, with no BoxFit.cover crop to replay). If the two ever
      // disagree, the blue border and the crop drift apart - so pin that the
      // projection really is rotation-then-fit on the same rotation.
      for (final turns in const [0, 1, 2, 3]) {
        for (final mirror in const [false, true]) {
          for (final c in const [
            Offset(0.1, 0.2),
            Offset(0.8, 0.15),
            Offset(0.45, 0.9),
          ]) {
            final rotated = rotateSensorPoint(c,
                quarterTurns: turns, mirror: mirror);
            final projected = projectDocumentPoint(
              point: c,
              sourceSize: source,
              canvasSize: canvas,
              quarterTurns: turns,
              mirror: mirror,
            )!;
            // Undo the cover fit and the rotated point must come back out.
            final fit = math.max(
              canvas.width / source.width,
              canvas.height / source.height,
            );
            final w = source.width * fit;
            final h = source.height * fit;
            final back = Offset(
              (projected.dx - (canvas.width - w) / 2) / w,
              (projected.dy - (canvas.height - h) / 2) / h,
            );
            expect(back.dx, closeTo(rotated.dx, 1e-9));
            expect(back.dy, closeTo(rotated.dy, 1e-9));
          }
        }
      }
    });

    test('a quarter turn moves the sensor left edge to the top', () {
      // The one that matters on real hardware: a back camera reporting
      // sensorOrientation 90. A point at the sensor's left edge is at the top
      // of the upright still, so a page framed at the top of the screen crops
      // from the correct end of the JPEG.
      final p = rotateSensorPoint(const Offset(0.0, 0.5),
          quarterTurns: 1, mirror: false);
      expect(p.dy, closeTo(0.0, 1e-9));
      final q = rotateSensorPoint(const Offset(0.5, 0.0),
          quarterTurns: 1, mirror: false);
      expect(q.dx, closeTo(1.0, 1e-9));
    });

    test('no rotation and no mirror leaves a point exactly where it was', () {
      const p = Offset(0.3, 0.7);
      expect(rotateSensorPoint(p, quarterTurns: 0, mirror: false), p);
      expect(rotateSensorPoint(p, quarterTurns: 4, mirror: false), p);
    });

    test('four turns is the identity, so the quad never creeps', () {
      const quad = [
        Offset(0.20, 0.24),
        Offset(0.82, 0.16),
        Offset(0.86, 0.70),
        Offset(0.24, 0.78),
      ];
      for (final c in quad) {
        var p = c;
        for (var i = 0; i < 4; i++) {
          p = rotateSensorPoint(p, quarterTurns: 1, mirror: false);
        }
        expect(p.dx, closeTo(c.dx, 1e-9));
        expect(p.dy, closeTo(c.dy, 1e-9));
      }
    });

    test('rotation preserves the quad - area and corner order survive', () {
      // A crop is only correct if the four corners still read TL, TR, BR, BL
      // after rotation; a reordered quad rectifies to a mirrored or bow-tied
      // page.
      const quad = [
        Offset(0.20, 0.24),
        Offset(0.82, 0.16),
        Offset(0.86, 0.70),
        Offset(0.24, 0.78),
      ];
      double area(List<Offset> q) {
        var a = 0.0;
        for (var i = 0; i < q.length; i++) {
          final p = q[i];
          final n = q[(i + 1) % q.length];
          a += p.dx * n.dy - n.dx * p.dy;
        }
        return a.abs() / 2;
      }

      final rotated = [
        for (final c in quad)
          rotateSensorPoint(c, quarterTurns: 1, mirror: false),
      ];
      expect(area(rotated), closeTo(area(quad), 1e-9));
      // Still traversed in the same rotational direction (no flip).
      double signedArea(List<Offset> q) {
        var a = 0.0;
        for (var i = 0; i < q.length; i++) {
          final p = q[i];
          final n = q[(i + 1) % q.length];
          a += p.dx * n.dy - n.dx * p.dy;
        }
        return a;
      }

      expect(signedArea(rotated).sign, signedArea(quad).sign);
    });

    test('a degenerate canvas projects nothing', () {
      expect(
        projectDocumentPoint(
          point: Offset.zero,
          sourceSize: source,
          canvasSize: Size.zero,
          quarterTurns: 1,
          mirror: false,
        ),
        isNull,
      );
    });
  });
}
