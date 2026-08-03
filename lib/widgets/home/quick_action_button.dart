import 'package:flutter/material.dart';

import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../common/ino_svg_icon.dart';
import '../pressable_scale.dart';

/// Section - a single Quick Action.
///
/// A circular pill: white glyph on a brand-gradient disc, caption below.
/// Prefer [svgAsset] (PhonePe-style launcher); [icon] remains as fallback.
///
/// When [enlarged] is true (Launcher / senior-friendly), the disc fills most
/// of the column and the glyph fills most of the disc — no nested glass/chip.
class QuickActionButton extends StatelessWidget {
  const QuickActionButton({
    super.key,
    this.icon,
    this.svgAsset,
    required this.label,
    required this.color,
    required this.onTap,
    this.enlarged = false,
  }) : assert(icon != null || svgAsset != null, 'Provide icon or svgAsset');

  final IconData? icon;
  final String? svgAsset;
  final String label;
  final Color color;
  final VoidCallback onTap;

  /// Bigger touch targets and icons for the Launcher theme.
  final bool enlarged;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final dark = palette.isDark;
    return PressableScale(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: enlarged ? 4 : 4),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Launcher: disc owns the column; glyph owns the disc.
              final disc = enlarged
                  ? (constraints.maxWidth * 0.88).clamp(64.0, 88.0)
                  : constraints.maxWidth.clamp(40.0, 56.0);
              final glyph = enlarged
                  ? (disc * 0.58).clamp(36.0, 50.0)
                  : (disc * 0.42).clamp(16.0, 24.0);
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
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
                          blurRadius: dark
                              ? (enlarged ? 12 : 8)
                              : (enlarged ? 18 : 12),
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
                  ),
                  SizedBox(height: enlarged ? 8 : AppSpacing.xs),
                  Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: AppText.caption.copyWith(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: enlarged ? 13 : 12,
                      height: 1.1,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
