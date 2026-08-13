import 'package:flutter/material.dart';

/// The visual styles ("app themes") pickable from Profile → App theme.
/// Orthogonal to light/dark [ThemeMode] - each style works in both.
///
///  • [classic]  - the current UI: airy white/pastel cards carrying filled
///    accent icon badges with white glyphs.
///  • [bold]     - the accent floods the whole container: the colour that used
///    to live on the small inner icon badge shifts onto the outer card, the
///    glyph stays in place but goes plain white, and every colour runs deeper.
///    Small standalone badges (e.g. Quick Actions) keep their shape and simply
///    darken.
///  • [soft]     - a lighter take on classic: fills a touch airier and the icon
///    badges go glass with **colourful** glyphs instead of white.
///  • [launcher] - Compact Home layout (quick actions → vaults →
///    needs-attention) plus frosted glass chrome on feature screens.
///    Colour rules match classic (#0EA5E9). Home icons are tinted SVGs.
///  • [aqua]     - Same compact Home + Divine Glass chrome as [launcher],
///    branded with teal #098F90 (gradient sky wash). Home icons are tinted SVGs.
///  • [aquaLight] - Same teal brand + Divine Glass as [aqua], but a **flat**
///    solid backdrop (no aurora / sky gradient). Home icons are tinted SVGs.
///  • [aquaMist] - Full Aqua replica (teal brand + Divine Glass + SVG icons)
///    on a flat #DFF3F3 mist wash — gradient replaced by solid mist.
///  • [clay]     - Same compact Home + Divine Glass chrome as [aqua]
///    (teal #098F90), with soft-3D / clay PNG Home icons.
enum ThemeStyle {
  classic,
  launcher,
  aqua,
  aquaLight,
  aquaMist,
  clay,
}

/// Inherited scope inserted above the Navigator (see main.dart) so every
/// widget that consults the active style - directly via [InoStyle.of] or
/// indirectly via `AppPalette.of` - rebuilds the moment the user picks a new
/// theme in Profile.
class InoStyleScope extends InheritedWidget {
  const InoStyleScope({super.key, required this.style, required super.child});

  final ThemeStyle style;

  static ThemeStyle of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<InoStyleScope>()?.style ??
      ThemeStyle.classic;

  @override
  bool updateShouldNotify(covariant InoStyleScope oldWidget) =>
      oldWidget.style != style;
}

/// Style-aware colour helpers - the one place the "darker in bold, lighter in
/// soft" rules live, so every surface shifts by the same amounts.
class InoStyle {
  InoStyle._();

  /// Sky brand (#0EA5E9) — classic / bold / soft / launcher.
  static const Color _skyBrand = Color(0xFF0EA5E9);

  /// Aqua brand (#098F90) — aqua / aquaLight / aquaMist / clay.
  static const Color _aquaBrand = Color(0xFF098F90);

  static ThemeStyle of(BuildContext context) => InoStyleScope.of(context);

  static bool isBold(BuildContext context) => false;
  static bool isSoft(BuildContext context) => false;
  static bool isLauncher(BuildContext context) =>
      of(context) == ThemeStyle.launcher;

  /// Teal #098F90 brand family ([aqua], [aquaLight], [aquaMist], or [clay]).
  static bool isAqua(BuildContext context) => usesAquaBrand(of(context));

  static bool usesAquaBrand(ThemeStyle style) =>
      style == ThemeStyle.aqua ||
      style == ThemeStyle.aquaLight ||
      style == ThemeStyle.aquaMist ||
      style == ThemeStyle.clay;

  /// Flat solid scaffold wash — no aurora / sky gradient ([aquaLight], [aquaMist]).
  static bool usesFlatBackdrop(BuildContext context) {
    final style = of(context);
    return style == ThemeStyle.aquaLight || style == ThemeStyle.aquaMist;
  }

  /// Flat #DFF3F3 mist wash — circular chrome needs porcelain + teal rim
  /// so back / header actions don't dissolve into the backdrop.
  static bool isAquaMist(BuildContext context) =>
      of(context) == ThemeStyle.aquaMist;

  /// Compact Home + Divine Glass chrome — launcher + aqua family + clay.
  static bool usesDivineGlass(BuildContext context) =>
      usesDivineGlassStyle(of(context));

  static bool usesDivineGlassStyle(ThemeStyle style) =>
      style == ThemeStyle.launcher ||
      style == ThemeStyle.clay ||
      style == ThemeStyle.aqua ||
      style == ThemeStyle.aquaLight ||
      style == ThemeStyle.aquaMist;

  /// Soft-3D / clay PNG Home icons (Quick Actions, vaults, tools, attention).
  /// Only [ThemeStyle.clay]; aqua family / launcher keep tinted SVGs.
  static bool usesHome3dIcons(BuildContext context) =>
      usesHome3dIconsStyle(of(context));

  static bool usesHome3dIconsStyle(ThemeStyle style) =>
      style == ThemeStyle.clay;

  /// Brand accent for the active style: teal #098F90 in Aqua family, else sky.
  static Color brandAccent(BuildContext context) {
    return usesAquaBrand(of(context)) ? _aquaBrand : _skyBrand;
  }

  /// Deepens a colour, gaining a little saturation on the way down so it stays
  /// vivid instead of turning muddy (same curve as the badge painter's shade).
  static Color deepen(Color c, [double amount = 0.14]) {
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withLightness((hsl.lightness - amount).clamp(0.0, 1.0))
        .withSaturation((hsl.saturation + amount * 0.55).clamp(0.0, 1.0))
        .toColor();
  }

  /// Lifts a colour towards light - the soft theme's counterpart to [deepen].
  static Color soften(Color c, [double amount = 0.10]) {
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withLightness((hsl.lightness + amount).clamp(0.0, 1.0))
        .toColor();
  }

  static Color accent(BuildContext context, Color c) {
    switch (of(context)) {
      case ThemeStyle.classic:
      case ThemeStyle.launcher:
      case ThemeStyle.aqua:
      case ThemeStyle.aquaLight:
      case ThemeStyle.aquaMist:
      case ThemeStyle.clay:
        return c;
    }
  }

  /// The solid fill an accent-driven container wears in the bold theme - the
  /// colour that used to sit on its small inner icon badge, run deeper.
  static Color boldFill(Color accentColor) => deepen(accentColor, 0.10);

  /// The bold container's edge: deeper still than the fill so the card keeps a
  /// definite border.
  static Color boldBorder(Color accentColor) => deepen(accentColor, 0.24);

  /// Secondary (label) text on a bold accent fill.
  static Color get boldTextSecondary => Colors.white.withValues(alpha: 0.85);

  /// A branded gradient resolved for the active style. Classic, launcher, clay and aqua family leave the gradient as authored.
  static Gradient gradient(BuildContext context, Gradient g) {
    return g;
  }
}
