import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// The animated document-detection frame painted over the camera feed.
///
/// Four green corner brackets, a soft detection border that brightens once a
/// document is "detected", and a scan line that sweeps top-to-bottom — the
/// familiar, trustworthy language of Adobe Scan / Microsoft Lens. Purely
/// decorative: it sits above the live preview and never intercepts touches.
class ScannerOverlay extends StatefulWidget {
  const ScannerOverlay({super.key, required this.detected});

  /// When true the border glows brighter and the scan line eases out — the
  /// "locked on" look.
  final bool detected;

  @override
  State<ScannerOverlay> createState() => _ScannerOverlayState();
}

class _ScannerOverlayState extends State<ScannerOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final border = widget.detected
        ? AppColors.primaryGreen
        : AppColors.primaryGreen.withValues(alpha: 0.7);
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          return CustomPaint(
            painter: _FramePainter(
              progress: _c.value,
              detected: widget.detected,
              color: border,
            ),
            child: const SizedBox.expand(),
          );
        },
      ),
    );
  }
}

class _FramePainter extends CustomPainter {
  _FramePainter({
    required this.progress,
    required this.detected,
    required this.color,
  });

  final double progress;
  final bool detected;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const radius = 20.0;
    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(radius),
    );

    // Soft outer border.
    final borderPaint = Paint()
      ..color = color.withValues(alpha: detected ? 0.9 : 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = detected ? 2.6 : 1.6;
    canvas.drawRRect(rect, borderPaint);

    // Sweeping scan line (fades out once locked on).
    if (!detected) {
      final y = size.height * Curves.easeInOut.transform(progress);
      final lineGradient = LinearGradient(
        colors: [
          color.withValues(alpha: 0.0),
          color.withValues(alpha: 0.55),
          color.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, y - 18, size.width, 36));
      final linePaint = Paint()..shader = lineGradient;
      canvas.drawRect(Rect.fromLTWH(0, y - 18, size.width, 36), linePaint);
      final corePaint = Paint()
        ..color = color.withValues(alpha: 0.85)
        ..strokeWidth = 2;
      canvas.drawLine(Offset(8, y), Offset(size.width - 8, y), corePaint);
    }

    // Corner brackets.
    const len = 30.0;
    final cornerPaint = Paint()
      ..color = AppColors.primaryGreen
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.4
      ..strokeCap = StrokeCap.round;
    const o = 3.0; // small inset so the stroke sits inside the frame
    // Top-left.
    canvas.drawPath(
      Path()
        ..moveTo(o, o + len)
        ..lineTo(o, o + radius)
        ..quadraticBezierTo(o, o, o + radius, o)
        ..lineTo(o + len, o),
      cornerPaint,
    );
    // Top-right.
    canvas.drawPath(
      Path()
        ..moveTo(size.width - o - len, o)
        ..lineTo(size.width - o - radius, o)
        ..quadraticBezierTo(size.width - o, o, size.width - o, o + radius)
        ..lineTo(size.width - o, o + len),
      cornerPaint,
    );
    // Bottom-left.
    canvas.drawPath(
      Path()
        ..moveTo(o, size.height - o - len)
        ..lineTo(o, size.height - o - radius)
        ..quadraticBezierTo(o, size.height - o, o + radius, size.height - o)
        ..lineTo(o + len, size.height - o),
      cornerPaint,
    );
    // Bottom-right.
    canvas.drawPath(
      Path()
        ..moveTo(size.width - o - len, size.height - o)
        ..lineTo(size.width - o - radius, size.height - o)
        ..quadraticBezierTo(size.width - o, size.height - o, size.width - o,
            size.height - o - radius)
        ..lineTo(size.width - o, size.height - o - len),
      cornerPaint,
    );
  }

  @override
  bool shouldRepaint(_FramePainter old) =>
      old.progress != progress || old.detected != detected;
}
