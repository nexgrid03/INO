import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// Plays a one-shot slide-up the moment it mounts, after an optional [delay].
/// Wrapping each dashboard section in one of these (with a growing delay) gives
/// the screen a staggered "settle in" entrance - the same feel as the
/// login/onboarding screens - without a single central controller to
/// coordinate. It animates only once and then leaves the child untouched.
///
/// Opacity is never animated: fading from 0 left cards looking grey / washed
/// until the tween finished. Motion is slide-only so colours are correct on
/// the first painted frame.
///
/// On Flutter web, staggered tickers often never fire (especially with many
/// glass tiles), which left children stuck mid-animation. Web therefore skips
/// the animation and shows the child immediately.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 520),
    this.offset = 26,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final double offset;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: widget.duration);
    _slide = Tween<Offset>(
      begin: Offset(0, widget.offset / 100),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic));

    // Web: never risk a blank / mid-tween screen from a stalled ticker.
    if (kIsWeb) {
      _c.value = 1;
      return;
    }
    if (widget.delay == Duration.zero) {
      _c.forward();
    } else {
      Future<void>.delayed(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return widget.child;
    return SlideTransition(position: _slide, child: widget.child);
  }
}
