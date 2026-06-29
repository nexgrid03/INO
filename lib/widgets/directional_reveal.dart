import 'package:flutter/material.dart';

/// Progressively reveals [child] along one axis, like a wipe.
///
/// Driven by [progress] (0 = hidden, 1 = fully visible). A soft transparent
/// edge follows the wipe so the reveal looks like the artwork is being
/// "drawn" rather than hard-cut. Used for:
///   • the wealth chart — horizontal wipe = the line drawing left→right
///   • the QR code — vertical wipe = blocks appearing top→bottom
///
/// It does NOT change the child's appearance once fully revealed, so the
/// resting design is preserved exactly.
class DirectionalReveal extends StatelessWidget {
  const DirectionalReveal({
    super.key,
    required this.progress,
    required this.child,
    this.axis = Axis.horizontal,
  });

  final Animation<double> progress;
  final Axis axis;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bool horizontal = axis == Axis.horizontal;
    return AnimatedBuilder(
      animation: progress,
      builder: (context, revealChild) {
        final double p = progress.value.clamp(0.0, 1.0);
        // Width of the soft fading edge that trails the wipe.
        const double soft = 0.12;
        final double edge = (p + soft).clamp(0.0, 1.0);

        return ShaderMask(
          blendMode: BlendMode.dstIn, // keep child where the mask is opaque
          shaderCallback: (rect) {
            return LinearGradient(
              begin: horizontal ? Alignment.centerLeft : Alignment.topCenter,
              end: horizontal ? Alignment.centerRight : Alignment.bottomCenter,
              colors: const [
                Colors.white, // revealed
                Colors.white,
                Colors.transparent, // soft edge → hidden
                Colors.transparent,
              ],
              stops: [0.0, p, edge, 1.0],
            ).createShader(rect);
          },
          child: revealChild,
        );
      },
      child: child,
    );
  }
}
