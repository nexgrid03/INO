import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A very subtle field of slowly drifting shapes painted behind the content
/// to make a screen feel "alive" without distracting the user.
///
/// Driven by a single looping [animation] (0→1). Everything is painted on one
/// [CustomPaint] inside a [RepaintBoundary], so the drift never rebuilds the
/// widget tree above it — just repaints this layer. Opacity is kept very low.
class FloatingParticles extends StatelessWidget {
  const FloatingParticles({super.key, required this.animation});

  /// A looping 0→1 value (e.g. an AnimationController on `repeat()`).
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          return CustomPaint(
            size: Size.infinite,
            painter: _ParticlesPainter(animation.value),
          );
        },
      ),
    );
  }
}

/// One drifting shape. Positions/sizes are expressed as fractions of the
/// canvas so the field scales to any screen.
class _Particle {
  const _Particle({
    required this.x,
    required this.y,
    required this.radius,
    required this.phase,
    required this.driftX,
    required this.driftY,
    required this.opacity,
    required this.color,
    required this.isCircle,
  });

  final double x; // base position (0–1)
  final double y;
  final double radius; // logical pixels
  final double phase; // 0–1, offsets the drift cycle
  final double driftX; // drift amplitude as a fraction of width/height
  final double driftY;
  final double opacity;
  final Color color;
  final bool isCircle;
}

/// A fixed, hand-placed set of particles — deterministic (no RNG) so the
/// layout is stable and reviewable.
const List<_Particle> _particles = [
  _Particle(x: 0.18, y: 0.18, radius: 5, phase: 0.0, driftX: 0.02, driftY: 0.03, opacity: 0.10, color: AppColors.primaryGreen, isCircle: true),
  _Particle(x: 0.82, y: 0.14, radius: 4, phase: 0.3, driftX: 0.025, driftY: 0.02, opacity: 0.08, color: AppColors.lightBlue, isCircle: false),
  _Particle(x: 0.10, y: 0.55, radius: 3, phase: 0.6, driftX: 0.02, driftY: 0.025, opacity: 0.07, color: AppColors.skyBlue, isCircle: true),
  _Particle(x: 0.90, y: 0.50, radius: 6, phase: 0.15, driftX: 0.015, driftY: 0.03, opacity: 0.06, color: AppColors.primaryGreen, isCircle: false),
  _Particle(x: 0.30, y: 0.80, radius: 4, phase: 0.45, driftX: 0.03, driftY: 0.02, opacity: 0.08, color: AppColors.lightBlue, isCircle: true),
  _Particle(x: 0.70, y: 0.85, radius: 3, phase: 0.75, driftX: 0.02, driftY: 0.025, opacity: 0.07, color: AppColors.primaryGreen, isCircle: true),
  _Particle(x: 0.50, y: 0.30, radius: 4, phase: 0.9, driftX: 0.025, driftY: 0.02, opacity: 0.06, color: AppColors.skyBlue, isCircle: false),
  _Particle(x: 0.60, y: 0.62, radius: 3, phase: 0.5, driftX: 0.02, driftY: 0.03, opacity: 0.07, color: AppColors.lightBlue, isCircle: true),
];

class _ParticlesPainter extends CustomPainter {
  _ParticlesPainter(this.t);

  /// Looping time value (0–1).
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in _particles) {
      // Drift along a slow circular path using sine/cosine of the cycle.
      final double angle = 2 * math.pi * (t + p.phase);
      final double dx = (p.x + math.sin(angle) * p.driftX) * size.width;
      final double dy = (p.y + math.cos(angle) * p.driftY) * size.height;

      final paint = Paint()..color = p.color.withValues(alpha: p.opacity);

      if (p.isCircle) {
        canvas.drawCircle(Offset(dx, dy), p.radius, paint);
      } else {
        // A small rotated square (diamond) for shape variety.
        canvas.save();
        canvas.translate(dx, dy);
        canvas.rotate(math.pi / 4);
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset.zero,
            width: p.radius * 2,
            height: p.radius * 2,
          ),
          paint,
        );
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(_ParticlesPainter oldDelegate) => oldDelegate.t != t;
}
