import 'package:flutter/material.dart';

import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_style.dart';
import '../common/liquid_glass.dart';
import '../common/shiny_border.dart';
import '../common/shiny_icon.dart';
import '../pressable_scale.dart';

/// A premium gradient grid card for the Property & Finance Tools hub - a large
/// icon badge, title and short description, with a ripple + press animation.
class ToolGridCard extends StatelessWidget {
  const ToolGridCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final themeStyle = InoStyle.of(context);
    final bold = themeStyle == ThemeStyle.bold;
    final soft = themeStyle == ThemeStyle.soft;
    final launcher = themeStyle == ThemeStyle.launcher;

    final gradient = bold
        ? LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [InoStyle.boldFill(color), InoStyle.deepen(color, 0.18)],
          )
        : palette.cardGradient;
    final edge = bold ? InoStyle.boldBorder(color) : palette.border;

    final inner = Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          bold
              ? SizedBox(
                  width: 46,
                  height: 46,
                  child: Icon(icon, color: Colors.white, size: 36),
                )
              : launcher
                  ? Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(icon, color: color, size: 26),
                    )
                  : ShinyIcon(
                      icon: icon,
                      color: color,
                      size: 46,
                      iconSize: 24,
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
