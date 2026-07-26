import 'package:flutter/material.dart';

import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_style.dart';
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

    final base = palette.surface;
    // Bold: the badge colour floods the whole card (run deeper) and the glyph
    // stays put in plain white. Soft: an even lighter wash + glass badge.
    final gradient = bold
        ? LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [InoStyle.boldFill(color), InoStyle.deepen(color, 0.18)],
          )
        : LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.alphaBlend(
                color.withValues(alpha: soft ? 0.10 : 0.16),
                base,
              ),
              Color.alphaBlend(
                color.withValues(alpha: soft ? 0.03 : 0.04),
                base,
              ),
            ],
          );
    // Soft keeps the classic accent edge - the glass sheen comes from the
    // ShinyBorder overlay below.
    final edge = bold ? InoStyle.boldBorder(color) : color;

    return PressableScale(
      pressedScale: 0.97,
      // Soft: the classic accent border picks up a glass sheen.
      child: ShinyBorder(
        radius: AppRadius.card,
        width: 2.5,
        enabled: soft,
        child: Container(
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(AppRadius.card),
            // Thick, solid accent edge in the same colour as the filled icon
            // badge - matching the tool tiles on the Home screen.
            border: Border.all(color: edge, width: 2.5),
            boxShadow: palette.cardShadow,
          ),
          clipBehavior: Clip.antiAlias,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              splashColor: color.withValues(alpha: 0.12),
              highlightColor: color.withValues(alpha: 0.05),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Bold keeps the glyph in the same 46px slot, plain white -
                    // the card itself is now the coloured container, so the
                    // glyph grows to fill the freed slot.
                    bold
                        ? SizedBox(
                            width: 46,
                            height: 46,
                            child: Icon(icon, color: Colors.white, size: 36),
                          )
                        : ShinyIcon(
                            icon: icon,
                            color: color,
                            size: 46,
                            iconSize: 26,
                            radius: AppRadius.chip,
                            style: ShinyIconStyle.filled,
                          ),
                    const SizedBox(height: AppSpacing.sm),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.subtitle.copyWith(
                            color: bold ? Colors.white : palette.textPrimary,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          maxLines: 2,
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
              ),
            ),
          ),
        ),
      ),
    );
  }
}
