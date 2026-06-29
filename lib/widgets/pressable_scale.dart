import 'package:flutter/material.dart';

/// Wraps a child so it scales down slightly while pressed, then springs back
/// on release — the tactile "squish" used by premium apps on their buttons.
///
/// Implemented with a [Listener] (not a GestureDetector) so it only *observes*
/// pointer events without consuming them: the inner button still receives the
/// tap and shows its own ink ripple.
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

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1.0,
        duration: widget.duration,
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
