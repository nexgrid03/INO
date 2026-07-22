import 'package:flutter/material.dart';

/// Central color palette and theme for the INO app.
///
/// Premium Teal + Cyan fintech system (CRED / Groww / INDmoney / Apple Wallet
/// feel). Three layers:
///   • [AppColors] — brand constants (teal/cyan + status colours). Theme-
///     agnostic; used by splash/login/onboarding and every gradient surface.
///     NOTE: legacy member names (primaryGreen, lightBlue, …) are kept so the
///     whole app re-skins from this one file — their VALUES are the new system.
///   • [AppGradients] / [AppShadows] / [AppBorders] — the named design-system
///     primitives every new surface should reach for.
///   • [AppPalette] — semantic, brightness-aware tokens (background, surface,
///     text, border, ambient glow …) resolved via [AppPalette.of]. The whole
///     dashboard draws from these, so re-theming is a one-file change.
class AppColors {
  AppColors._();

  // --- Brand -----------------------------------------------------------------

  /// Primary Teal — the brand anchor. (Legacy name kept; value is #0CB7A3.)
  static const Color primaryGreen = Color(0xFF0CB7A3);

  /// Soft mint-teal accent for secondary fills and positive surfaces.
  static const Color secondaryGreen = Color(0xFF2DD4BF);

  /// Darker teal for text/icons sitting on tinted fills.
  static const Color darkGreen = Color(0xFF0A9186);

  /// Secondary Cyan — the gradient partner. (Legacy name; value is #3EC7FF.)
  static const Color lightBlue = Color(0xFF3EC7FF);

  /// Lighter cyan for washes and dark-mode accents.
  static const Color skyBlue = Color(0xFF7DD9FF);

  // --- Semantic status colours ----------------------------------------------

  static const Color success = Color(0xFF22C55E);
  static const Color critical = Color(0xFFEF4444); // error
  static const Color warning = Color(0xFFF59E0B);
  static const Color positive = Color(0xFF22C55E); // gains / informational
  static const Color negative = Color(0xFFEF4444); // losses
  static const Color gold = Color(0xFFE0A100);
  static const Color silver = Color(0xFF8C9BA5);

  // --- Light neutrals (splash / login / onboarding) --------------------------

  static const Color background = Color(0xFFF8FAFC);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color textDark = Color(0xFF0F172A);
  static const Color textMuted = Color(0xFF64748B);

  // --- Premium gradient system (legacy aliases → AppGradients) ---------------

  /// Hero gradient — buttons, FAB, avatars, splash. #0CB7A3 → #3EC7FF.
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryGreen, lightBlue],
  );

  /// Wallet gradient — mint teal → light cyan.
  static const LinearGradient walletGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [secondaryGreen, skyBlue],
  );

  /// Insight gradient — teal → light cyan.
  static const LinearGradient insightGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryGreen, skyBlue],
  );
}

/// The named gradient library. Prefer these over ad-hoc [LinearGradient]s so
/// every branded surface shifts together.
class AppGradients {
  AppGradients._();

  /// The primary brand gradient (#0CB7A3 → #3EC7FF) — primary buttons, the
  /// active nav pill, avatars, hero chips.
  static const LinearGradient primary = AppColors.brandGradient;

  /// Softer companion (mint → light cyan) — wallet tiles, secondary heroes.
  static const LinearGradient soft = AppColors.walletGradient;

  /// A barely-there wash for card headers / hero tints (use over white).
  static LinearGradient wash({double opacity = 0.08}) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          AppColors.primaryGreen.withValues(alpha: opacity),
          AppColors.lightBlue.withValues(alpha: opacity * 0.75),
        ],
      );

  /// Success gradient for positive stat chips.
  static const LinearGradient successGrad = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.success, AppColors.secondaryGreen],
  );
}

/// The named elevation system — soft, floating, premium. Never use harsh
/// ad-hoc shadows; pick one of these.
class AppShadows {
  AppShadows._();

  /// The standard floating-card shadow (blur 20, 8% black).
  static List<BoxShadow> get card => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.08),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ];

  /// Slightly stronger, for surfaces hovering above cards (nav, FAB, sheets).
  static List<BoxShadow> get floating => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.10),
          blurRadius: 24,
          offset: const Offset(0, 10),
        ),
      ];

  /// A coloured brand glow under gradient buttons / hero chips.
  static List<BoxShadow> glow(Color color, {double opacity = 0.30}) => [
        BoxShadow(
          color: color.withValues(alpha: opacity),
          blurRadius: 16,
          offset: const Offset(0, 8),
        ),
      ];
}

/// Hairline border helpers.
class AppBorders {
  AppBorders._();

  /// The standard 1px hairline against the ambient palette.
  static Border hairline(AppPalette palette) =>
      Border.all(color: palette.border, width: 1);

  /// A soft brand-tinted border for highlighted cards.
  static Border accent({double opacity = 0.35}) => Border.all(
      color: AppColors.primaryGreen.withValues(alpha: opacity), width: 1);
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

  /// Inset chips, progress tracks, secondary cards (#F7F9FB in light).
  final Color surfaceVariant;

  final Color textPrimary;
  final Color textSecondary;
  final Color textFaint;

  /// Hairline borders / glass edges.
  final Color border;

  /// Neutral drop-shadow colour.
  final Color shadow;

  /// Teal-cyan ambient glow colour (the premium card halo).
  final Color ambient;

  /// Opacity multiplier for the neutral drop shadow.
  final double shadowStrength;

  bool get isDark => brightness == Brightness.dark;

  // Light is the PRIMARY theme — bright, clean, spacious, slate-based neutrals.
  static const AppPalette light = AppPalette(
    brightness: Brightness.light,
    bg: Color(0xFFF8FAFC), // spec background
    bgElevated: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF), // card background
    cardTop: Color(0xFFFFFFFF), // pure white cards
    cardBottom: Color(0xFFFFFFFF),
    surfaceVariant: Color(0xFFF7F9FB), // spec secondary card
    textPrimary: Color(0xFF0F172A), // spec primary text
    textSecondary: Color(0xFF64748B), // spec secondary text
    textFaint: Color(0xFF94A3B8), // slate-400
    border: Color(0xFFE5E7EB), // spec border
    shadow: Color(0xFF000000),
    ambient: Color(0xFF0CB7A3),
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
    border: Color(0x1F3EC7FF), // rgba(cyan, 0.12)
    shadow: Color(0xFF000000),
    ambient: Color(0xFF3EC7FF),
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
  /// (`0 8 20 rgba(0,0,0,0.08)` — soft, floating); dark mode pairs a deeper
  /// drop shadow with a very light teal-cyan ambient glow so cards lift off
  /// the near-black bg.
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
      : AppShadows.card;
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
            borderRadius: BorderRadius.circular(18),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primaryGreen,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
    );
  }
}
