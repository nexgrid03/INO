import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'shiny_icon.dart';

/// The design system's vector-style illustration primitive: a soft outer halo
/// disc, a glossy [ShinyIcon] at its centre, and floating accent dots.
/// Gives empty states / heroes a premium illustrated feel without shipping
/// image assets - it's pure Flutter, so it scales crisply and follows the theme.
class IllustrationBadge extends StatelessWidget {
  const IllustrationBadge({
    super.key,
    required this.icon,
    this.size = 120,
    this.color,
  });

  final IconData icon;
  final double size;

  /// Overrides the brand teal as the illustration's tint.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? AppColors.primaryGreen;
    final partner = color == null ? AppColors.lightBlue : tint;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // Outer halo.
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  tint.withValues(alpha: 0.10),
                  partner.withValues(alpha: 0.08),
                ],
              ),
            ),
          ),
          // Inner disc - the glossy badge.
          ShinyIcon(
            icon: icon,
            color: tint,
            size: size * 0.72,
            iconSize: size * 0.34,

          ),
          // Floating accent dots - the "illustrated" sparkle.
          Positioned(
            top: size * 0.06,
            right: size * 0.14,
            child: _dot(partner, size * 0.09),
          ),
          Positioned(
            bottom: size * 0.10,
            left: size * 0.08,
            child: _dot(tint, size * 0.06),
          ),
          Positioned(
            top: size * 0.30,
            left: -size * 0.015,
            child: _dot(partner.withValues(alpha: 0.6), size * 0.045),
          ),
        ],
      ),
    );
  }

  Widget _dot(Color color, double d) => Container(
        width: d,
        height: d,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.35),
              blurRadius: 6,
            ),
          ],
        ),
      );
}
