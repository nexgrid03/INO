import 'package:flutter/material.dart';

/// Scanner-only design tokens.
///
/// The live camera scanner is a dark, full-bleed surface and uses a brighter,
/// more luminous green/blue than the rest of INO so the overlay and controls
/// pop against a real camera feed. These are intentionally scoped to the
/// scanner module — the global [AppColors] / app theme are left untouched.
class ScanColors {
  ScanColors._();

  static const Color green = Color(0xFF00E676); // luminous green
  static const Color blue = Color(0xFF29B6F6); // sky blue
  static const Color white = Color(0xFFFFFFFF);
  static const Color bg = Color(0xFF050B10); // near-black background
  static const Color surface = Color(0xFF0D1720); // glass surface

  /// Primary green → blue gradient used by the capture button & accents.
  static const LinearGradient gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [green, blue],
  );
}
