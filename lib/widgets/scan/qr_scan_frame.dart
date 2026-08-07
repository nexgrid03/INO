import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// White rounded QR frame with a soft animated scan line sweeping top → bottom.
///
/// Purely presentational — no camera. Drop a real [MobileScanner] behind it later.
class QrScanFrame extends StatefulWidget {
  const QrScanFrame({
    super.key,
    this.size = 220,
    this.active = true,
    this.accent,
  });

  final double size;
  final bool active;
  final Color? accent;

  @override
  State<QrScanFrame> createState() => _QrScanFrameState();
}

class _QrScanFrameState extends State<QrScanFrame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _line;

  @override
  void initState() {
    super.initState();
    _line = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    if (widget.active) _line.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant QrScanFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_line.isAnimating) {
      _line.repeat(reverse: true);
    } else if (!widget.active && _line.isAnimating) {
      _line.stop();
    }
  }

  @override
  void dispose() {
    _line.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent ?? AppColors.primaryGreen;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size.square(widget.size),
            painter: _FramePainter(color: Colors.white, accent: accent),
            isComplex: true,
            willChange: false,
          ),
          if (widget.active)
            AnimatedBuilder(
              animation: _line,
              builder: (context, _) {
                final y = 18 + (widget.size - 36) * _line.value;
                final dark = Theme.of(context).brightness == Brightness.dark;
                return Positioned(
                  top: y,
                  left: 22,
                  right: 22,
                  child: Container(
                    height: 2.5,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(99),
                      gradient: LinearGradient(
                        colors: [
                          accent.withValues(alpha: 0),
                          accent.withValues(alpha: dark ? 0.7 : 1),
                          accent.withValues(alpha: 0),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: accent.withValues(alpha: dark ? 0.28 : 0.55),
                          blurRadius: dark ? 5 : 8,
                          spreadRadius: dark ? 0 : 0.5,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _FramePainter extends CustomPainter {
  _FramePainter({required this.color, required this.accent});

  final Color color;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const corner = 28.0;
    const inset = 8.0;
    final r = RRect.fromRectAndRadius(
      Rect.fromLTWH(inset, inset, size.width - inset * 2, size.height - inset * 2),
      const Radius.circular(18),
    );

    // Soft outer glow rect
    final glow = Paint()
      ..color = accent.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(r, glow);

    Path cornerPath(Offset a, Offset b, Offset c) => Path()
      ..moveTo(a.dx, a.dy)
      ..lineTo(b.dx, b.dy)
      ..lineTo(c.dx, c.dy);

    final left = inset;
    final top = inset;
    final right = size.width - inset;
    final bottom = size.height - inset;

    // TL
    canvas.drawPath(
      cornerPath(
        Offset(left, top + corner),
        Offset(left, top),
        Offset(left + corner, top),
      ),
      stroke,
    );
    // TR
    canvas.drawPath(
      cornerPath(
        Offset(right - corner, top),
        Offset(right, top),
        Offset(right, top + corner),
      ),
      stroke,
    );
    // BL
    canvas.drawPath(
      cornerPath(
        Offset(left, bottom - corner),
        Offset(left, bottom),
        Offset(left + corner, bottom),
      ),
      stroke,
    );
    // BR
    canvas.drawPath(
      cornerPath(
        Offset(right - corner, bottom),
        Offset(right, bottom),
        Offset(right, bottom - corner),
      ),
      stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _FramePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.accent != accent;
}
