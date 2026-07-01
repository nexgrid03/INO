import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../screens/scan/scan_theme.dart';

/// The three detection states the overlay can reflect (per the scanner brief).
enum ScanOverlayState {
  /// No document framed yet — neutral border, sweeping scan line.
  idle,

  /// A document is framed — green border + soft pulsing glow.
  detected,

  /// Locked on and sharp — brighter green + stronger glow.
  ready,
}

/// The animated document-detection frame painted over the live camera feed.
///
/// Corner brackets, a state-driven border (neutral → green) and a scan line that
/// sweeps while searching then eases out once a document locks in. On detection
/// the border smoothly thickens/greens (a short "reveal" animation) and a soft
/// green glow pulses continuously — the trustworthy language of Adobe Scan /
/// Microsoft Lens. Purely decorative: it sits above the preview and never
/// intercepts touches.
class ScannerOverlay extends StatefulWidget {
  const ScannerOverlay({super.key, required this.state});

  final ScanOverlayState state;

  @override
  State<ScannerOverlay> createState() => _ScannerOverlayState();
}

class _ScannerOverlayState extends State<ScannerOverlay>
    with TickerProviderStateMixin {
  // Continuous phase: drives the searching scan line and the detected pulse.
  late final AnimationController _phase = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat();

  // Short one-shot that eases the border/glow in as detection succeeds and out
  // when the document is lost — so nothing ever snaps.
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
    value: widget.state == ScanOverlayState.idle ? 0 : 1,
  );

  @override
  void didUpdateWidget(covariant ScannerOverlay old) {
    super.didUpdateWidget(old);
    if (widget.state != old.state) {
      if (widget.state == ScanOverlayState.idle) {
        _reveal.reverse();
      } else {
        _reveal.forward();
      }
    }
  }

  @override
  void dispose() {
    _phase.dispose();
    _reveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: Listenable.merge([_phase, _reveal]),
        builder: (context, _) {
          return CustomPaint(
            painter: _FramePainter(
              progress: _phase.value,
              reveal: _reveal.value,
              state: widget.state,
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
    required this.reveal,
    required this.state,
  });

  /// Continuous 0→1 phase (scan-line sweep + pulse).
  final double progress;

  /// 0 = idle (neutral) … 1 = fully detected (green + glow). Eased.
  final double reveal;

  final ScanOverlayState state;

  bool get _ready => state == ScanOverlayState.ready;

  @override
  void paint(Canvas canvas, Size size) {
    const radius = 20.0;
    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(radius),
    );

    // A soft sine pulse (0..1) used to breathe the glow while locked on.
    final pulse = 0.5 + 0.5 * math.sin(progress * 2 * math.pi);

    // ---- Pulsing glow (grows with `reveal`, breathes with `pulse`) ---------
    if (reveal > 0.01) {
      final glowStrength = _ready ? 0.55 : 0.38;
      final glow = Paint()
        ..color = ScanColors.green
            .withValues(alpha: reveal * glowStrength * (0.45 + 0.55 * pulse))
        ..style = PaintingStyle.stroke
        ..strokeWidth = _ready ? 9 : 6
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, _ready ? 12 : 8);
      canvas.drawRRect(rect.deflate(2), glow);
    }

    // ---- Border (neutral white → green, smoothly thickening) ---------------
    final borderColor = Color.lerp(
      Colors.white.withValues(alpha: 0.42),
      ScanColors.green,
      reveal,
    )!;
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6 + 1.2 * reveal;
    canvas.drawRRect(rect, borderPaint);

    // ---- Sweeping scan line (fades out as detection locks in) --------------
    final lineAlpha = 1 - reveal;
    if (lineAlpha > 0.02) {
      final y = size.height * Curves.easeInOut.transform(progress);
      final lineColor = Color.lerp(Colors.white, ScanColors.green, reveal)!;
      final shader = LinearGradient(
        colors: [
          lineColor.withValues(alpha: 0.0),
          lineColor.withValues(alpha: 0.55 * lineAlpha),
          lineColor.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, y - 18, size.width, 36));
      canvas.drawRect(
          Rect.fromLTWH(0, y - 18, size.width, 36), Paint()..shader = shader);
      canvas.drawLine(
        Offset(8, y),
        Offset(size.width - 8, y),
        Paint()
          ..color = lineColor.withValues(alpha: 0.85 * lineAlpha)
          ..strokeWidth = 2,
      );
    }

    // ---- Corner brackets (white → green) -----------------------------------
    const len = 30.0;
    final cornerPaint = Paint()
      ..color = Color.lerp(
        Colors.white.withValues(alpha: 0.85),
        ScanColors.green,
        reveal,
      )!
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
      old.progress != progress ||
      old.reveal != reveal ||
      old.state != state;
}
