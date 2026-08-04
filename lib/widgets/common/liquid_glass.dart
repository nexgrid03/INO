import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// The app's iOS 26 "Liquid Glass" material.
///
/// Renders a surface exactly the way Apple's Liquid Glass reads:
///
///  1. **Real refraction** - a [BackdropFilter] blurs whatever scrolls behind
///     the surface (light mode only). Dark mode uses an opaque frosted fill
///     so scroll gradients cannot recolour icon / card backgrounds.
///  2. **Frost fill** - translucent white wash in light; solid surface glass
///     in dark.
///  3. **Hairline edge** - a 1px bright rim that catches the light.
///  4. **Specular sheen** - light-mode only diagonal highlight (omitted in
///     dark — the wet glint reads as artificial over night surfaces).
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
  /// In dark mode the fill is opaque; frost only nudges the top lift.
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
    // Dark: never sample the backdrop — translucent glass + sky wash made
    // icon tiles shift colour while scrolling. Light keeps real blur on
    // native; web always uses frosted fill only.
    final useBlur = enableBlur && blur > 0 && !kIsWeb && !dark;

    final BorderRadius? radius = circle
        ? null
        : (borderRadius ?? BorderRadius.circular(24)).resolve(
            Directionality.of(context),
          );

    final frostScale = useBlur ? frost : (dark ? frost : frost * 1.05);
    double a(double v) => (v * frostScale).clamp(0.0, 1.0);

    // Dark glass sits on [surface] (or [tint]) — fully opaque so gradients
    // behind never bleed through. Light keeps the classic white frost.
    final glassBase = tint ?? (dark ? palette.surface : Colors.white);

    final LinearGradient fill;
    if (dark) {
      final lift = (0.05 * frost.clamp(0.6, 1.6)).clamp(0.03, 0.08);
      fill = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.lerp(glassBase, Colors.white, lift)!,
          glassBase,
        ],
      );
    } else {
      fill = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          glassBase.withValues(alpha: a(useBlur ? 0.55 : 0.58)),
          glassBase.withValues(alpha: a(useBlur ? 0.28 : 0.36)),
        ],
      );
    }

    final rim = Border.all(
      color: dark
          ? Colors.white.withValues(alpha: 0.10)
          : Colors.white.withValues(alpha: useBlur ? 0.85 : 0.70),
      width: 1,
    );

    // Specular glint — light mode only.
    final Widget? sheen = dark
        ? null
        : IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: const Alignment(0.3, 1),
                  colors: [
                    Colors.white.withValues(alpha: 0.38),
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
          if (sheen != null) Positioned.fill(child: sheen),
          if (padding != null)
            Padding(padding: padding!, child: child)
          else
            child,
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
        boxShadow: dark
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.28),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.10),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: surface,
    );
  }
}
