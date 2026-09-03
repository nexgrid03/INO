import 'package:flutter/material.dart';

import 'theme_style.dart';

/// Avatar / profile accent colours.
///
/// Classic / bold / soft keep a stable per-user swatch. Launcher and the Aqua
/// family use one fixed brand fill for every account so Home + Profile match.
class AvatarColor {
  AvatarColor._();

  /// Launcher profile avatar — shared for every user.
  static const Color launcherProfile = Color(0xFF0A75A6);

  /// Aqua / Aqua Light / Aqua Mist / Clay profile avatar — shared for every user.
  static const Color aquaProfile = Color(0xFF055E5E);

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

  /// Theme-aware profile accent: fixed brand on Launcher / Aqua family,
  /// otherwise the per-user [forKey] swatch.
  static Color forStyle(ThemeStyle style, String seed) {
    switch (style) {
      case ThemeStyle.launcher:
        return launcherProfile;
      case ThemeStyle.aqua:
      case ThemeStyle.aquaMist:
        return aquaProfile;
    }
  }

  /// Two-stop gradient for avatar rings / initials fills (per-user).
  static LinearGradient gradientFor(String seed) {
    return _gradientFrom(forKey(seed));
  }

  /// Theme-aware avatar gradient (Home header + Profile hero).
  static LinearGradient gradientForStyle(ThemeStyle style, String seed) {
    return _gradientFrom(forStyle(style, seed));
  }

  static LinearGradient _gradientFrom(Color c) {
    final deep = Color.lerp(c, const Color(0xFF0F172A), 0.22)!;
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [c, deep],
    );
  }
}
