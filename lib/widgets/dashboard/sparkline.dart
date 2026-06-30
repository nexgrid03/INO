import 'package:flutter/material.dart';

/// A lightweight mini trend line drawn with [CustomPainter] — no chart package.
///
/// Renders a smooth-ish polyline of [values] with a soft gradient fill beneath
/// it, plus a dot on the latest point. Colour comes from [color] so callers can
/// tint it green/red to match the quote's direction. Matches the hand-drawn,
/// dependency-free aesthetic already used by `DirectionalReveal`.
class Sparkline extends StatelessWidget {
  const Sparkline({
    super.key,
    required this.values,
    required this.color,
    this.strokeWidth = 2.2,
    this.fill = true,
  });

  final List<double> values;
  final Color color;
  final double strokeWidth;
  final bool fill;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _SparklinePainter(
        values: values,
        color: color,
        strokeWidth: strokeWidth,
        fill: fill,
      ),
      size: Size.infinite,
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({
    required this.values,
    required this.color,
    required this.strokeWidth,
    required this.fill,
  });

  final List<double> values;
  final Color color;
  final double strokeWidth;
  final bool fill;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;

    final minV = values.reduce((a, b) => a < b ? a : b);
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final range = (maxV - minV).abs() < 1e-9 ? 1.0 : (maxV - minV);

    // Leave a little vertical padding so the line/dot never clips the edge.
    const pad = 3.0;
    final h = size.height - pad * 2;
    final dx = size.width / (values.length - 1);

    Offset pointAt(int i) {
      final norm = (values[i] - minV) / range;
      return Offset(dx * i, pad + h - norm * h);
    }

    final path = Path()..moveTo(0, pointAt(0).dy);
    for (var i = 1; i < values.length; i++) {
      final p0 = pointAt(i - 1);
      final p1 = pointAt(i);
      // Gentle cubic smoothing between successive points.
      final cx = (p0.dx + p1.dx) / 2;
      path.cubicTo(cx, p0.dy, cx, p1.dy, p1.dx, p1.dy);
    }

    if (fill) {
      final fillPath = Path.from(path)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      final fillPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.28),
            color.withValues(alpha: 0.0),
          ],
        ).createShader(Offset.zero & size);
      canvas.drawPath(fillPath, fillPaint);
    }

    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, linePaint);

    // Latest-point marker.
    final last = pointAt(values.length - 1);
    canvas.drawCircle(last, strokeWidth + 1.2, Paint()..color = color);
    canvas.drawCircle(
      last,
      strokeWidth + 1.2,
      Paint()
        ..color = color.withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.values != values || old.color != color;
}
