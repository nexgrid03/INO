import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A soft, radial glow halo intended to sit *behind* a logo.
///
/// It is driven by an external [animation] whose value (0.0 → 1.0) controls
/// both the halo's opacity and how far it expands — letting the parent shape
/// a single gentle "pulse". Rendering is isolated in its own
/// [AnimatedBuilder] so only this halo repaints each frame, keeping the rest
/// of the splash tree static (good for a smooth 60 FPS).
class SoftGlow extends StatelessWidget {
  const SoftGlow({
    super.key,
    required this.animation,
    required this.size,
  });

  /// Drives the glow: 0 = invisible, 1 = full bloom.
  final Animation<double> animation;

  /// Diameter of the glow at full bloom.
  final double size;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final t = animation.value;
        return Opacity(
          // Cap peak opacity so the glow stays subtle and premium.
          opacity: (t * 0.55).clamp(0.0, 0.55),
          child: Transform.scale(
            // Expand gently from 80% to 100% as it blooms.
            scale: 0.8 + (t * 0.2),
            child: Container(
              width: size,
              height: size,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.skyBlue,
                    AppColors.primaryGreen,
                    Color(0x00000000), // fully transparent edge
                  ],
                  stops: [0.0, 0.45, 1.0],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
