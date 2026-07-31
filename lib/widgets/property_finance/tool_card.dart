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

    // Bold: the badge colour floods the whole card (run deeper) and the glyph
    // stays put in plain white. Classic/soft: a white Divine Glass card with a
    // hairline border - the pastel colour lives in the icon chip alone.
    final gradient = bold
        ? LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [InoStyle.boldFill(color), InoStyle.deepen(color, 0.18)],
          )
        : palette.cardGradient;
    final edge = bold ? InoStyle.boldBorder(color) : palette.border;

    return PressableScale(
      pressedScale: 0.97,
      // Soft: the hairline border picks up a glass sheen.
      child: ShinyBorder(
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
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Bold keeps the glyph in the same 46px slot, plain white -
                    // the card itself is now the coloured container. Classic
                    // shows a pastel glass chip carrying the accent glyph.
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
                            fontSize: 15,
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
              ),
            ),
          ),
        ),
      ),
    );
  }
}
