import 'package:flutter/material.dart';

/// Stable per-user accent colors so avatars / profile cards stay distinct
/// across accounts (same key → same color every launch).
class AvatarColor {
  AvatarColor._();

  static const List<Color> _swatches = [
    Color(0xFF0D9488), // teal
    Color(0xFF4F46E5), // indigo
    Color(0xFFE11D48), // rose
    Color(0xFF7C3AED), // violet
    Color(0xFF0284C7), // sky
    Color(0xFFD97706), // amber
    Color(0xFFDB2777), // pink
    Color(0xFF059669), // emerald
    Color(0xFF2563EB), // blue
    Color(0xFFEA580C), // orange
    Color(0xFF0891B2), // cyan
    Color(0xFF9333EA), // purple
  ];

  /// Picks a swatch from [seed] (email, user id, or display name).
  static Color forKey(String seed) {
    final key = seed.trim().toLowerCase();
    if (key.isEmpty) return _swatches.first;
    var hash = 0;
    for (final c in key.codeUnits) {
      hash = 0x1fffffff & (hash * 31 + c);
    }
    return _swatches[hash.abs() % _swatches.length];
  }

  /// Two-stop gradient for avatar rings / initials fills.
  static LinearGradient gradientFor(String seed) {
    final c = forKey(seed);
    final deep = Color.lerp(c, const Color(0xFF0F172A), 0.28)!;
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [c, deep],
    );
  }
}
