import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// Grows [child] as it scrolls up into view, then holds it at full size.
///
/// The effect is driven directly by the enclosing [Scrollable]'s position, so it
/// tracks the finger frame-for-frame instead of running a timed animation that
/// would lag behind (or fight) the scroll.
///
/// **The travel is one-way on purpose.** Progress ramps up as the child rises
/// toward [settleFraction] and then *stays* at full size however much further
/// you scroll ([holdPastSettle]) - it does not shrink again on the way out the
/// top. Scrolling back down reverses it normally. A symmetric curve would mean
/// the child started shrinking the moment it passed the middle of the screen,
/// which reads as the animation fighting you rather than settling.
///
/// **Why this is smooth, and what would make it jank:**
///
///  * **Layout never changes.** The child is laid out once at its natural size
///    and only ever scaled DOWN ([maxScale] is the layout size). Animating a
///    real width/height instead would re-layout the sliver list on every frame
///    and drag the whole page down with it.
///  * **Only the transform rebuilds.** The child is passed through
///    [AnimatedBuilder]'s `child` slot, so scrolling rebuilds a [Transform] and
///    nothing else - no image decode, no widget subtree work.
///  * **Painting is isolated.** A [RepaintBoundary] keeps the rescale from
///    repainting the rest of the feed.
///
/// Outside a [Scrollable] it renders at [maxScale] and does nothing, so it is
/// safe to drop anywhere.
class ScrollZoomIn extends StatefulWidget {
  const ScrollZoomIn({
    super.key,
    required this.child,
    this.minScale = 0.62,
    this.maxScale = 1.0,
    this.lift = 16,
    this.glowColor,
    this.borderRadius = 18,
    this.curve = Curves.easeOutCubic,
    this.settleFraction = 0.62,
    this.travelFraction = 0.42,
    this.holdPastSettle = true,
  });

  final Widget child;

  /// Scale when the child is furthest from its settle point. Layout is always
  /// reserved at [maxScale], so this only ever shrinks what is drawn.
  final double minScale;

  /// Scale at the settle point - the "fits properly" size.
  final double maxScale;

  /// How far (px) the child sits BELOW its resting place at [minScale]. It
  /// rises to zero as it grows, so the code lifts into place instead of merely
  /// inflating. Set 0 to disable.
  final double lift;

  /// Colour of the shadow that deepens as the child settles, selling it as
  /// coming forward off the page. Null disables the shadow entirely.
  final Color? glowColor;

  /// Corner radius the shadow is drawn against - should match the child's own.
  final double borderRadius;

  /// Shaping curve. Ease-out grows quickly as the child appears and eases as it
  /// settles, which reads as deliberate rather than linear and mechanical.
  final Curve curve;

  /// Where in the viewport the child is considered settled, as a fraction of
  /// viewport height (0 = top, 1 = bottom).
  ///
  /// Deliberately BELOW centre. A child that is the last thing in its feed
  /// never rises past roughly the middle of the screen - the scroll runs out
  /// first - so a settle point at 0.5 or above would leave it permanently a few
  /// pixels short of full size. Settling low means the zoom completes on its
  /// own, with no filler space added under the content to buy extra scroll.
  final double settleFraction;

  /// How far below the settle point (as a fraction of viewport height) the
  /// child is at [minScale]. Smaller = a punchier, faster ramp.
  final double travelFraction;

  /// Keep full size once the settle point has been passed, instead of shrinking
  /// again as the child continues up and out of view.
  final bool holdPastSettle;

  @override
  State<ScrollZoomIn> createState() => _ScrollZoomInState();
}

class _ScrollZoomInState extends State<ScrollZoomIn> {
  ScrollableState? _scrollable;

  /// Set once the first layout has happened, so the very first paint doesn't
  /// guess a scale from an unmeasured box.
  bool _measured = false;

  @override
  void initState() {
    super.initState();
    // After the first layout the render boxes exist and the real scale can be
    // computed; without this the child would paint once at a fallback size.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _measured = true);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scrollable = Scrollable.maybeOf(context);
  }

  /// 0 when the child is a full [ScrollZoomIn.travelFraction] below its settle
  /// point, 1 once it reaches (or passes) it.
  double _progress() {
    final scrollable = _scrollable;
    if (scrollable == null || !_measured) return 1;

    final box = context.findRenderObject() as RenderBox?;
    final viewport = scrollable.context.findRenderObject() as RenderBox?;
    if (box == null || viewport == null || !box.hasSize || !viewport.hasSize) {
      return 1;
    }

    final viewportHeight = viewport.size.height;
    if (viewportHeight <= 0) return 1;

    final double top;
    try {
      top = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
    } catch (_) {
      // The boxes can briefly share no ancestor during a route change.
      return 1;
    }

    final centre = top + box.size.height / 2;
    final settle = viewportHeight * widget.settleFraction;
    final travel = viewportHeight * widget.travelFraction;
    if (travel <= 0) return 1;

    // Positive = still below the settle line (not yet arrived).
    final below = centre - settle;
    if (below <= 0) {
      // At or past the settle line. Holding here is what makes extra scrolling
      // a no-op rather than a reversal.
      return widget.holdPastSettle
          ? 1
          : (1 + below / travel).clamp(0.0, 1.0);
    }
    return (1 - below / travel).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final scrollable = _scrollable;
    final child = RepaintBoundary(child: widget.child);

    if (scrollable == null) return child;

    final glow = widget.glowColor;

    return AnimatedBuilder(
      // The scroll position is a Listenable that ticks every frame of a scroll,
      // which is exactly the cadence this effect wants.
      animation: scrollable.position,
      // Passed through, never rebuilt - only the transform below is.
      child: child,
      builder: (context, child) {
        final t = widget.curve.transform(_progress());
        final scale =
            lerpDouble(widget.minScale, widget.maxScale, t) ?? widget.maxScale;

        Widget painted = child!;
        if (glow != null) {
          painted = DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              boxShadow: [
                BoxShadow(
                  color: glow.withValues(alpha: 0.30 * t),
                  blurRadius: 28 * t,
                  spreadRadius: 1.5 * t,
                  offset: Offset(0, 10 * t),
                ),
              ],
            ),
            child: painted,
          );
        }

        return Transform.translate(
          offset: Offset(0, widget.lift * (1 - t)),
          child: Transform.scale(
            scale: scale,
            filterQuality: FilterQuality.medium,
            child: painted,
          ),
        );
      },
    );
  }
}
