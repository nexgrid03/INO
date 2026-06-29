import 'package:flutter/material.dart';

/// Central color palette and theme for the INO app.
///
/// The brand identity is built around a professional green + light blue
/// combination: green signals security & trust, light blue keeps it fresh
/// and modern.
class AppColors {
  AppColors._();

  // Primary brand greens.
  static const Color primaryGreen = Color(0xFF1B9C85);
  static const Color darkGreen = Color(0xFF0E6E5C);

  // Light blue accents.
  static const Color lightBlue = Color(0xFF4FC3F7);
  static const Color skyBlue = Color(0xFF81D4FA);

  // Neutral surfaces.
  static const Color background = Color(0xFFF5F9F8);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color textDark = Color(0xFF1A2B29);
  static const Color textMuted = Color(0xFF6B7C7A);

  /// Brand gradient used on the splash and other hero surfaces.
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryGreen, lightBlue],
  );
}

class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primaryGreen,
      primary: AppColors.primaryGreen,
      secondary: AppColors.lightBlue,
      surface: AppColors.surface,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.background,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.primaryGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryGreen,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
    );
  }
}
