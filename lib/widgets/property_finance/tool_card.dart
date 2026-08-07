import 'package:flutter/material.dart';

import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_style.dart';
import '../common/ino_svg_icon.dart';
import '../common/liquid_glass.dart';
import '../common/shiny_border.dart';
import '../common/shiny_icon.dart';
import '../pressable_scale.dart';

/// A premium gradient grid card for the Property & Finance Tools hub - a large
/// icon badge, title and short description, with a ripple + press animation.
///
/// Prefer [imageAsset] / [svgAsset] (same Home finance glyphs) when set.
class ToolGridCard extends StatelessWidget {
  const ToolGridCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.imageAsset,
    this.svgAsset,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  final String? imageAsset;
  final String? svgAsset;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final themeStyle = InoStyle.of(context);
    final bold = themeStyle == ThemeStyle.bold;
    final soft = themeStyle == ThemeStyle.soft;
    final launcher = InoStyle.usesDivineGlassStyle(themeStyle);

    final gradient = bold
        ? LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [InoStyle.boldFill(color), InoStyle.deepen(color, 0.18)],
          )
        : palette.cardGradient;
    final edge = bold ? InoStyle.boldBorder(color) : palette.border;

    Widget glyph({required double size, required Color tint}) {
      if (imageAsset != null) {
        return Image.asset(
          imageAsset!,
          width: size,
          height: size,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          gaplessPlayback: true,
        );
      }
      if (svgAsset != null) {
        return InoSvgIcon(svgAsset!, size: size, color: tint);
      }
      return Icon(icon, color: tint, size: size);
    }

    final inner = Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          bold
              ? SizedBox(
                  width: 64,
                  height: 64,
                  child: Center(
                    child: glyph(size: 48, tint: Colors.white),
                  ),
                )
              : launcher
                  ? Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Center(
                        child: glyph(size: 38, tint: color),
                      ),
                    )
                  : imageAsset != null || svgAsset != null
                      ? Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(AppRadius.chip),
                          ),
                          child: Center(
                            child: glyph(size: 34, tint: color),
                          ),
                        )
                      : ShinyIcon(
                          icon: icon,
                          color: color,
                          size: 60,
                          iconSize: 32,
                          radius: AppRadius.chip,
                          style: ShinyIconStyle.glass,
                        ),
          const SizedBox(height: AppSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                title,
                maxLines: 1,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: AppText.subtitle.copyWith(
                  color: bold ? Colors.white : palette.textPrimary,
                  fontSize: launcher ? 16 : 15,
                  fontWeight: launcher ? FontWeight.w800 : null,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: AppText.caption.copyWith(
                  color: bold
                      ? InoStyle.boldTextSecondary
                      : palette.textSecondary,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ],
      ),
    );

    final surface = launcher
        ? LiquidGlass(
            borderRadius: BorderRadius.circular(AppRadius.card),
            blur: 16,
            frost: 0.95,
            padding: EdgeInsets.zero,
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(AppRadius.card),
                splashColor: color.withValues(alpha: 0.12),
                child: inner,
              ),
            ),
          )
        : ShinyBorder(
            radius: AppRadius.card,
            width: 1,
            enabled: soft,
            child: Container(
              decoration: BoxDecoration(
                gradient: gradient,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: edge, width: bold ? 2.5 : 1),
                boxShadow: palette.cardShadow,
              ),
              clipBehavior: Clip.antiAlias,
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: onTap,
                  splashColor: color.withValues(alpha: 0.12),
                  highlightColor: color.withValues(alpha: 0.05),
                  child: inner,
                ),
              ),
            ),
          );

    return PressableScale(pressedScale: 0.97, child: surface);
  }
}
