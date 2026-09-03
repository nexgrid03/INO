import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';

/// The single scroll feel for the whole app.
///
/// Installed once on the root `MaterialApp` (see `main.dart`), so **no screen
/// needs to pass `physics:` at all** — every list, grid, sliver and sheet in
/// INO inherits from here. Screens that used to hand-pick their own physics
/// were the reason scrolling changed character from page to page (a springy
/// list on one screen, a hard stop on the next, a re-scaling stretch on a
/// third); one behaviour removes that entirely.
///
/// Three deliberate choices:
///
///  1. **Bouncing physics on every platform**, not just iOS. Flutter's Android
///     default ([ClampingScrollPhysics]) stops dead at the edges and uses a
///     heavier friction model; the iOS spring simulation carries a fling
///     further and settles more gently, which is what reads as "smooth". This
///     is the same choice the Zenup app makes, where it is applied by hand at
///     ~90 call sites — done here once instead.
///
///  2. **No overscroll indicator.** Material 3's
///     [StretchingOverscrollIndicator] scale-transforms the entire viewport
///     when you pull past the end, which makes text and chrome look like they
///     shrink mid-scroll, and costs a full-viewport transform while it runs.
///     With bouncing physics the edges already have their own overscroll
///     feedback (the spring), so the indicator is redundant as well as
///     expensive. The older glow indicator is dropped for the same reason.
///
///  3. **[AlwaysScrollableScrollPhysics] as the parent**, so a short page
///     still drags — which is what `RefreshIndicator` needs to fire on a list
///     that does not fill its viewport. Screens no longer have to remember to
///     wrap their physics for pull-to-refresh to work.
class InoScrollBehavior extends MaterialScrollBehavior {
  const InoScrollBehavior();

  /// Trackpads, mice and styluses drag scrollables too, not just fingers.
  /// Without this a desktop/web build (and an Android tablet with a mouse)
  /// can only scroll with the wheel.
  @override
  Set<PointerDeviceKind> get dragDevices => const {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
        PointerDeviceKind.unknown,
      };

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    // No stretch, no glow — overscroll must never rescale or tint the viewport.
    return child;
  }

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) => inoScrollPhysics;
}

/// The app's scroll physics, as a constant.
///
/// Only needed where a scrollable cannot inherit from [InoScrollBehavior] —
/// for example when composing it as the `parent` of another physics. Everywhere
/// else, simply omit `physics:` and let the behaviour supply this.
const ScrollPhysics inoScrollPhysics = BouncingScrollPhysics(
  parent: AlwaysScrollableScrollPhysics(),
);
