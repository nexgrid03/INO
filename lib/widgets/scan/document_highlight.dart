import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../screens/scan/scan_theme.dart';
import 'scanner_overlay.dart' show ScanOverlayState;

/// The blue outline that traces the document the camera is actually looking at,
/// painted over the live preview.
///
/// [corners] carries the detector's latest reading as four points - top-left,
/// top-right, bottom-right, bottom-left - normalised to the raw camera frame
/// (0..1 in *sensor* coordinates). A page held at an angle is a skewed
/// quadrilateral on the sensor, so the outline is a real polygon rather than an
/// upright rectangle: each corner is rotated into display space with
/// [quarterTurns] / [mirror] and put through the same `BoxFit.cover` fit the
/// preview uses ([sourceSize]).
///
/// It listens to [corners] directly rather than taking a plain value so the
/// ~7 readings a second never rebuild the camera preview above it - only this
/// painter repaints. Purely decorative: it never intercepts touches.
class DocumentHighlight extends StatefulWidget {
  const DocumentHighlight({
    super.key,
    required this.corners,
    required this.state,
    required this.sourceSize,
    this.quarterTurns = 1,
    this.mirror = false,
  });

  /// Latest document quad in normalised sensor coordinates (TL, TR, BR, BL), or
  /// null when the detector could not isolate one this frame.
  final ValueListenable<List<Offset>?> corners;

  /// Drives the outline's weight and colour: blue once detected, brighter and
  /// heavier when held steady and ready to shoot.
  final ScanOverlayState state;

  /// The preview's un-cropped size in display space (portrait-swapped), used
  /// to reproduce the preview's `BoxFit.cover` crop. Only the aspect matters.
  final Size sourceSize;

  /// Clockwise quarter turns mapping sensor space onto display space (1 for the
  /// usual 90° back camera in portrait).
  final int quarterTurns;

  /// Horizontal flip, for a front-facing (mirrored) preview.
  final bool mirror;

  @override
  State<DocumentHighlight> createState() => _DocumentHighlightState();
}

class _DocumentHighlightState extends State<DocumentHighlight>
    with TickerProviderStateMixin {
  /// Fades the outline in when a document appears and out when it is lost, so
  /// it never pops.
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    reverseDuration: const Duration(milliseconds: 180),
  );

  /// Eases `documentDetected` → `readyToScan` (brighter, heavier).
  late final AnimationController _lock = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );

  /// Glides the outline between successive detector readings instead of letting
  /// it snap around at the sampling rate.
  late final AnimationController _move = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 140),
    value: 1,
  );

  List<Offset>? _from;
  List<Offset>? _to;

  @override
  void initState() {
    super.initState();
    widget.corners.addListener(_onCorners);
    _onCorners();
    _syncLock();
  }

  @override
  void didUpdateWidget(covariant DocumentHighlight old) {
    super.didUpdateWidget(old);
    if (widget.corners != old.corners) {
      old.corners.removeListener(_onCorners);
      widget.corners.addListener(_onCorners);
      _onCorners();
    }
    if (widget.state != old.state) _syncLock();
  }

  @override
  void dispose() {
    widget.corners.removeListener(_onCorners);
    _reveal.dispose();
    _lock.dispose();
    _move.dispose();
    super.dispose();
  }

  void _onCorners() {
    final next = widget.corners.value;
    if (next == null || next.length != 4) {
      // Keep the last quad on screen and fade it out - dropping it the instant
      // one frame misses reads as a flicker.
      if (_reveal.value != 0) _reveal.reverse();
      return;
    }
    // A quad arriving after the outline faded out has no meaningful "from" -
    // place it and fade in, rather than sliding across from a stale position.
    _from = _reveal.value == 0 ? null : _quadNow();
    _to = next;
    _move
      ..value = 0
      ..forward();
    if (_reveal.status != AnimationStatus.completed) _reveal.forward();
  }

  void _syncLock() {
    if (widget.state == ScanOverlayState.ready) {
      _lock.forward();
    } else {
      _lock.reverse();
    }
  }

  /// The quad the painter should use right now, mid-glide.
  List<Offset>? _quadNow() {
    final from = _from;
    final to = _to;
    if (to == null) return null;
    if (from == null || from.length != to.length) return to;
    final t = Curves.easeOutCubic.transform(_move.value);
    return [
      for (var i = 0; i < to.length; i++) Offset.lerp(from[i], to[i], t)!,
    ];
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: Listenable.merge([_reveal, _lock, _move]),
          builder: (context, _) {
            final quad = _quadNow();
            final reveal = Curves.easeOut.transform(_reveal.value);
            if (quad == null || reveal <= 0.01) {
              return const SizedBox.expand();
            }
            return CustomPaint(
              painter: _HighlightPainter(
                corners: quad,
                reveal: reveal,
                lock: Curves.easeOut.transform(_lock.value),
                sourceSize: widget.sourceSize,
                quarterTurns: widget.quarterTurns,
                mirror: widget.mirror,
              ),
              child: const SizedBox.expand(),
            );
          },
        ),
      ),
    );
  }
}

class _HighlightPainter extends CustomPainter {
  _HighlightPainter({
    required this.corners,
    required this.reveal,
    required this.lock,
    required this.sourceSize,
    required this.quarterTurns,
    required this.mirror,
  });

  /// Document quad in normalised sensor coordinates (TL, TR, BR, BL).
  final List<Offset> corners;

  /// 0 = hidden … 1 = fully shown.
  final double reveal;

  /// 0 = detected … 1 = ready to scan.
  final double lock;

  final Size sourceSize;
  final int quarterTurns;
  final bool mirror;

  @override
  void paint(Canvas canvas, Size size) {
    final points = <Offset>[];
    for (final c in corners) {
      final p = projectDocumentPoint(
        point: c,
        sourceSize: sourceSize,
        canvasSize: size,
        quarterTurns: quarterTurns,
        mirror: mirror,
      );
      if (p == null) return;
      points.add(p);
    }

    final path = Path()..addPolygon(points, true);

    // ---- Interior wash - just enough to read as "this is the document" -----
    canvas.drawPath(
      path,
      Paint()
        ..color =
            ScanColors.accent.withValues(alpha: reveal * (0.08 + 0.06 * lock)),
    );

    // ---- Soft outer glow ---------------------------------------------------
    canvas.drawPath(
      path,
      Paint()
        ..color = ScanColors.accent.withValues(alpha: reveal * 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5 + 3 * lock
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 + 3 * lock),
    );

    // ---- The border itself -------------------------------------------------
    canvas.drawPath(
      path,
      Paint()
        ..color = Color.lerp(ScanColors.accent, ScanColors.accentDeep, lock)!
            .withValues(alpha: reveal)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4 + 1.2 * lock
        ..strokeJoin = StrokeJoin.round,
    );

    // ---- Corner ticks - short accents running from each vertex along both
    // of its edges, so the quad's corners read even over a busy page.
    final tick = Paint()
      ..color = Colors.white.withValues(alpha: reveal * (0.55 + 0.35 * lock))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3 + 0.8 * lock
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      for (final neighbour in [
        points[(i + 1) % points.length],
        points[(i + points.length - 1) % points.length],
      ]) {
        final v = neighbour - p;
        final len = v.distance;
        if (len < 1) continue;
        // A fifth of the edge, capped, so ticks never meet on a small quad.
        final run = math.min(len * 0.2, 26.0);
        canvas.drawLine(p, p + v / len * run, tick);
      }
    }
  }

  @override
  bool shouldRepaint(_HighlightPainter old) =>
      !listEquals(old.corners, corners) ||
      old.reveal != reveal ||
      old.lock != lock ||
      old.sourceSize != sourceSize ||
      old.quarterTurns != quarterTurns ||
      old.mirror != mirror;
}

/// Maps a point normalised to the raw camera frame onto canvas pixels: rotate
/// [quarterTurns] clockwise into display space (and [mirror] for a front
/// camera), then replay the preview's `BoxFit.cover` crop of [sourceSize] into
/// [canvasSize].
///
/// Returns null when either size is degenerate. Exposed for tests - the
/// rotation is the one piece of this widget that cannot be eyeballed.
@visibleForTesting
Offset? projectDocumentPoint({
  required Offset point,
  required Size sourceSize,
  required Size canvasSize,
  required int quarterTurns,
  required bool mirror,
}) {
  if (canvasSize.isEmpty || sourceSize.isEmpty) return null;

  final p = rotateSensorPoint(
    point,
    quarterTurns: quarterTurns,
    mirror: mirror,
  );

  final double fit = math.max(
    canvasSize.width / sourceSize.width,
    canvasSize.height / sourceSize.height,
  );
  final double w = sourceSize.width * fit;
  final double h = sourceSize.height * fit;
  return Offset(
    (canvasSize.width - w) / 2 + p.dx * w,
    (canvasSize.height - h) / 2 + p.dy * h,
  );
}

/// Turns a point normalised to the raw sensor frame into one normalised to the
/// *upright* frame the user actually sees - [quarterTurns] clockwise, then a
/// horizontal flip for a mirrored front camera.
///
/// Shared deliberately. The preview overlay uses it (via [projectDocumentPoint],
/// which then applies the preview's `BoxFit.cover` crop) and so does the capture
/// path, which needs the same rotation but no crop - a still is the whole frame,
/// not the slice the screen had room for. One transform, so the border the user
/// saw and the crop they get cannot drift apart.
Offset rotateSensorPoint(
  Offset point, {
  required int quarterTurns,
  required bool mirror,
}) {
  var p = point;
  for (int i = 0; i < (quarterTurns % 4 + 4) % 4; i++) {
    // 90° clockwise: (x, y) → (1 - y, x).
    p = Offset(1 - p.dy, p.dx);
  }
  return mirror ? Offset(1 - p.dx, p.dy) : p;
}

/// [projectDocumentPoint] applied to a rect's opposite corners, returned as the
/// upright box that contains them. Exposed for tests.
@visibleForTesting
Rect? projectDocumentBounds({
  required Rect bounds,
  required Size sourceSize,
  required Size canvasSize,
  required int quarterTurns,
  required bool mirror,
}) {
  final mapped = <Offset>[];
  for (final c in [bounds.topLeft, bounds.bottomRight]) {
    final p = projectDocumentPoint(
      point: c,
      sourceSize: sourceSize,
      canvasSize: canvasSize,
      quarterTurns: quarterTurns,
      mirror: mirror,
    );
    if (p == null) return null;
    mapped.add(p);
  }
  return Rect.fromPoints(mapped[0], mapped[1]);
}
