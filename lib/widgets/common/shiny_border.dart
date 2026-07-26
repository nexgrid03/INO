import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The soft theme's glassy border treatment.
///
/// Wraps a tile that already draws its own (classic) accent border and paints
/// a glass sheen **over** that border: a bright white light-catch arc at the
/// top-left (matching the light source of the ShinyIcon badges) and a fainter
/// echo at the bottom-right. The underlying border colour/width stays exactly
/// as in the classic theme - this only adds the shine.
///
/// Pure overlay: no layout impact, no pointer interception.
class ShinyBorder extends StatelessWidget {
  const ShinyBorder({
    super.key,
    required this.radius,
    required this.child,
    this.width = 2.5,
    this.enabled = true,
  });

  /// Corner radius of the child's border (must match for the sheen to sit
  /// exactly on the border ring).
  final double radius;

  /// Stroke width of the child's border.
  final double width;

  /// When false the child renders untouched (lets call sites keep one tree
  /// shape across themes).
  final bool enabled;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return CustomPaint(
      foregroundPainter: _ShinyBorderPainter(radius: radius, width: width),
      child: child,
    );
  }
}

class _ShinyBorderPainter extends CustomPainter {
  _ShinyBorderPainter({required this.radius, required this.width});

  final double radius;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.shortestSide <= width * 2) return;
    final rect = Offset.zero & size;
    final ring = RRect.fromRectAndRadius(
      rect,
      Radius.circular(radius),
    ).deflate(width / 2);

    // The glass sheen riding on the accent border: a white-hot catch parked at
    // the top-left (where the badges' gloss sits) and a soft echo opposite.
    // Everything else stays fully transparent so the classic border colour
    // shows through untouched.
    canvas.drawRRect(
      ring,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..shader = SweepGradient(
          transform: const GradientRotation(-math.pi),
          colors: [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.92), // top-left light catch
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.38), // bottom-right echo
            Colors.white.withValues(alpha: 0),
          ],
          stops: const [0.0, 0.12, 0.34, 0.62, 0.86],
        ).createShader(rect),
    );

    // A hairline inner rim just inside the border - the crisp glass edge.
    final rimW = math.max(0.9, width * 0.5);
    canvas.drawRRect(
      ring.deflate(width / 2 + rimW / 2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = rimW
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.85),
            Colors.white.withValues(alpha: 0),
          ],
          stops: const [0.0, 0.55],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_ShinyBorderPainter old) =>
      old.radius != radius || old.width != width;
}
