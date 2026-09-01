import 'dart:async' show Timer;
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/theme_style.dart';

/// Shared blur filters — creating a new [ImageFilter.blur] per build forces
/// the engine to recompile the blur shader. Bucketing keeps visuals identical
/// while cutting GPU churn across dozens of glass tiles.
final Map<int, ImageFilter> _kBlurFilters = <int, ImageFilter>{};

ImageFilter _blurFilterFor(double sigma) => sharedBlurFilter(sigma);

/// A cached [ImageFilter.blur] for [sigma], snapped to 0.5px buckets.
///
/// Reach for this instead of constructing `ImageFilter.blur` inline — most
/// importantly inside an [AnimatedBuilder], where a fresh filter per frame
/// makes the engine rebuild the blur shader on every single frame of the
/// animation. Bucketing means an animated sigma reuses ~30 cached filters
/// across its whole sweep rather than allocating 60 new ones per second.
ImageFilter sharedBlurFilter(double sigma) {
  // Cap at 16: values 18–24 look nearly identical on phone screens but cost
  // disproportionately more fill-rate (backdrop blur is O(sigma²) work).
  final s = sigma.clamp(0.0, 16.0);
  final key = (s * 2).round(); // 0.5px buckets
  return _kBlurFilters.putIfAbsent(
    key,
    () => ImageFilter.blur(sigmaX: key / 2.0, sigmaY: key / 2.0),
  );
}

/// Whether backdrop blur is allowed right now (false while a parent scroll
/// view is actively scrolling). Resting UI keeps full glass; mid-scroll uses
/// frost-only so frame time stays production-smooth.
class GlassScrollPerformance extends InheritedWidget {
  const GlassScrollPerformance({
    super.key,
    required this.allowBlur,
    required super.child,
  });

  final bool allowBlur;

  static bool blurAllowedOf(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<GlassScrollPerformance>();
    return scope?.allowBlur ?? true;
  }

  @override
  bool updateShouldNotify(GlassScrollPerformance oldWidget) =>
      allowBlur != oldWidget.allowBlur;
}

/// Wraps a scrollable so dense [LiquidGlass] surfaces drop backdrop blur only
/// while the user is scrolling. Appearance at rest is unchanged.
class GlassScrollListener extends StatefulWidget {
  const GlassScrollListener({super.key, required this.child});

  final Widget child;

  @override
  State<GlassScrollListener> createState() => _GlassScrollListenerState();
}

class _GlassScrollListenerState extends State<GlassScrollListener> {
  bool _allowBlur = true;

  /// Re-enables blur shortly after the scroll ends.
  Timer? _settle;

  /// Toggling [_allowBlur] swaps every visible glass surface between its
  /// BackdropFilter and frost-only renderings — a layer-tree change plus a
  /// dependents rebuild. The old implementation restarted a 140ms timer on
  /// every ScrollUpdate, so a finger resting mid-drag (no updates for 140ms)
  /// flipped blur back ON under the gesture, and the next movement flipped it
  /// OFF again — a visible hitch in the middle of scrolling. Bracketing on
  /// Start/End instead means blur drops exactly once per gesture and returns
  /// exactly once, only after the scroll (fling included) has fully ended —
  /// a drag flowing into its fling is a single Start…End bracket.
  void _onScrollStart() {
    _settle?.cancel();
    if (_allowBlur) setState(() => _allowBlur = false);
  }

  void _onScrollEnd() {

    _settle?.cancel();
    // A beat of quiet before restoring blur, so back-to-back flicks don't\


    // thrash the layer tree between them.
    _settle = Timer(const Duration(milliseconds: 250), () {
      if (!mounted || _allowBlur) return;
      setState(() => _allowBlur = true);
    });
  }

  @override
  void dispose() {
    _settle?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        // Depth 0 keeps this to the scrollable the user is actually dragging,
        // so a nested horizontal chip strip doesn't also suspend blur for the
        // whole page behind it.
        if (n.depth != 0) return false;
        if (n is ScrollStartNotification) {
          _onScrollStart();
        } else if (n is ScrollEndNotification) {
          _onScrollEnd();
        }
        return false;
      },
      child: GlassScrollPerformance(allowBlur: _allowBlur, child: widget.child),
    );
  }
}

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

    // Aqua Mist only: translucent frost + white rim vanish into #DFF3F3.
    // Circles become a porcelain disc with a teal jewelry rim and soft lift.
    if (!dark && circle && InoStyle.isAquaMist(context)) {
      return _mistCircleChrome(context);
    }

    // Dark: never sample the backdrop — translucent glass + sky wash made
    // icon tiles shift colour while scrolling. Light keeps real blur on
    // native; web always uses frosted fill only. Mid-scroll parents may
    // temporarily suspend blur via [GlassScrollPerformance] (frost-only).
    // blurAllowedOf is consulted LAST so surfaces that can never blur (dark
    // mode, web, enableBlur: false) register no dependency and aren't
    // rebuilt on every scroll start/settle.
    final useBlur =
        enableBlur &&
        blur > 0 &&
        !kIsWeb &&
        !dark &&
        GlassScrollPerformance.blurAllowedOf(context);

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
        colors: [Color.lerp(glassBase, Colors.white, lift)!, glassBase],
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
        ? RepaintBoundary(
            child: BackdropFilter(filter: _blurFilterFor(blur), child: body),
          )
        : body;

    surface = circle
        ? ClipOval(clipBehavior: clipBehavior, child: surface)
        : ClipRRect(
            clipBehavior: clipBehavior,
            borderRadius: radius!,
            child: surface,
          );

    if (!shadow) return RepaintBoundary(child: surface);

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

  /// Mist-only circular chrome: opaque porcelain + teal jewelry rim + soft
  /// brand bloom. Reads as a real control against the flat mist wash.
  Widget _mistCircleChrome(BuildContext context) {
    final brand = AppColors.aquaPrimary;
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFFFF), Color(0xFFF4FAF9)],
        ),
        border: Border.all(color: brand.withValues(alpha: 0.34), width: 1.35),
        boxShadow: [
          BoxShadow(
            color: brand.withValues(alpha: 0.18),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipOval(
        clipBehavior: clipBehavior,
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            // Quiet top sheen — keeps the disc feeling glass, not plastic.
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.55),
                      Colors.white.withValues(alpha: 0),
                    ],
                    stops: const [0, 0.55],
                  ),
                ),
              ),
            ),
            if (padding != null)
              Padding(padding: padding!, child: child)
            else
              child,
          ],
        ),
      ),
    );
  }
}
