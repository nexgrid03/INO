import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Reusable INO brand mark: an "INO" monogram inside a rounded shield on a
/// white badge.
///
/// This is a TEMPORARY placeholder. When the real logo is ready, replace the
/// inner [Stack] with `Image.asset('assets/logo.png')` — every screen that
/// uses [InoLogo] will pick up the new mark automatically.
///
/// Kept presentation-only (no animation) so it can be reused on the splash,
/// login header, app bars, etc. Animations are applied by the parent.
class InoLogo extends StatelessWidget {
  const InoLogo({super.key, this.size = 130});

  /// Width/height of the square badge.
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(size * 0.26),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: size * 0.22,
            offset: Offset(0, size * 0.09),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Gradient-filled shield via ShaderMask.
          ShaderMask(
            shaderCallback: (bounds) =>
                AppColors.brandGradient.createShader(bounds),
            child: Icon(
              Icons.shield_rounded,
              size: size * 0.74,
              color: Colors.white,
            ),
          ),
          Text(
            'INO',
            style: TextStyle(
              color: Colors.white,
              fontSize: size * 0.17,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
