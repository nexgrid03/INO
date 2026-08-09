import 'package:flutter/material.dart';

import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_style.dart';
import '../common/ino_svg_icon.dart';
import '../common/liquid_glass.dart';
import '../common/shiny_border.dart';
import '../common/shiny_icon.dart';
import '../pressable_scale.dart';

/// A premium tool card for the Property & Finance Tools hub.
///
/// Wide (list) cards use a horizontal row: icon + title/subtitle.
/// Compact grid tiles keep the stacked icon-above-label layout.
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final palette = AppPalette.of(context);
        final themeStyle = InoStyle.of(context);
        final launcher = InoStyle.usesDivineGlassStyle(themeStyle);
        final cardW = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        // Full-width phone rows and tablet half-width tiles read as list rows.
        final listLayout = cardW >= 160;

        final gradient = palette.cardGradient;
        final edge = palette.border;

        final badgeSize = listLayout
            ? (launcher ? 44.0 : 42.0)
            : (cardW < 120 ? 36.0 : (launcher ? 42.0 : 40.0));
        final glyphSize = listLayout
            ? (launcher ? 24.0 : 22.0)
            : (cardW < 120 ? 20.0 : (launcher ? 24.0 : 22.0));
        final pad = listLayout ? AppSpacing.sm : AppSpacing.xs;

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

        final badge = launcher
            ? Container(
                width: badgeSize,
                height: badgeSize,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(listLayout ? 14 : 12),
                ),
                child: Center(
                  child: glyph(size: glyphSize, tint: color),
                ),
              )
            : imageAsset != null || svgAsset != null
                ? Container(
                    width: badgeSize,
                    height: badgeSize,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: glyph(size: glyphSize, tint: color),
                    ),
                  )
                : ShinyIcon(
                    icon: icon,
                    color: color,
                    size: badgeSize,
                    iconSize: glyphSize,
                    radius: AppRadius.chip,
                    style: ShinyIconStyle.glass,
                  );

        final titleStyle = AppText.subtitle.copyWith(
          color: palette.textPrimary,
          fontSize: listLayout ? 15 : (cardW < 120 ? 10.5 : 11.5),
          fontWeight: launcher ? FontWeight.w800 : FontWeight.w700,
          height: 1.15,
        );
        final subtitleStyle = AppText.caption.copyWith(
          color: palette.textSecondary,
          fontSize: listLayout ? 12.5 : (cardW < 120 ? 9 : 9.5),
          height: 1.2,
        );

        final Widget inner;
        if (listLayout) {
          inner = Padding(
            padding: EdgeInsets.symmetric(
              horizontal: pad,
              vertical: AppSpacing.xs,
            ),
            child: Row(
              children: [
                badge,
                SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: titleStyle,
                      ),
                      if (subtitle.trim().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: subtitleStyle,
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 22,
                  color: palette.textSecondary.withValues(alpha: 0.7),
                ),
              ],
            ),
          );
        } else {
          inner = Padding(
            padding: EdgeInsets.all(pad),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: badge),
                const SizedBox(height: 4),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        flex: 3,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            title,
                            maxLines: 1,
                            softWrap: false,
                            textAlign: TextAlign.center,
                            style: titleStyle.copyWith(height: 1.0),
                          ),
                        ),
                      ),
                      if (subtitle.trim().isNotEmpty) ...[
                        const SizedBox(height: 1),
                        Flexible(
                          flex: 2,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              subtitle,
                              maxLines: 1,
                              softWrap: false,
                              textAlign: TextAlign.center,
                              style: subtitleStyle.copyWith(height: 1.0),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        final radius = BorderRadius.circular(listLayout ? 18 : 16);
        final surface = launcher
            ? LiquidGlass(
                borderRadius: radius,
                blur: 16,
                frost: 0.95,
                padding: EdgeInsets.zero,
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    onTap: onTap,
                    borderRadius: radius,
                    splashColor: color.withValues(alpha: 0.12),
                    child: inner,
                  ),
                ),
              )
            : ShinyBorder(
                radius: AppRadius.card,
                width: 1,
                enabled: false,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: gradient,
                    borderRadius: radius,
                    border: Border.all(color: edge, width: 1),
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
      },
    );
  }
}
