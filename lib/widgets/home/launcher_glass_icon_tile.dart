import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/theme_style.dart';
import '../common/ino_svg_icon.dart';
import '../common/liquid_glass.dart';
import '../pressable_scale.dart';

/// Shared PhonePe-style launcher tile:
/// same neutral glass box → centred 3D/SVG/icon → count badge on the corner.
///
/// Top inset leaves room for the badge so it is never clipped by the section
/// above. **Aqua Light / Aqua Mist** use a milkier frosted plate + rim so tiles
/// stay readable on the flat solid backdrop.
///
/// Labels always stay on **one line** via [FittedBox] (scale down, never wrap).
class LauncherGlassIconTile extends StatelessWidget {
  const LauncherGlassIconTile({
    super.key,
    required this.label,
    required this.accent,
    required this.onTap,
    this.icon,
    this.svgAsset,
    this.imageAsset,
    this.count,
  }) : assert(
          icon != null || svgAsset != null || imageAsset != null,
          'Provide icon, svgAsset, or imageAsset',
        );

  final String label;
  final Color accent;
  final VoidCallback onTap;
  final IconData? icon;
  final String? svgAsset;
  final String? imageAsset;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final dark = palette.isDark;
    final flat = InoStyle.usesFlatBackdrop(context);

    // Flat Aqua Light: opaque glass + rim + lift so tiles stay readable.
    final frost = flat ? 1.35 : (dark ? 1.2 : 0.72);
    // Tight inset so glyphs fill the plate without looking sparse.
    const iconPad = 4.0;
    const glyphSize = 62.0;
    final plate = LiquidGlass(
      borderRadius: BorderRadius.circular(20),
      enableBlur: flat,
      blur: flat ? 18 : 20,
      frost: frost,
      shadow: flat,
      padding: const EdgeInsets.all(iconPad),
      child: imageAsset != null
          ? Image.asset(
              imageAsset!,
              fit: BoxFit.contain,
              alignment: Alignment.center,
              filterQuality: FilterQuality.high,
              gaplessPlayback: true,
            )
          : Center(
              child: svgAsset != null
                  ? InoSvgIcon(
                      svgAsset!,
                      size: glyphSize,
                      color: accent,
                    )
                  : Icon(icon, color: accent, size: glyphSize),
            ),
    );

    final tile = flat
        ? DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.85),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryGreen.withValues(alpha: 0.10),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: plate,
          )
        : plate;

    return PressableScale(
      pressedScale: 0.96,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: AspectRatio(
                aspectRatio: 1,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    Positioned.fill(child: tile),
                    if (count != null)
                      Positioned(
                        top: -8,
                        right: -4,
                        child: _Badge(
                          count: count!,
                          accent: accent,
                          dark: dark,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.count,
    required this.accent,
    required this.dark,
  });

  final int count;
  final Color accent;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: accent,
        shape: BoxShape.circle,
        border: Border.all(
          color: dark ? const Color(0xFF0B1220) : Colors.white,
          width: 2,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
  }
}
