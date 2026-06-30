import 'package:flutter/material.dart';

/// Central color palette and theme for the INO app.
///
/// Premium Green + Light Blue fintech system (Apple Wallet / Revolut / Google
/// Wallet feel). Two layers:
///   • [AppColors] — brand constants (greens/blues) + premium gradients. Theme-
///     agnostic; used by splash/login/onboarding and every gradient surface.
///   • [AppPalette] — semantic, brightness-aware tokens (background, surface,
///     text, border, ambient glow …) resolved via [AppPalette.of]. The whole
///     dashboard draws from these, so re-theming is a one-file change.
class AppColors {
  AppColors._();

  // Primary brand greens.
  static const Color primaryGreen = Color(0xFF00A86B); // emerald
  static const Color secondaryGreen = Color(0xFF34D399); // mint emerald
  static const Color darkGreen = Color(0xFF00875A);

  // Light blue accents.
  static const Color lightBlue = Color(0xFF38BDF8); // sky 400
  static const Color skyBlue = Color(0xFF7DD3FC); // sky 300

  // Semantic status colours (priority indicators, P/L, etc.).
  static const Color critical = Color(0xFFEF5350); // 🔴 critical
  static const Color warning = Color(0xFFF5A524); // 🟠 important
  static const Color positive = Color(0xFF00A86B); // 🟢 informational / gains
  static const Color negative = Color(0xFFEF5350); // losses
  static const Color gold = Color(0xFFE0A100);
  static const Color silver = Color(0xFF8C9BA5);

  // Original light neutrals (kept for splash / login / onboarding).
  static const Color background = Color(0xFFEEF6F6);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color textDark = Color(0xFF0C2421);
  static const Color textMuted = Color(0xFF547471);

  // --- Premium gradient system ---------------------------------------------

  /// Hero gradient — buttons, FAB, avatars, splash. #00A86B → #38BDF8.
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryGreen, lightBlue],
  );

  /// Wallet gradient — #34D399 → #7DD3FC.
  static const LinearGradient walletGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [secondaryGreen, skyBlue],
  );

  /// Insight gradient — #00A86B → #7DD3FC.
  static const LinearGradient insightGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryGreen, skyBlue],
  );
}

/// Brightness-aware semantic colour tokens for the dashboard.
///
/// Resolve the right set with [AppPalette.of(context)] — it reads the ambient
/// [Theme]'s brightness. Build dashboard surfaces against these tokens (never
/// hard-coded colours) so the whole experience flips between light and dark.
class AppPalette {
  const AppPalette({
    required this.brightness,
    required this.bg,
    required this.bgElevated,
    required this.surface,
    required this.cardTop,
    required this.cardBottom,
    required this.surfaceVariant,
    required this.textPrimary,
    required this.textSecondary,
    required this.textFaint,
    required this.border,
    required this.shadow,
    required this.ambient,
    required this.shadowStrength,
  });

  final Brightness brightness;

  /// Scaffold background.
  final Color bg;

  /// Slightly raised background (floating nav, header backdrop).
  final Color bgElevated;

  /// Nominal card surface (used by colorScheme).
  final Color surface;

  /// Glassmorphism card gradient stops (top-lit → base).
  final Color cardTop;
  final Color cardBottom;

  /// Inset chips, progress tracks, secondary fills.
  final Color surfaceVariant;

  final Color textPrimary;
  final Color textSecondary;
  final Color textFaint;

  /// Hairline borders / glass edges.
  final Color border;

  /// Neutral drop-shadow colour.
  final Color shadow;

  /// Green-blue ambient glow colour (the premium card halo).
  final Color ambient;

  /// Opacity multiplier for the neutral drop shadow.
  final double shadowStrength;

  bool get isDark => brightness == Brightness.dark;

  // Light is the PRIMARY theme — bright, clean, spacious, slate-based neutrals.
  static const AppPalette light = AppPalette(
    brightness: Brightness.light,
    bg: Color(0xFFF8FAFC), // slate-50
    bgElevated: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    cardTop: Color(0xFFFFFFFF), // pure white cards
    cardBottom: Color(0xFFFFFFFF),
    surfaceVariant: Color(0xFFF1F5F9), // slate-100
    textPrimary: Color(0xFF0F172A), // slate-900
    textSecondary: Color(0xFF64748B), // slate-500
    textFaint: Color(0xFF94A3B8), // slate-400
    border: Color(0xFFE2E8F0), // slate-200
    shadow: Color(0xFF000000),
    ambient: Color(0xFF00A86B),
    shadowStrength: 1.0,
  );

  static const AppPalette dark = AppPalette(
    brightness: Brightness.dark,
    bg: Color(0xFF07141A),
    bgElevated: Color(0xFF0D1F24),
    surface: Color(0xFF11262C),
    cardTop: Color(0xFF16333A),
    cardBottom: Color(0xFF11262C),
    surfaceVariant: Color(0xFF16333A),
    textPrimary: Color(0xFFECF7F4),
    textSecondary: Color(0xFFA6C6C3),
    textFaint: Color(0xFF6F918E),
    border: Color(0x1F7DD3FC), // rgba(125,211,252,0.12)
    shadow: Color(0xFF000000),
    ambient: Color(0xFF7DD3FC),
    shadowStrength: 0.5,
  );

  static AppPalette of(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark ? dark : light;
  }

  /// Subtle top-lit glass gradient used as the default card fill.
  LinearGradient get cardGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [cardTop, cardBottom],
      );

  /// The premium card elevation. Light mode uses the clean spec shadow
  /// (`0 8 30 rgba(0,0,0,0.08)`); dark mode pairs a deeper drop shadow with a
  /// very light green-blue ambient glow so cards lift off the near-black bg.
  List<BoxShadow> get cardShadow => isDark
      ? [
          BoxShadow(
            color: shadow.withValues(alpha: 0.5 * shadowStrength),
            blurRadius: 26,
            offset: const Offset(0, 14),
          ),
          BoxShadow(
            color: ambient.withValues(alpha: 0.07),
            blurRadius: 22,
            spreadRadius: -3,
            offset: const Offset(0, 6),
          ),
        ]
      : [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 30,
            offset: const Offset(0, 8),
          ),
        ];
}

class AppTheme {
  AppTheme._();

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;

    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primaryGreen,
      primary: AppColors.primaryGreen,
      secondary: AppColors.lightBlue,
      surface: palette.surface,
      brightness: brightness,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: palette.bg,
      canvasColor: palette.bg,
      appBarTheme: AppBarTheme(
        backgroundColor: palette.bg,
        foregroundColor: palette.textPrimary,
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
