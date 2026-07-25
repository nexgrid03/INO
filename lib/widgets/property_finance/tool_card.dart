import 'package:flutter/material.dart';

import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
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
    final base = palette.surface;
    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color.alphaBlend(color.withValues(alpha: 0.16), base),
        Color.alphaBlend(color.withValues(alpha: 0.04), base),
      ],
    );

    return PressableScale(
      pressedScale: 0.97,
      child: Container(
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(AppRadius.card),
          // Thick, solid accent edge in the same colour as the filled icon
          // badge - matching the tool tiles on the Home screen.
          border: Border.all(color: color, width: 2.5),
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
                  ShinyIcon(
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
                            color: palette.textPrimary, fontSize: 15),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.caption.copyWith(
                            color: palette.textSecondary, height: 1.3),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
