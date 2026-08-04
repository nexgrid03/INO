import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../pressable_scale.dart';

/// A quiet, outlined "Continue with …" button for federated sign-in
/// (Google / Phone / Apple).
///
/// Deliberately understated - a theme-aware surface with a soft brand-tinted
/// border and the glyph seated in a small tinted well - so the gradient
/// primary CTA stays the clear focus. Pass [brand] as the leading glyph (see
/// [GoogleGlyph] / [AppleGlyph]).
class SocialAuthButton extends StatelessWidget {
  const SocialAuthButton({
    super.key,
    required this.label,
    required this.brand,
    required this.onPressed,
    this.busy = false,
  });

  final String label;
  final Widget brand;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return PressableScale(
      child: GestureDetector(
        onTap: busy ? null : onPressed,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: AppSizes.button,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: palette.isDark
                ? palette.surface
                : Colors.white.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(AppRadius.button),
            border: Border.all(
              color: palette.isDark
                  ? AppColors.primaryGreen.withValues(alpha: 0.30)
                  : AppColors.tealPale,
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: palette.shadow
                    .withValues(alpha: 0.04 * palette.shadowStrength),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: busy
              ? SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: palette.textSecondary,
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: AppColors.primaryGreen
                            .withValues(alpha: palette.isDark ? 0.16 : 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(child: brand),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Multicolour Google "G" mark (official brand colours, no asset).
class GoogleGlyph extends StatelessWidget {
  const GoogleGlyph({super.key, this.size = 20});

  final double size;

  static const blue = Color(0xFF4285F4);
  static const green = Color(0xFF34A853);
  static const yellow = Color(0xFFFBBC05);
  static const red = Color(0xFFEA4335);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: const CustomPaint(painter: _GoogleGPainter()),
    );
  }
}

class _GoogleGPainter extends CustomPainter {
  const _GoogleGPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final stroke = s * 0.22;
    final center = Offset(s / 2, s / 2);
    final radius = (s - stroke) / 2;
    final ring = Rect.fromCircle(center: center, radius: radius);

    Paint arcPaint(Color color) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt
      ..isAntiAlias = true;

    // Flutter arcs: 0 = right, increases clockwise.
    // Leave a mouth gap on the right so it reads as "G", not a closed "O".
    const gapStart = -0.38; // ~−22°
    const gapEnd = 0.72; // ~+41°

    // Blue: top → just above the mouth.
    canvas.drawArc(
      ring,
      -math.pi / 2,
      gapStart - (-math.pi / 2),
      false,
      arcPaint(GoogleGlyph.blue),
    );
    // Green: below the mouth → bottom.
    canvas.drawArc(
      ring,
      gapEnd,
      math.pi / 2 - gapEnd,
      false,
      arcPaint(GoogleGlyph.green),
    );
    // Yellow: bottom → left.
    canvas.drawArc(
      ring,
      math.pi / 2,
      math.pi / 2,
      false,
      arcPaint(GoogleGlyph.yellow),
    );
    // Red: left → top.
    canvas.drawArc(
      ring,
      math.pi,
      math.pi / 2,
      false,
      arcPaint(GoogleGlyph.red),
    );

    // Blue crossbar through the mouth (center → right rim).
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(
          center.dx - stroke * 0.08,
          center.dy - stroke / 2,
          center.dx + radius + stroke / 2,
          center.dy + stroke / 2,
        ),
        Radius.circular(stroke * 0.12),
      ),
      Paint()
        ..color = GoogleGlyph.blue
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Apple logo for Sign in with Apple.
class AppleGlyph extends StatelessWidget {
  const AppleGlyph({super.key, this.size = 22, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Icon(
      Icons.apple,
      size: size,
      color: color ?? (palette.isDark ? Colors.white : Colors.black),
    );
  }
}
