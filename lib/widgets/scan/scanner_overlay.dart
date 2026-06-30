import 'package:flutter/material.dart';

import '../../screens/scan/scan_theme.dart';

/// The three detection states the overlay can reflect (per the scanner brief).
enum ScanOverlayState {
  /// No document framed yet — neutral border, "Position document".
  idle,

  /// A document is framed — green border, "Document Detected".
  detected,

  /// Locked on and sharp — green + blue glow, "Ready to Scan".
  ready,
}

/// The animated document-detection frame painted over the live camera feed.
///
/// Corner brackets, a state-driven border (neutral → green → green+blue glow)
/// and a scan line that sweeps while searching and eases out once ready — the
/// trustworthy language of Adobe Scan / Microsoft Lens. Purely decorative: it
/// sits above the preview and never intercepts touches.
class ScannerOverlay extends StatefulWidget {
  const ScannerOverlay({super.key, required this.state});

  final ScanOverlayState state;

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
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          return CustomPaint(
            painter: _FramePainter(progress: _c.value, state: widget.state),
            child: const SizedBox.expand(),
          );
        },
      ),
    );
  }
}

class _FramePainter extends CustomPainter {
  _FramePainter({required this.progress, required this.state});

  final double progress;
  final ScanOverlayState state;

  bool get _locked => state == ScanOverlayState.ready;
  bool get _active => state != ScanOverlayState.idle;

  @override
  void paint(Canvas canvas, Size size) {
    const radius = 20.0;
    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(radius),
    );

    // Border colour by state: neutral → green → green/blue.
    final Color borderColor = switch (state) {
      ScanOverlayState.idle => Colors.white.withValues(alpha: 0.35),
      ScanOverlayState.detected => ScanColors.green,
      ScanOverlayState.ready => ScanColors.green,
    };
    final borderPaint = Paint()
      ..color = borderColor.withValues(alpha: _active ? 0.95 : 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = _active ? 2.6 : 1.6;
    canvas.drawRRect(rect, borderPaint);

    // Ready state adds a soft blue inner glow.
    if (_locked) {
      final glow = Paint()
        ..color = ScanColors.blue.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawRRect(rect.deflate(2), glow);
    }

    // Sweeping scan line while still searching.
    if (!_locked) {
      final y = size.height * Curves.easeInOut.transform(progress);
      final lineColor = _active ? ScanColors.green : Colors.white;
      final shader = LinearGradient(
        colors: [
          lineColor.withValues(alpha: 0.0),
          lineColor.withValues(alpha: 0.55),
          lineColor.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, y - 18, size.width, 36));
      canvas.drawRect(
          Rect.fromLTWH(0, y - 18, size.width, 36), Paint()..shader = shader);
      canvas.drawLine(
        Offset(8, y),
        Offset(size.width - 8, y),
        Paint()
          ..color = lineColor.withValues(alpha: 0.85)
          ..strokeWidth = 2,
      );
    }

    // Corner brackets (always the accent green).
    const len = 30.0;
    final cornerPaint = Paint()
      ..color = _active ? ScanColors.green : Colors.white.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.4
      ..strokeCap = StrokeCap.round;
    const o = 3.0;
    void corner(Path p) => canvas.drawPath(p, cornerPaint);
    corner(Path()
      ..moveTo(o, o + len)
      ..lineTo(o, o + radius)
      ..quadraticBezierTo(o, o, o + radius, o)
      ..lineTo(o + len, o));
    corner(Path()
      ..moveTo(size.width - o - len, o)
      ..lineTo(size.width - o - radius, o)
      ..quadraticBezierTo(size.width - o, o, size.width - o, o + radius)
      ..lineTo(size.width - o, o + len));
    corner(Path()
      ..moveTo(o, size.height - o - len)
      ..lineTo(o, size.height - o - radius)
      ..quadraticBezierTo(o, size.height - o, o + radius, size.height - o)
      ..lineTo(o + len, size.height - o));
    corner(Path()
      ..moveTo(size.width - o - len, size.height - o)
      ..lineTo(size.width - o - radius, size.height - o)
      ..quadraticBezierTo(size.width - o, size.height - o, size.width - o,
          size.height - o - radius)
      ..lineTo(size.width - o, size.height - o - len));
  }

  @override
  bool shouldRepaint(_FramePainter old) =>
      old.progress != progress || old.state != state;
}
