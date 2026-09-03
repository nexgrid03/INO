import 'dart:async' show Timer;

import 'package:flutter/material.dart';

/// Wraps a child so it scales down slightly while pressed, then springs back
/// on release - the tactile "squish" used by premium apps on their buttons.
///
/// Implemented with a [Listener] (not a GestureDetector) so it only *observes*
/// pointer events without consuming them: the inner button still receives the
/// tap and shows its own ink ripple.
///
/// Because a [Listener] sits below the gesture arena it also sees the touches
/// that *start* a scroll. Two guards keep the squish out of scrolling:
///
///  * a short activation delay, so the fleeting touch of a fling never fires
///    the squish at all;
///  * a touch-slop check, so the moment the finger travels far enough to be a
///    drag the squish releases instead of staying compressed for the whole
///    scroll.
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.pressedScale = 0.96,
    this.duration = const Duration(milliseconds: 120),
  });

  final Widget child;

  /// Scale applied while the pointer is down.
  final double pressedScale;

  /// How quickly it eases between pressed and released.
  final Duration duration;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;
  Timer? _activation;
  Offset? _downPosition;

  /// A real press reads as instant at 70ms, but a scroll touch has usually
  /// started moving by then.
  static const Duration _activationDelay =
      Duration(milliseconds: 70);

  /// Movement beyond this is a drag, not a press (matches kTouchSlop).
  static const double _slop = 18.0;

  void _onDown(PointerDownEvent event) {
    _downPosition = event.position;

    _activation?.cancel();

    _activation = Timer(_activationDelay, () {
      if (!mounted || _downPosition == null) return;

      setState(() => _pressed = true);
    });
  }

  void _onMove(PointerMoveEvent event) {
    final down = _downPosition;

    if (down == null) return;

    if ((event.position - down).distance > _slop) {
      _release();
    }
  }

  void _release() {
    _activation?.cancel();
    _activation = null;
    _downPosition = null;

    // Guard against setState() after dispose().
    if (!mounted || !_pressed) return;

    setState(() => _pressed = false);
  }

  @override
  void dispose() {
    _activation?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _onDown,
      onPointerMove: _onMove,
      onPointerUp: (_) => _release(),
      onPointerCancel: (_) => _release(),
      child: AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1.0,
        duration: widget.duration,
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}