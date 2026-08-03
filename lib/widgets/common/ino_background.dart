import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// The signature INO decorative backdrop - a soft teal aurora.
///
/// Layers (bottom → top):
///   1. A vertical mist gradient (teal-white wash → white → faint foam) so no
///      screen ever sits on plain flat white.
///   2. Two or three large organic blobs in the light tint ladder
///      (#38BDF8 / #7DD3FC / #BAE6FD at very low alpha) that drift slowly.
///   3. An optional whisper-subtle dot grid near the top for texture.
///
/// Wrap any screen body with it:
/// ```dart
/// Scaffold(body: InoBackground(child: content))
/// ```
/// The decoration is pointer-transparent and repaint-isolated, so it costs
/// nothing in hit-testing and only the backdrop layer repaints while drifting.
class InoBackground extends StatefulWidget {
  const InoBackground({
    super.key,
    required this.child,
    this.animate = true,
    this.showDots = true,
    this.intensity = 1.0,
    this.sky = true,
  });

  final Widget child;

  /// Slow ambient drift of the blobs (a ~14s breathing loop).
  final bool animate;

  /// Paint the dotted texture band near the top.
  final bool showDots;

  /// Scales blob opacity (use <1.0 behind dense content).
  final double intensity;

  /// Hero-sky variant (light mode): a saturated brand-blue band at the top
  /// that melts into white by mid-screen - the app-wide backdrop (pass false
  /// for the softer legacy wash). Ignored in dark mode.
  final bool sky;

  @override
  State<InoBackground> createState() => _InoBackgroundState();
}

class _InoBackgroundState extends State<InoBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _drift.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant InoBackground old) {
    super.didUpdateWidget(old);
    if (widget.animate && !_drift.isAnimating) {
      _drift.repeat(reverse: true);
    } else if (!widget.animate && _drift.isAnimating) {
      _drift.stop();
    }
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _drift,
              builder: (context, _) => CustomPaint(
                painter: _AuroraPainter(
                  t: Curves.easeInOut.transform(_drift.value),
                  palette: palette,
                  brand: AppColors.primaryGreen,
                  showDots: widget.showDots,
                  intensity: widget.intensity,
                  sky: widget.sky,
                ),
              ),
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter({
    required this.t,
    required this.palette,
    required this.brand,
    required this.showDots,
    required this.intensity,
    required this.sky,
  });

  final double t;
  final AppPalette palette;
  final Color brand;
  final bool showDots;
  final double intensity;
  final bool sky;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final dark = palette.isDark;
    final aqua = brand == AppColors.aquaPrimary;

    // 1. Base mist wash - never plain white. The hero-sky variant leads with
    // a saturated brand band that melts into the standard wash by mid-screen.
    final wash = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: dark
            ? [palette.bg, palette.bgElevated, palette.bg]
            : sky
                ? (aqua
                    ? const [
                        Color(0xFF7AE8D9),
                        Color(0xFFB5F0E6),
                        Color(0xFFE0F9F5),
                        Color(0xFFE8F8F5),
                      ]
                    : const [
                        Color(0xFF7DD3FC), // brand skyBlue - full tint at the top
                        Color(0xFFB2E2FC), // deep melt holds through the hero
                        Color(0xFFE3F3FD), // pale wash past mid-screen
                        Color(0xFFEAF4FC),
                      ])
                : (aqua
                    ? const [
                        Color(0xFFD4F7F2),
                        Color(0xFFFDFFFF),
                        Color(0xFFE8F8F5),
                      ]
                    : const [
                        Color(0xFFD8EDFA), // faint teal sky at the top
                        Color(0xFFFDFFFF),
                        Color(0xFFEAF4FC),
                      ]),
        stops: sky && !dark
            ? const [0.0, 0.28, 0.62, 1.0]
            : const [0.0, 0.45, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, wash);

    // 2. Drifting organic blobs - whisper alphas; much quieter in dark so
    // theme toggles never leave a teal cast over the whole shell (nav blur
    // would otherwise amplify it via extendBody).
    final drift = 18.0 * (t - 0.5); // −9 → +9 px of slow travel
    final blobScale = dark ? 0.12 : 1.0;
    void blob(Offset c, double r, Color color, double alpha) {
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: alpha * intensity * blobScale),
            color.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: c, radius: r));
      canvas.drawCircle(c, r, paint);
    }

    blob(
      Offset(size.width * 1.02, size.height * 0.02 + drift),
      size.width * 0.55,
      aqua ? AppColors.aquaSky : AppColors.skyBlue,
      0.22,
    );
    blob(
      Offset(size.width * -0.12, size.height * 0.30 - drift),
      size.width * 0.45,
      aqua ? AppColors.aquaPale : AppColors.tealPale,
      0.26,
    );
    blob(
      Offset(size.width * 0.85, size.height * 0.88 + drift * 0.6),
      size.width * 0.50,
      aqua ? AppColors.aquaSecondary : AppColors.secondaryGreen,
      0.14,
    );

    // 3. Dot texture band - a quiet geometric accent near the top.
    if (showDots && !dark) {
      final dot = Paint()
        ..color = brand.withValues(alpha: 0.05 * intensity);
      const gap = 26.0;
      final rows = math.min(7, (size.height / gap).floor());
      for (var row = 0; row < rows; row++) {
        // Fade the band out row by row.
        dot.color = brand.withValues(
          alpha: (0.055 - row * 0.007) * intensity,
        );
        for (var x = gap / 2; x < size.width; x += gap) {
          canvas.drawCircle(
            Offset(x + (row.isOdd ? gap / 2 : 0), 14 + row * gap),
            1.4,
            dot,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_AuroraPainter old) =>
      old.t != t ||
      old.palette != palette ||
      old.brand != brand ||
      old.showDots != showDots ||
      old.intensity != intensity ||
      old.sky != sky;
}

/// A standalone soft gradient circle for ad-hoc decoration inside cards,
/// headers and empty states. Position it with [Positioned] inside a [Stack].
class DecorBlob extends StatelessWidget {
   DecorBlob({
    super.key,
    required this.size,
    this.color = AppColors.skyBrandSky,
    this.opacity = 0.18,
  });

  final double size;
  final Color color;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: opacity),
              color.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}
