import 'package:flutter/material.dart';

/// Scanner-only design tokens.
///
/// The scanner uses light, professional chrome around a live camera viewport so
/// it matches INO's primary light theme. Accents are a confident emerald green
/// — the "document detected / ready to scan" language users trust from Adobe
/// Scan & Microsoft Lens — giving the scanner a positive, ready-to-go feel.
/// Scoped to the scanner module — the global [AppColors] / app theme are left
/// untouched.
class ScanColors {
  ScanColors._();

  /// Primary accent — emerald green.
  static const Color accent = Color(0xFF10B981); // emerald 500
  static const Color accentDeep = Color(0xFF059669); // emerald 600

  // Back-compat names kept so the overlay/controls stay readable at a glance.
  // Both now resolve to the emerald accent.
  static const Color green = accent;
  static const Color blue = accentDeep;
  static const Color white = Color(0xFFFFFFFF);

  /// Light chrome around the camera viewport (matches the app background).
  static const Color bg = Color(0xFFF8FAFC); // slate-50
  static const Color surface = Color(0xFFFFFFFF); // cards / glass surfaces
  static const Color surfaceVariant = Color(0xFFF1F5F9); // slate-100
  static const Color border = Color(0xFFE2E8F0); // slate-200

  /// Text on the light chrome.
  static const Color textPrimary = Color(0xFF0F172A); // slate-900
  static const Color textSecondary = Color(0xFF64748B); // slate-500

  /// Primary light-blue gradient used by the capture button & accents.
  static const LinearGradient gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accent, accentDeep],
  );
}
