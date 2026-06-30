import 'package:flutter/material.dart';

import '../../models/dashboard_models.dart';

/// A clean asset-allocation donut drawn with [CustomPainter].
///
/// Each [AssetAllocation] becomes an arc sized by its share of the total, with
/// a small gap between segments for a premium, "Apple Health ring" feel. The
/// [progress] animation (0→1) sweeps the segments in on entrance. A centre
/// label can be supplied via [centerTop] / [centerBottom].
class DonutChart extends StatelessWidget {
  const DonutChart({
    super.key,
    required this.allocations,
    this.progress = 1.0,
    this.size = 132,
    this.centerTop,
    this.centerBottom,
    this.centerColor,
  });

  final List<AssetAllocation> allocations;
  final double progress;
  final double size;
  final String? centerTop;
  final String? centerBottom;
  final Color? centerColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size.square(size),
            painter: _DonutPainter(allocations: allocations, progress: progress),
          ),
          if (centerTop != null || centerBottom != null)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (centerTop != null)
                  Text(
                    centerTop!,
                    style: TextStyle(
                      fontSize: 11,
                      color: centerColor?.withValues(alpha: 0.7),
                    ),
                  ),
                if (centerBottom != null)
                  Text(
                    centerBottom!,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: centerColor,
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.allocations, required this.progress});

  final List<AssetAllocation> allocations;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final total = allocations.fold<double>(0, (s, a) => s + a.value);
    if (total <= 0) return;

    final stroke = size.width * 0.13;
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = (size.width - stroke) / 2;
    final arcRect = Rect.fromCircle(center: center, radius: radius);

    const startBase = -1.5708; // -90° (12 o'clock)
    const gap = 0.05; // radians between segments
    var start = startBase;
    final sweepTotal = 6.28318 * progress; // 2π * progress

    for (final a in allocations) {
      final fullSweep = (a.value / total) * 6.28318;
      // Clamp this segment to the animated reveal window.
      final remaining = (startBase + sweepTotal) - start;
      if (remaining <= 0) break;
      final sweep = (fullSweep - gap).clamp(0.0, remaining);
      if (sweep <= 0) {
        start += fullSweep;
        continue;
      }
      final paint = Paint()
        ..color = a.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(arcRect, start, sweep, false, paint);
      start += fullSweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.progress != progress || old.allocations != allocations;
}
