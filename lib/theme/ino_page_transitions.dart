import 'package:flutter/material.dart';

/// INO's push/pop transition — a slide with parallax, installed once on the
/// root [PageTransitionsTheme] so **every** `MaterialPageRoute` in the app
/// inherits it.
///
/// **Why not the Material default.** Android's stock
/// [ZoomPageTransitionsBuilder] scales and cross-fades two full-screen layers
/// at once. It reads as a "container transform" on the phones it was designed
/// on, and as a stutter on mid-range hardware — the incoming page's very first
/// frame (which is also the frame that builds the whole screen for the first
/// time, resolves its images and starts its network calls) is the frame that
/// has to composite two scaled, faded, full-screen layers. That is the frame
/// that drops, and it drops on the transition the user notices most.
///
/// A slide costs one translate per layer, no scale and no layer for the
/// incoming page at all, so the expensive first frame carries almost nothing
/// extra. It is also the motion the Zenup app uses, which is the reference for
/// how navigation is meant to feel here.
///
/// iOS keeps [CupertinoPageTransitionsBuilder]: it looks near-identical, but it
/// is the only builder that installs Flutter's interactive back-swipe detector,
/// and on iOS the edge swipe is the primary way people go back.
class InoSlidePageTransitionsBuilder extends PageTransitionsBuilder {
  const InoSlidePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T>? route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // Incoming page: slides in from the right, and on pop slides back out to
    // the right with a decelerated exit.
    final entry = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final slideIn = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: Offset.zero,
    ).animate(entry);

    // Outgoing page: parallax left plus a slight dim, so the two pages read as
    // a stack rather than as one sheet replacing another. A symmetric curve so
    // it glides back into place when the top page is popped.
    final exit = CurvedAnimation(
      parent: secondaryAnimation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final slideOut = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(-0.25, 0.0),
    ).animate(exit);
    final fadeOut = Tween<double>(begin: 1.0, end: 0.85).animate(exit);

    return SlideTransition(
      position: slideOut,
      child: FadeTransition(
        opacity: fadeOut,
        child: SlideTransition(position: slideIn, child: child),
      ),
    );
  }
}
