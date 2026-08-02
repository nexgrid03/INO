import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// The app's iOS 26 "Liquid Glass" material.
///
/// Renders a surface exactly the way Apple's Liquid Glass reads:
///
///  1. **Real refraction** - a [BackdropFilter] blurs whatever scrolls behind
///     the surface (the sky gradient, cards, content), so the material feels
///     like actual glass rather than painted translucency.
///  2. **Frost fill** - a soft white-to-clear gradient (light mode) or a
///     barely-there white film (dark mode) keeps content on top legible.
///  3. **Hairline edge** - a 1px bright rim that catches the light.
///  4. **Specular sheen** - a diagonal top-left highlight, the signature
///     Liquid Glass "wet" glint.
///
/// Drop-in for any card / pill / circle chrome:
///
/// ```dart
/// LiquidGlass(
///   borderRadius: BorderRadius.circular(24),
///   padding: const EdgeInsets.all(16),
///   child: ...,
/// )
/// ```
class LiquidGlass extends StatelessWidget {
  const LiquidGlass({
    super.key,
    required this.child,
    this.borderRadius,
    this.circle = false,
    this.blur = 22,
    this.frost = 1.0,
    this.tint,
    this.padding,
    this.shadow = true,
    this.enableBlur = true,
    this.clipBehavior = Clip.antiAlias,
  });

  final Widget child;

  /// Corner treatment for rectangular glass. Ignored when [circle] is true.
  final BorderRadiusGeometry? borderRadius;

  /// True for circular chrome (icon buttons, badges).
  final bool circle;

  /// Backdrop blur sigma. 18-26 reads like the iOS 26 tab bar.
  final double blur;

  /// Scales the frost-fill opacity: 1.0 = regular material,
  /// ~0.6 = "clear" Liquid Glass variant, >1 = milkier.
  final double frost;

  /// Optional colour breathed into the frost (Liquid Glass tinting).
  final Color? tint;

  final EdgeInsetsGeometry? padding;

  /// Soft ambient drop shadow lifting the glass off the page.
  final bool shadow;

  /// When false, skips [BackdropFilter] and paints an opaque frost fill —
  /// use for dense icon grids (performance on Android / web).
  final bool enableBlur;

  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final dark = palette.isDark;
    // Flutter web: BackdropFilter is extremely expensive and can leave Home
    // blank under load. Keep real blur for native; web uses frosted fill only.
    final useBlur = enableBlur && blur > 0 && !kIsWeb;

    final BorderRadius? radius = circle
        ? null
        : (borderRadius ?? BorderRadius.circular(24)).resolve(
            Directionality.of(context),
          );

    // Without real blur, slightly milk the frost — but keep light-mode tiles
    // translucent so the sky wash reads through (opaque white looked solid).
    final frostScale = useBlur ? frost : (dark ? frost * 1.35 : frost * 1.05);
    double a(double v) => (v * frostScale).clamp(0.0, 1.0);

    final base = tint ?? Colors.white;

    // Frost: brighter at the top-left where the sheen lives, thinning toward
    // the bottom-right so the backdrop colour bleeds through.
    final fill = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: dark
          ? [
              Colors.white.withValues(alpha: a(useBlur ? 0.14 : 0.20)),
              Colors.white.withValues(alpha: a(useBlur ? 0.06 : 0.12)),
            ]
          : [
              // Glassier light frost: translucent so sky wash shows through.
              base.withValues(alpha: a(useBlur ? 0.55 : 0.58)),
              base.withValues(alpha: a(useBlur ? 0.28 : 0.36)),
            ],
    );

    final rim = Border.all(
      color: dark
          ? Colors.white.withValues(alpha: 0.16)
          : Colors.white.withValues(alpha: useBlur ? 0.85 : 0.70),
      width: 1,
    );

    // The specular glint: a soft diagonal light pooling in the top-left.
    final sheen = IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: const Alignment(0.3, 1),
            colors: [
              Colors.white.withValues(alpha: dark ? 0.10 : 0.38),
              Colors.white.withValues(alpha: 0),
            ],
            stops: const [0, 0.45],
          ),
        ),
      ),
    );

    Widget body = DecoratedBox(
      decoration: BoxDecoration(
        gradient: fill,
        border: rim,
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: radius,
      ),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          Positioned.fill(child: sheen),
          if (padding != null) Padding(padding: padding!, child: child) else child,
        ],
      ),
    );

    Widget surface = useBlur
        ? BackdropFilter(
            filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
            child: body,
          )
        : body;

    surface = circle
        ? ClipOval(clipBehavior: clipBehavior, child: surface)
        : ClipRRect(
            clipBehavior: clipBehavior,
            borderRadius: radius!,
            child: surface,
          );

    if (!shadow) return surface;

    return DecoratedBox(
      decoration: BoxDecoration(
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.42 : 0.10),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.28 : 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: surface,
    );
  }
}
