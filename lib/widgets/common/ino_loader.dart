import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// The INO brand loader — the shield mark spinning inside a sweeping brand arc.
///
/// This is the app's ONE loading affordance. Anywhere the user waits on work
/// that takes more than a blink (uploading a document, running OCR, saving a
/// record, exporting a PDF) shows this instead of a bare
/// [CircularProgressIndicator], so a wait always reads as "INO is working"
/// rather than as generic Material chrome.
///
/// Three pieces, all driven by a **single** [AnimationController] and wrapped
/// in a [RepaintBoundary], so the whole thing costs one small isolated layer
/// per frame no matter where it is mounted:
///
///  1. **The sweeping arc** — a brand-gradient tail orbiting the mark. This is
///     what makes it legible as a spinner at a glance.
///  2. **The shield, spinning** — a real 3D flip about the Y axis (a coin
///     spin), not a flat rotation: a flat spin would put the INO wordmark
///     upside-down for half of every turn. When the back face comes round the
///     content is re-mirrored, so the wordmark always reads forwards.
///  3. **An optional label** underneath, for waits long enough to need words.
///
/// Sizes: [InoLoader.small] for inline / in-button use (mark only, no
/// wordmark — it would be unreadable), the default 64 for section and page
/// placeholders, and anything larger for a full-screen block.
class InoLoader extends StatefulWidget {
  const InoLoader({
    super.key,
    this.size = 64,
    this.label,
    this.showRing = true,
    this.color,
  });

  /// Compact variant for buttons, list rows and toolbars.
  const InoLoader.small({super.key, this.color})
      : size = 24,
        label = null,
        showRing = true;

  /// Diameter of the whole loader (ring included).
  final double size;

  /// Optional caption under the mark, e.g. "Uploading…".
  final String? label;

  /// Draw the orbiting arc. Off leaves just the spinning shield.
  final bool showRing;

  /// Overrides the brand accent (e.g. white, on a coloured surface).
  final Color? color;

  @override
  State<InoLoader> createState() => _InoLoaderState();
}

class _InoLoaderState extends State<InoLoader>
    with SingleTickerProviderStateMixin {
  /// One turn of the shield. The arc runs at twice this rate (see [build]) so
  /// the two motions never lock into a single readable beat.
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
    final accent = widget.color ?? AppColors.primaryGreen;
    final size = widget.size;
    // The mark sits inside the ring with a clear gap, so the arc never crops
    // the shield's shoulders as it passes.
    final markSize = size * (widget.showRing ? 0.66 : 0.94);
    // The wordmark is 0.235 of the mark, so this is the point below which it
    // would render under ~8px — a smudge. The silhouette alone reads better
    // there, and it is still unmistakably the app icon.
    final showWordmark = markSize >= 34;

    final loader = RepaintBoundary(
      child: SizedBox(
        width: size,
        height: size,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = _c.value;
            final flip = t * 2 * math.pi;
            // Seeing the reverse of the shield — mirror the content back so
            // the wordmark is never written backwards.
            final showingBack = math.cos(flip) < 0;

            return Stack(
              alignment: Alignment.center,
              children: [
                if (widget.showRing)
                  CustomPaint(
                    size: Size.square(size),
                    painter: _SweepArcPainter(
                      turn: t * 2,
                      color: accent,
                      stroke: math.max(2.0, size * 0.055),
                    ),
                  ),
                Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    // A touch of perspective so the flip has depth instead of
                    // reading as a horizontal squash.
                    ..setEntry(3, 2, 0.0012)
                    ..rotateY(flip),
                  child: Transform(
                    alignment: Alignment.center,
                    transform: showingBack
                        ? (Matrix4.identity()..rotateY(math.pi))
                        : Matrix4.identity(),
                    child: _ShieldMark(
                      size: markSize,
                      accent: accent,
                      showWordmark: showWordmark,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );

    final label = widget.label;
    if (label == null) return loader;

    final palette = AppPalette.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        loader,
        SizedBox(height: size * 0.24),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: palette.textSecondary,
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            height: 1.35,
          ),
        ),
      ],
    );
  }
}

/// A centred [InoLoader] with breathing room — the standard body for a screen,
/// sheet or section that is still fetching.
///
/// Use this in a `FutureBuilder`/`StreamBuilder` waiting branch instead of a
/// bare `Center(child: CircularProgressIndicator())`.
class InoLoadingView extends StatelessWidget {
  const InoLoadingView({
    super.key,
    this.message,
    this.size = 64,
    this.padding = const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
  });

  final String? message;
  final double size;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: padding,
        child: InoLoader(size: size, label: message),
      ),
    );
  }
}

/// The shield silhouette filled with the brand gradient, with the INO wordmark
/// carved out of it.
///
/// Reuses the splash's flat silhouette asset as an alpha mask (see
/// `_ClayShield3d` in `splash_screen.dart`): the PNG is flattened to white with
/// `BlendMode.srcIn`, then a [ShaderMask] paints the gradient through it. That
/// keeps the mark identical to the launcher icon at every size, and the decode
/// is capped because it is only ever painted a few dozen pixels wide.
class _ShieldMark extends StatelessWidget {
  const _ShieldMark({
    required this.size,
    required this.accent,
    required this.showWordmark,
  });

  final double size;
  final Color accent;
  final bool showWordmark;

  static const String _asset = 'assets/splash/splash_shield_blank.png';

  @override
  Widget build(BuildContext context) {
    // Lighter at the top-left, deeper at the bottom-right — the same light
    // direction the rest of the app's brand surfaces use.
    final hsl = HSLColor.fromColor(accent);
    final light =
        hsl.withLightness((hsl.lightness + 0.14).clamp(0.05, 0.92)).toColor();
    final deep =
        hsl.withLightness((hsl.lightness - 0.10).clamp(0.05, 0.92)).toColor();

    // Decoded at the painted size (x3 for high-DPI panels) rather than at the
    // asset's native resolution — see core/perf/image_decode.dart.
    final decode = (size * 3).ceil();

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (bounds) => LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [light, accent, deep],
              stops: const [0.0, 0.55, 1.0],
            ).createShader(bounds),
            child: Image.asset(
              _asset,
              width: size,
              height: size,
              fit: BoxFit.contain,
              color: Colors.white,
              colorBlendMode: BlendMode.srcIn,
              cacheWidth: decode,
              cacheHeight: decode,
              filterQuality: FilterQuality.medium,
              // The mark must still appear if the asset ever goes missing —
              // a loader that renders as a blank gap reads as a frozen app.
              errorBuilder: (_, _, _) => Icon(
                Icons.shield_rounded,
                size: size,
                color: Colors.white,
              ),
            ),
          ),
          if (showWordmark)
            Transform.translate(
              // Optically centred: the shield's mass sits above its point.
              offset: Offset(0, -size * 0.045),
              child: Text(
                'INO',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: size * 0.235,
                  fontWeight: FontWeight.w800,
                  letterSpacing: size * 0.012,
                  height: 1.0,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The orbiting arc: a 260° tail that fades out behind the head, rotated by
/// [turn] full revolutions.
class _SweepArcPainter extends CustomPainter {
  const _SweepArcPainter({
    required this.turn,
    required this.color,
    required this.stroke,
  });

  /// Revolutions completed — only its fractional part matters.
  final double turn;
  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = (size.shortestSide - stroke) / 2;
    final start = turn * 2 * math.pi;
    const sweep = math.pi * 1.45;

    // Faint full-circle track, so the arc reads as travelling along something
    // rather than floating in space.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = color.withValues(alpha: 0.12),
    );

    // SweepGradient lays its stops out from angle 0, so the shader is rotated
    // with the arc to keep the bright end pinned to the head of the tail.
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: sweep,
        tileMode: TileMode.clamp,
        colors: [
          color.withValues(alpha: 0.0),
          color.withValues(alpha: 0.55),
          color,
        ],
        stops: const [0.0, 0.62, 1.0],
        transform: GradientRotation(start),
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      start,
      sweep,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_SweepArcPainter old) =>
      old.turn != turn || old.color != color || old.stroke != stroke;
}
