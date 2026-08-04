import 'package:flutter/material.dart';

import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_style.dart';
import '../common/liquid_glass.dart';
import '../pressable_scale.dart';

export 'divine_glass_kit.dart';
export 'divine_glass_page.dart';

/// True when Profile → App theme is Launcher or Aqua (Divine Glass restyles).
bool divineGlassEnabled(BuildContext context) =>
    InoStyle.usesDivineGlass(context);

/// Shared Divine Glass surface — frosted card used across Launcher screens.
class DivineGlassCard extends StatelessWidget {
  const DivineGlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 20.0,
    this.onTap,
    this.blur = 20,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final double blur;

  @override
  Widget build(BuildContext context) {
    final glass = LiquidGlass(
      borderRadius: BorderRadius.circular(radius),
      blur: blur,
      padding: padding,
      child: child,
    );
    if (onTap == null) return glass;
    return PressableScale(
      pressedScale: 0.98,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: glass,
      ),
    );
  }
}

/// Large page title used on Divine Glass hubs (Profile-style).
///
/// Floats on the sky wash — no opaque slab — for a clean, cozy look.
class DivineGlassPageTitle extends StatelessWidget {
  const DivineGlassPageTitle(
    this.title, {
    super.key,
    this.leading,
    this.trailing,
  });

  final String title;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.pageHeading(palette.headingInk),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// Uppercase section caption matching Figma Divine Glass settings groups.
class DivineGlassCaption extends StatelessWidget {
  const DivineGlassCaption(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, AppSpacing.xs),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: palette.textFaint,
        ),
      ),
    );
  }
}

/// Coloured icon chip used in Divine Glass list rows / tool tiles.
class DivineGlassIconChip extends StatelessWidget {
  const DivineGlassIconChip({
    super.key,
    required this.icon,
    required this.accent,
    this.size = 44,
    this.iconSize = 22,
  });

  final IconData icon;
  final Color accent;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: accent, size: iconSize),
    );
  }
}

/// Frosted glass card used across themes for a consistent glassy surface.
class AdaptiveGlassCard extends StatelessWidget {
  const AdaptiveGlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final r = radius ?? AppRadius.card;
    return LiquidGlass(
      borderRadius: BorderRadius.circular(r),
      blur: 20,
      frost: palette.isDark ? 1.05 : 0.72,
      padding: padding,
      child: child,
    );
  }
}
