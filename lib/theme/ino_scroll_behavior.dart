import 'package:flutter/material.dart';

/// Scroll behavior for Launcher (Divine Glass).
///
/// Material 3's default [StretchingOverscrollIndicator] applies a scale
/// transform on overscroll, which makes text and chrome look like they shrink
/// while scrolling — especially noticeable on Profile and other long pages.
/// This behavior keeps clamping physics and drops the stretch indicator.
class InoNoStretchScrollBehavior extends MaterialScrollBehavior {
  const InoNoStretchScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    // No stretch / glow — overscroll should not rescale the viewport.
    return child;
  }

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const ClampingScrollPhysics();
  }
}
