import 'package:flutter/material.dart';

import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../common/ino_svg_icon.dart';
import '../pressable_scale.dart';

/// Section - a single Quick Action.
///
/// Prefer [imageAsset] (3D PNG glyphs on a Flutter disc). Layout uses a fixed
/// square disc slot + label column so every Quick Action cell aligns.
/// Labels stay on one line via [FittedBox] (scale down — never wrap).
class QuickActionButton extends StatelessWidget {
  const QuickActionButton({
    super.key,
    this.icon,
    this.svgAsset,
    this.imageAsset,
    required this.label,
    required this.color,
    required this.onTap,
    this.enlarged = false,
  }) : assert(
          icon != null || svgAsset != null || imageAsset != null,
          'Provide icon, svgAsset, or imageAsset',
        );

  final IconData? icon;
  final String? svgAsset;
  final String? imageAsset;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool enlarged;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final dark = palette.isDark;
    final use3d = imageAsset != null;

    return PressableScale(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final cellW = constraints.maxWidth;
            // Same pixel size in every Expanded cell (equal cellW + fixed formula).
            final disc = enlarged
                ? (cellW * 0.88).clamp(64.0, 88.0)
                : cellW.clamp(0.0, 56.0);
            final glyph = enlarged
                ? (disc * 0.55).clamp(28.0, 48.0)
                : (disc * 0.42).clamp(16.0, 24.0);

            final Widget discChild;
            if (use3d) {
              // Flutter owns the teal disc; PNG is glyph-only → guaranteed
              // same circle size/alignment for every Quick Action.
              final glyphSize = disc * 0.64;
              discChild = SizedBox(
                width: disc,
                height: disc,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: AppColors.brandGradient,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primaryGreen
                            .withValues(alpha: dark ? 0.18 : 0.22),
                        blurRadius: enlarged ? 14 : 10,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Image.asset(
                      imageAsset!,
                      width: glyphSize,
                      height: glyphSize,
                      fit: BoxFit.contain,
                      alignment: Alignment.center,
                      filterQuality: FilterQuality.high,
                      gaplessPlayback: true,
                    ),
                  ),
                ),
              );
            } else {
              discChild = Container(
                width: disc,
                height: disc,
                decoration: BoxDecoration(
                  gradient: AppColors.brandGradient,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.glowOf(
                        context,
                        light: 0.28,
                        dark: 0.12,
                      ),
                      blurRadius:
                          dark ? (enlarged ? 12 : 8) : (enlarged ? 18 : 12),
                      offset: Offset(0, dark ? 4 : 6),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: svgAsset != null
                    ? InoSvgIcon(
                        svgAsset!,
                        size: glyph,
                        color: Colors.white,
                      )
                    : Icon(icon, color: Colors.white, size: glyph),
              );
            }

            // Disc slot matches the circle — no empty air under the icon.
            final discSlot = disc;

            return SizedBox(
              width: cellW,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: discSlot,
                    child: Center(child: discChild),
                  ),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      softWrap: false,
                      textAlign: TextAlign.center,
                      style: AppText.caption.copyWith(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: enlarged ? 12.5 : 12,
                        height: 1.0,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
