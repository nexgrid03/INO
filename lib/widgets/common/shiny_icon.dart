import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/theme_style.dart';

/// How the badge body is filled.
enum ShinyIconStyle {
  /// A bright glass body carrying the accent glyph - the Divine Glass default
  /// for classic/soft themes.
  glass,

  /// A saturated accent body with a white glyph inside a thick accent ring -
  /// used by the bold theme (and any call site that opts in under classic).
  filled,
}

/// The app's icon badge: a glossy, brightly-lit body inside a crisp accent ring.
///
/// Entirely static - no ticker, no animation, and no outer glow or drop shadow.
/// The "lit" quality comes from the surface itself: a tinted gradient body, a
/// top-left gloss, a bright ring with a white-hot arc, and a hairline rim light.
/// Nothing is painted outside the badge, so a badge never bleeds onto whatever
/// sits next to it.
///
/// Layout is exactly [size]×[size] - the same box the plain `Container` badges
/// used - so dropping this in never shifts surrounding content. Pass [radius]
/// for a squircle badge, or leave it null for a circle.
class ShinyIcon extends StatelessWidget {
  const ShinyIcon({
    super.key,
    required IconData this.icon,
    required this.color,
    this.size = 44,
    this.iconSize,
    this.radius,
    this.style = ShinyIconStyle.glass,
  }) : child = null;

  /// Same badge, but wrapping an arbitrary glyph (an animated icon, an image,
  /// initials …) instead of an [IconData].
  const ShinyIcon.custom({
    super.key,
    required Widget this.child,
    required this.color,
    this.size = 44,
    this.radius,
    this.style = ShinyIconStyle.glass,
  }) : icon = null,
       iconSize = null;

  final IconData? icon;
  final Widget? child;

  /// The badge's accent - drives the ring, the body tint and (in glass) the
  /// glyph.
  final Color color;

  /// Diameter / side of the layout box.
  final double size;

  /// Glyph size. Defaults to 42% of [size].
  final double? iconSize;

  /// Corner radius; null gives a circle.
  final double? radius;

  final ShinyIconStyle style;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    // The picked app theme re-skins every badge from this one place:
    //  • classic / soft - Divine Glass pastel chip (glass body, coloured glyph),
    //    remapping any legacy `filled` call sites automatically,
    //  • bold - saturated accent body with a white glyph.
    final themeStyle = InoStyle.of(context);
    final effectiveStyle = themeStyle == ThemeStyle.bold
        ? ShinyIconStyle.filled
        : (style == ShinyIconStyle.filled ? ShinyIconStyle.glass : style);
    final effectiveColor = themeStyle == ThemeStyle.bold
        ? InoStyle.deepen(color, 0.12)
        : color;
    final filled = effectiveStyle == ShinyIconStyle.filled;

    final glyph =
        child ??
        Icon(
          icon,
          size: iconSize ?? size * 0.42,
          color: filled
              ? Colors.white
              // A touch deeper than the raw accent so the glyph reads firmly
              // against the glass - but only a touch; shading it hard made the
              // whole badge feel heavy.
              : shinyGlyphColor(effectiveColor, isDark: palette.isDark),
        );

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _ShinyBadgePainter(
          accent: effectiveColor,
          style: effectiveStyle,
          radius: radius,
          isDark: palette.isDark,
          surface: palette.surface,
          // The soft theme's signature: a pronounced glass shine riding on
          // every badge ring, matching the containers' ShinyBorder sheen.
          shine: themeStyle == ThemeStyle.soft,
        ),
        // `painter` draws behind `child`, so the glyph rides on top of the
        // glass - including on top of the gloss, which keeps it legible.
        child: Center(child: glyph),
      ),
    );
  }
}

/// Lifts a colour towards light - the dark-mode counterpart to [_shade], and
/// the source of the ring's light-catch arc.
Color _lift(Color c, double amount) {
  final hsl = HSLColor.fromColor(c);
  return hsl
      .withLightness((hsl.lightness + amount).clamp(0.0, 1.0))
      .withSaturation((hsl.saturation + amount * 0.5).clamp(0.0, 1.0))
      .toColor();
}

/// Deepens a colour, gaining a little saturation on the way down so it stays
/// vivid instead of turning muddy. Drives the glyph and the ring, which need to
/// sit firmly against the bright glass body.
Color _shade(Color c, double amount) {
  final hsl = HSLColor.fromColor(c);
  return hsl
      .withLightness((hsl.lightness - amount).clamp(0.0, 1.0))
      .withSaturation((hsl.saturation + amount * 0.55).clamp(0.0, 1.0))
      .toColor();
}

/// The glyph colour a glass [ShinyIcon] paints its icon in.
///
/// Exported so surfaces that show a *bare* accent icon - no badge around it -
/// can match the badges exactly instead of copying the constant. Keeping the one
/// definition means the two can't drift apart when it's next tuned.
Color shinyGlyphColor(Color accent, {required bool isDark}) =>
    isDark ? _lift(accent, 0.20) : _shade(accent, 0.06);

/// The accent border strength that reads as the same edge as a badge's ring,
/// for containers that want the treatment without the badge.
Color shinyBorderColor(Color accent, {double opacity = 0.45}) =>
    accent.withValues(alpha: opacity);

class _ShinyBadgePainter extends CustomPainter {
  _ShinyBadgePainter({
    required this.accent,
    required this.style,
    required this.radius,
    required this.isDark,
    required this.surface,
    this.shine = false,
  });

  final Color accent;
  final ShinyIconStyle style;
  final double? radius;
  final bool isDark;
  final Color surface;

  /// Paints the extra glass shine on the ring (the soft theme).
  final bool shine;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    if (s <= 0) return;

    final rect = Offset.zero & size;
    final body = RRect.fromRectAndRadius(
      rect,
      Radius.circular(radius ?? s / 2),
    );
    final filled = style == ShinyIconStyle.filled;
    final bright = _lift(accent, 0.18);

    // Every fade below ends on a zero-alpha copy of the *same* colour, never
    // `Colors.transparent` - that constant is transparent **black**, and a
    // gradient running white→transparent interpolates through grey, which
    // turns the glass a dull metallic instead of bright.

    // 1 - The body. Glass keeps a light accent tint; filled runs a lifted
    // accent gradient. Lit from the top-left in both cases.
    final List<Color> bodyColors;
    if (filled) {
      bodyColors = [_lift(accent, 0.16), accent];
    } else if (isDark) {
      // Lean harder on the accent here: over a near-black surface a timid tint
      // reads as grey once the gloss lands on top of it.
      bodyColors = [
        Color.alphaBlend(bright.withValues(alpha: 0.58), surface),
        Color.alphaBlend(bright.withValues(alpha: 0.26), surface),
      ];
    } else {
      // Enough tint that the ring and glyph sit on real colour rather than
      // looking pasted onto a white disc, but kept light - this gradient is the
      // biggest driver of how heavy the badge feels.
      bodyColors = [
        Color.alphaBlend(accent.withValues(alpha: 0.08), Colors.white),
        Color.alphaBlend(accent.withValues(alpha: 0.27), Colors.white),
      ];
    }
    canvas.drawRRect(
      body,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: bodyColors,
        ).createShader(rect),
    );

    // 2 - Top-left gloss, the highlight that makes the face read as glass.
    // Drawing the shape with a radial shader confines it to the body, no extra
    // clip needed. Dark mode takes far less of it: a strong white bloom over a
    // dark body just greys out the accent.
    canvas.drawRRect(
      body,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.55, -0.70),
          radius: 1.0,
          colors: [
            Colors.white.withValues(
              alpha: filled ? 0.46 : (isDark ? 0.30 : 0.85),
            ),
            Colors.white.withValues(alpha: 0),
          ],
          stops: const [0.0, 0.85],
        ).createShader(rect),
    );

    // 3 - The ring. A saturated border so the badge has a definite edge, with a
    // lighter catch parked at the top-left to match the gloss's light source.
    // The catch is a lifted accent rather than white - white read as a pale gap
    // in the border and undercut the whole edge.
    //
    // The shading here is gentle on purpose: the ring sits at full accent for
    // most of its run and only dips slightly on the shaded side. Pushing it
    // darker turned a crisp edge into a heavy outline.
    // Thick accent edge - the same weight the Home tiles carry on their card
    // borders, scaled with the badge so small and large read alike.
    final ringW = math.max(2.0, s * 0.07);
    canvas.drawRRect(
      body.deflate(ringW / 2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ringW
        ..shader = SweepGradient(
          transform: const GradientRotation(-math.pi),
          colors: [
            accent,
            _lift(accent, 0.16), // the light catch, top-left
            accent,
            _shade(accent, 0.09), // slightly deeper on the shaded far side
            _shade(accent, 0.05),
            accent,
          ],
          stops: const [0.0, 0.12, 0.30, 0.56, 0.80, 1.0],
        ).createShader(rect),
    );

    // 4b - The soft theme's glass shine, painted ON the ring: a white-hot
    // light-catch arc at the top-left and a softer echo bottom-right, the same
    // sheen the containers' [ShinyBorder] carries - so badges and container
    // borders read as one glassy system.
    if (shine) {
      canvas.drawRRect(
        body.deflate(ringW / 2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = ringW
          ..shader = SweepGradient(
            transform: const GradientRotation(-math.pi),
            colors: [
              Colors.white.withValues(alpha: 0),
              Colors.white.withValues(alpha: 0.92), // top-left light catch
              Colors.white.withValues(alpha: 0),
              Colors.white.withValues(alpha: 0.38), // bottom-right echo
              Colors.white.withValues(alpha: 0),
            ],
            stops: const [0.0, 0.12, 0.34, 0.62, 0.86],
          ).createShader(rect),
      );
    }

    // 4 - Inner rim light: the crisp glass edge, brightest at the top-left.
    // Kept modest so it reads as a highlight *inside* the border rather than
    // competing with it.
    final rimW = math.max(0.8, s * (shine ? 0.032 : 0.022));
    final rimInset = ringW + rimW / 2;
    if (s > rimInset * 2 + 2) {
      canvas.drawRRect(
        body.deflate(rimInset),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = rimW
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(
                alpha: shine ? 0.95 : (filled ? 0.66 : 0.82),
              ),
              Colors.white.withValues(alpha: 0),
            ],
            stops: const [0.0, 0.55],
          ).createShader(rect),
      );
    }
  }

  @override
  bool shouldRepaint(_ShinyBadgePainter old) =>
      old.accent != accent ||
      old.style != style ||
      old.radius != radius ||
      old.isDark != isDark ||
      old.surface != surface ||
      old.shine != shine;
}
