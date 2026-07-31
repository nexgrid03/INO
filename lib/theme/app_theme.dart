// CupertinoPageTransitionsBuilder lives in the cupertino library (it's no
// longer re-exported by material.dart), so it needs its own import.
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'theme_style.dart';

/// Central color palette and theme for the INO app.
///
/// Premium Teal design system built around the brand anchor **#0EA5E9** and a
/// ladder of lighter tints only (never darker):
///   #0EA5E9 → #38BDF8 → #7DD3FC → #BAE6FD → #E0F2FE → white.
///
/// Three layers:
///   • [AppColors] - brand constants (teal tints + status colours). Theme-
///     agnostic; used by splash/login/onboarding and every gradient surface.
///     NOTE: legacy member names (primaryGreen, lightBlue, …) are kept so the
///     whole app re-skins from this one file - their VALUES are the new system.
///   • [AppGradients] / [AppShadows] / [AppBorders] - the named design-system
///     primitives every new surface should reach for.
///   • [AppPalette] - semantic, brightness-aware tokens (background, surface,
///     text, border, ambient glow …) resolved via [AppPalette.of]. The whole
///     dashboard draws from these, so re-theming is a one-file change.
class AppColors {
  AppColors._();

  // --- Brand: the #0EA5E9 tint ladder ---------------------------------------

  /// Primary brand teal - #0EA5E9. (Legacy name kept for app-wide reach.)
  static const Color primaryGreen = Color(0xFF0EA5E9);

  /// Tint 1 - #38BDF8. Secondary fills, gradient partner, soft accents.
  static const Color secondaryGreen = Color(0xFF38BDF8);

  /// Text/icons sitting on tinted fills. Per the brand rule the primary is
  /// never darkened, so this aliases the anchor itself.
  static const Color darkGreen = Color(0xFF0EA5E9);

  /// Tint 1 - #38BDF8. (Legacy "cyan partner" name; now the first tint.)
  static const Color lightBlue = Color(0xFF38BDF8);

  /// Tint 2 - #7DD3FC. Washes, glows and dark-mode accents.
  static const Color skyBlue = Color(0xFF7DD3FC);

  /// Tint 3 - #BAE6FD. Chip strokes, decorative shapes.
  static const Color tealPale = Color(0xFFBAE6FD);

  /// Tint 4 - #E0F2FE. Mist fills, progress tracks, chip backgrounds.
  static const Color tealMist = Color(0xFFE0F2FE);

  /// Near-white teal - #F0F9FF. Section washes and inset surfaces.
  static const Color tealFoam = Color(0xFFF0F9FF);

  // --- Semantic status colours ----------------------------------------------

  static const Color success = Color(0xFF22C55E);
  static const Color critical = Color(0xFFEF4444); // error
  static const Color warning = Color(0xFFF59E0B);
  static const Color positive = Color(0xFF22C55E); // gains / informational
  static const Color negative = Color(0xFFEF4444); // losses
  static const Color gold = Color(0xFFE0A100);
  static const Color silver = Color(0xFF8C9BA5);

  // --- Light neutrals (splash / login / onboarding) --------------------------

  static const Color background = Color(0xFFEAF4FC);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color textDark = Color(0xFF0F172A);
  static const Color textMuted = Color(0xFF64748B);

  // --- Premium gradient system (legacy aliases → AppGradients) ---------------

  /// Hero gradient - buttons, FAB, avatars, splash. #0EA5E9 → #38BDF8.
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryGreen, secondaryGreen],
  );

  /// Wallet gradient - tint 1 → tint 2.
  static const LinearGradient walletGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [secondaryGreen, skyBlue],
  );

  /// Insight gradient - anchor → tint 2 (a wider, airier sweep).
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

  /// The primary brand gradient (#0EA5E9 → #38BDF8) - primary buttons, the
  /// active nav pill, avatars, hero chips.
  static const LinearGradient primary = AppColors.brandGradient;

  /// Softer companion (#38BDF8 → #7DD3FC) - wallet tiles, secondary heroes.
  static const LinearGradient soft = AppColors.walletGradient;

  /// The widest in-family sweep (#0EA5E9 → #7DD3FC) - hero banners.
  static const LinearGradient hero = AppColors.insightGradient;

  /// Airy mist gradient (white → #E0F2FE) - screen washes, empty states.
  static const LinearGradient mist = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Colors.white, AppColors.tealMist],
  );

  /// A barely-there wash for card headers / hero tints (use over white).
  static LinearGradient wash({double opacity = 0.08}) => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      AppColors.primaryGreen.withValues(alpha: opacity),
      AppColors.skyBlue.withValues(alpha: opacity * 0.75),
    ],
  );

  /// Success gradient for positive stat chips.
  static const LinearGradient successGrad = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.success, Color(0xFF4ADE80)],
  );
}

/// The named elevation system - soft, floating, premium. Depth comes mostly
/// from spacing, layering and hairline borders; shadows stay whisper-light and
/// teal-tinted so nothing ever looks heavy. Never use harsh ad-hoc shadows.
class AppShadows {
  AppShadows._();

  /// The standard floating-card shadow - a soft teal-tinted halo.
  static List<BoxShadow> get card => [
    BoxShadow(
      color: AppColors.primaryGreen.withValues(alpha: 0.07),
      blurRadius: 22,
      offset: const Offset(0, 8),
    ),
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.03),
      blurRadius: 10,
      offset: const Offset(0, 3),
    ),
  ];

  /// Slightly stronger, for surfaces hovering above cards (nav, FAB, sheets).
  static List<BoxShadow> get floating => [
    BoxShadow(
      color: AppColors.primaryGreen.withValues(alpha: 0.12),
      blurRadius: 28,
      offset: const Offset(0, 12),
    ),
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.04),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];

  /// A coloured brand glow under gradient buttons / hero chips.
  static List<BoxShadow> glow(Color color, {double opacity = 0.30}) => [
    BoxShadow(
      color: color.withValues(alpha: opacity),
      blurRadius: 18,
      offset: const Offset(0, 8),
    ),
  ];
}

/// Hairline border helpers.
class AppBorders {
  AppBorders._();

  /// The spec card border: 1px solid rgba(48,172,179,0.15).
  static const Color line = Color(0x260EA5E9);

  /// The standard 1px hairline against the ambient palette.
  static Border hairline(AppPalette palette) =>
      Border.all(color: palette.border, width: 1);

  /// A soft brand-tinted border for highlighted cards.
  static Border accent({double opacity = 0.35}) => Border.all(
    color: AppColors.primaryGreen.withValues(alpha: opacity),
    width: 1,
  );
}

/// Brightness-aware semantic colour tokens for the dashboard.
///
/// Resolve the right set with [AppPalette.of(context)] - it reads the ambient
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

  /// Inset chips, progress tracks, secondary cards.
  final Color surfaceVariant;

  final Color textPrimary;
  final Color textSecondary;
  final Color textFaint;

  /// Hairline borders / glass edges - rgba(48,172,179,0.15) in light.
  final Color border;

  /// Neutral drop-shadow colour.
  final Color shadow;

  /// Teal ambient glow colour (the premium card halo).
  final Color ambient;

  /// Opacity multiplier for the neutral drop shadow.
  final double shadowStrength;

  bool get isDark => brightness == Brightness.dark;

  // Light is the PRIMARY theme - bright, airy, teal-washed, never plain white.
  static const AppPalette light = AppPalette(
    brightness: Brightness.light,
    bg: Color(0xFFEAF4FC), // soft teal-white wash
    bgElevated: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF), // card background
    cardTop: Color(0xFFFFFFFF), // top-lit glass card
    cardBottom: Color(0xFFFAFCFF), // whisper of mist at the base
    surfaceVariant: Color(0xFFF0F9FF), // teal foam inset
    textPrimary: Color(0xFF0F172A),
    textSecondary: Color(0xFF64748B),
    textFaint: Color(0xFF94A3B8), // slate-400
    border: Color(0x260EA5E9), // spec: rgba(48,172,179,0.15)
    shadow: Color(0xFF0EA5E9),
    ambient: Color(0xFF0EA5E9),
    shadowStrength: 1.0,
  );

  /// Bold-style light: the same layout of tokens with every neutral run a
  /// shade deeper - a stronger teal wash, firmer borders and heavier shadows -
  /// so the accent-flooded cards sit in a correspondingly deeper scene.
  static const AppPalette lightBold = AppPalette(
    brightness: Brightness.light,
    bg: Color(0xFFDCEEFA), // deeper teal wash
    bgElevated: Color(0xFFF9FDFD),
    surface: Color(0xFFFCFEFE),
    cardTop: Color(0xFFFCFEFE),
    cardBottom: Color(0xFFE8F3FC),
    surfaceVariant: Color(0xFFD8EBF8),
    textPrimary: Color(0xFF0B1220),
    textSecondary: Color(0xFF56636F),
    textFaint: Color(0xFF8593A2),
    border: Color(0x400EA5E9), // rgba(48,172,179,0.25) - firmer hairline
    shadow: Color(0xFF0EA5E9),
    ambient: Color(0xFF0EA5E9),
    shadowStrength: 1.2,
  );

  /// Soft-style light: a touch airier than classic - a near-white wash, lighter
  /// hairlines and whisper shadows - the backdrop for glass badges with
  /// colourful glyphs.
  static const AppPalette lightSoft = AppPalette(
    brightness: Brightness.light,
    bg: Color(0xFFF5FAFE), // lighter, near-white wash
    bgElevated: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    cardTop: Color(0xFFFFFFFF),
    cardBottom: Color(0xFFFCFEFE),
    surfaceVariant: Color(0xFFEAF4FC),
    textPrimary: Color(0xFF1E293B),
    textSecondary: Color(0xFF6E7F94),
    textFaint: Color(0xFFA0ACBC),
    border: Color(0x1F0EA5E9), // rgba(48,172,179,0.12) - lighter hairline
    shadow: Color(0xFF0EA5E9),
    ambient: Color(0xFF0EA5E9),
    shadowStrength: 0.8,
  );

  static const AppPalette dark = AppPalette(
    brightness: Brightness.dark,
    bg: Color(0xFF0A1926),
    bgElevated: Color(0xFF102331),
    surface: Color(0xFF13293A),
    cardTop: Color(0xFF173347),
    cardBottom: Color(0xFF13293A),
    surfaceVariant: Color(0xFF173347),
    textPrimary: Color(0xFFEDF5FB),
    textSecondary: Color(0xFFA8C2D6),
    textFaint: Color(0xFF6F8BA3),
    border: Color(0x247DD3FC), // rgba(tint2, 0.14)
    shadow: Color(0xFF000000),
    ambient: Color(0xFF7DD3FC),
    shadowStrength: 0.5,
  );

  static AppPalette of(BuildContext context) {
    // Depends on the InoStyleScope too, so every palette consumer rebuilds
    // (and re-tones) when the user picks a new style in Profile → App theme.
    return resolve(
      brightness: Theme.of(context).brightness,
      style: InoStyleScope.of(context),
    );
  }

  /// The palette for an explicit brightness + style pair (used by [AppTheme]
  /// when building ThemeData, where there's no scope to read yet).
  static AppPalette resolve({
    required Brightness brightness,
    required ThemeStyle style,
  }) {
    if (brightness == Brightness.dark) return dark;
    switch (style) {
      case ThemeStyle.bold:
        return lightBold;
      case ThemeStyle.soft:
        return lightSoft;
      case ThemeStyle.classic:
        return light;
    }
  }

  /// Subtle top-lit glass gradient used as the default card fill.
  LinearGradient get cardGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [cardTop, cardBottom],
  );

  /// The premium card elevation. Light mode pairs a whisper-light teal halo
  /// with a faint neutral key shadow (depth comes from the hairline border and
  /// layering, not weight); dark mode pairs a deeper drop shadow with a light
  /// teal ambient glow so cards lift off the near-black bg.
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

  /// Style-aware variants - the scaffold wash, borders and shadows shift with
  /// the picked [ThemeStyle] (classic / bold / soft).
  static ThemeData lightFor(ThemeStyle style) =>
      _build(Brightness.light, style: style);
  static ThemeData darkFor(ThemeStyle style) =>
      _build(Brightness.dark, style: style);

  static ThemeData _build(
    Brightness brightness, {
    ThemeStyle style = ThemeStyle.classic,
  }) {
    final isDark = brightness == Brightness.dark;
    final palette = AppPalette.resolve(brightness: brightness, style: style);
    final fontFamily = GoogleFonts.manrope().fontFamily;

    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primaryGreen,
      primary: AppColors.primaryGreen,
      secondary: AppColors.secondaryGreen,
      tertiary: AppColors.skyBlue,
      error: AppColors.critical,
      surface: palette.surface,
      brightness: brightness,
    );

    // Strong hierarchy: large expressive headings, comfortable body text.
    // Divine Glass spec: everything is set in Manrope.
    final textTheme = GoogleFonts.manropeTextTheme(
      Typography.material2021(platform: TargetPlatform.android).englishLike,
    )
        .apply(
          bodyColor: palette.textPrimary,
          displayColor: palette.textPrimary,
        )
        .copyWith(
          displaySmall: TextStyle(fontFamily: fontFamily, 
            fontSize: 34,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.0,
            color: palette.textPrimary,
          ),
          headlineMedium: TextStyle(fontFamily: fontFamily, 
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
            color: palette.textPrimary,
          ),
          headlineSmall: TextStyle(fontFamily: fontFamily, 
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            color: palette.textPrimary,
          ),
          titleLarge: TextStyle(fontFamily: fontFamily, 
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
            color: palette.textPrimary,
          ),
          titleMedium: TextStyle(fontFamily: fontFamily, 
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
            color: palette.textPrimary,
          ),
          bodyLarge: TextStyle(fontFamily: fontFamily, 
            fontSize: 16,
            fontWeight: FontWeight.w500,
            height: 1.45,
            color: palette.textPrimary,
          ),
          bodyMedium: TextStyle(fontFamily: fontFamily, 
            fontSize: 14,
            fontWeight: FontWeight.w500,
            height: 1.45,
            color: palette.textPrimary,
          ),
          bodySmall: TextStyle(fontFamily: fontFamily, 
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
            color: palette.textSecondary,
          ),
          labelLarge: TextStyle(fontFamily: fontFamily, 
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
            color: palette.textPrimary,
          ),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      fontFamily: fontFamily,
      textTheme: textTheme,
      scaffoldBackgroundColor: palette.bg,
      canvasColor: palette.bg,
      splashFactory: InkRipple.splashFactory,
      // Premium, smooth route transitions everywhere (~350–450ms feel).
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: palette.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(fontFamily: fontFamily, 
          fontSize: 17,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
          color: palette.textPrimary,
        ),
        iconTheme: IconThemeData(color: palette.textPrimary, size: 22),
      ),
      iconTheme: IconThemeData(color: palette.textSecondary, size: 22),
      // Cards: rounded 20, hairline teal border, whisper shadow.
      cardTheme: CardThemeData(
        color: palette.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: palette.border),
        ),
      ),
      // Primary buttons: filled brand teal, rounded, soft elevation.
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryGreen,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.tealMist,
          disabledForegroundColor: AppColors.textMuted,
          elevation: 0,
          shadowColor: AppColors.primaryGreen.withValues(alpha: 0.35),
          textStyle: TextStyle(fontFamily: fontFamily, 
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
          ),
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
          textStyle: TextStyle(fontFamily: fontFamily, 
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        ),
      ),
      // Secondary buttons: white fill, thin light-teal border, teal text.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: isDark ? Colors.transparent : Colors.white,
          foregroundColor: AppColors.primaryGreen,
          side: BorderSide(
            color: isDark ? palette.border : AppColors.tealPale,
            width: 1.2,
          ),
          textStyle: TextStyle(fontFamily: fontFamily, 
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primaryGreen,
          textStyle: TextStyle(fontFamily: fontFamily, fontSize: 14, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.primaryGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      // Inputs: soft filled fields, rounded 16, teal focus ring.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? palette.surfaceVariant : Colors.white,
        hintStyle: TextStyle(fontFamily: fontFamily, 
          color: palette.textFaint,
          fontSize: 14.5,
          fontWeight: FontWeight.w500,
        ),
        labelStyle: TextStyle(fontFamily: fontFamily, 
          color: palette.textSecondary,
          fontSize: 14.5,
          fontWeight: FontWeight.w500,
        ),
        prefixIconColor: AppColors.primaryGreen,
        suffixIconColor: palette.textFaint,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(
            color: AppColors.primaryGreen,
            width: 1.4,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.critical),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.critical, width: 1.4),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: palette.border),
        ),
      ),
      // Chips: mist fills with teal text and a pale stroke.
      chipTheme: ChipThemeData(
        backgroundColor: isDark ? palette.surfaceVariant : AppColors.tealFoam,
        selectedColor: AppColors.primaryGreen,
        disabledColor: palette.surfaceVariant,
        labelStyle: TextStyle(fontFamily: fontFamily, 
          color: palette.textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        secondaryLabelStyle: TextStyle(fontFamily: fontFamily, 
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        side: BorderSide(color: palette.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      // Dialogs: airy 28-radius sheets of light.
      dialogTheme: DialogThemeData(
        backgroundColor: palette.bgElevated,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(color: palette.border),
        ),
        titleTextStyle: TextStyle(fontFamily: fontFamily, 
          fontSize: 19,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
          color: palette.textPrimary,
        ),
        contentTextStyle: TextStyle(fontFamily: fontFamily, 
          fontSize: 14.5,
          fontWeight: FontWeight.w500,
          height: 1.5,
          color: palette.textSecondary,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.bgElevated,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: palette.bgElevated,
        showDragHandle: true,
        dragHandleColor: AppColors.tealPale,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.primaryGreen,
        contentTextStyle: TextStyle(fontFamily: fontFamily, 
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        actionTextColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.primaryGreen,
        unselectedLabelColor: palette.textFaint,
        labelStyle: TextStyle(fontFamily: fontFamily, fontSize: 14, fontWeight: FontWeight.w700),
        unselectedLabelStyle: TextStyle(fontFamily: fontFamily, 
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        indicatorColor: AppColors.primaryGreen,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        overlayColor: WidgetStatePropertyAll(
          AppColors.primaryGreen.withValues(alpha: 0.06),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: palette.border,
        thickness: 1,
        space: 1,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: AppColors.primaryGreen,
        textColor: palette.textPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: palette.bgElevated,
        surfaceTintColor: Colors.transparent,
        elevation: 4,
        shadowColor: AppColors.primaryGreen.withValues(alpha: 0.18),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: palette.border),
        ),
        textStyle: TextStyle(fontFamily: fontFamily, 
          color: palette.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.primaryGreen
              : (isDark ? palette.surfaceVariant : AppColors.tealMist),
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.primaryGreen
              : Colors.transparent,
        ),
        checkColor: const WidgetStatePropertyAll(Colors.white),
        side: const BorderSide(color: AppColors.tealPale, width: 1.6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.primaryGreen
              : AppColors.tealPale,
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: AppColors.primaryGreen,
        inactiveTrackColor: isDark
            ? palette.surfaceVariant
            : AppColors.tealMist,
        thumbColor: Colors.white,
        overlayColor: AppColors.primaryGreen.withValues(alpha: 0.10),
        trackHeight: 5,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: AppColors.primaryGreen,
        linearTrackColor: isDark ? palette.surfaceVariant : AppColors.tealMist,
        circularTrackColor: isDark
            ? palette.surfaceVariant
            : AppColors.tealMist,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.primaryGreen,
          borderRadius: BorderRadius.circular(12),
        ),
        textStyle: TextStyle(fontFamily: fontFamily, 
          color: Colors.white,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
