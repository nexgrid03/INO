import 'package:flutter/material.dart';

import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../common/liquid_glass.dart';
import '../pressable_scale.dart';

/// The premium surface primitive every dashboard section sits on.
///
/// Frosted [LiquidGlass] by default. When [gradient] is set (hero cards),
/// falls back to a painted gradient surface.
class InoCard extends StatelessWidget {
  const InoCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.onTap,
    this.radius = AppRadius.card,
    this.gradient,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double radius;

  /// Optional gradient fill (e.g. hero cards). Falls back to glass frost.
  final Gradient? gradient;

  /// Override the hairline border (e.g. a coloured status edge).
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final shape = BorderRadius.circular(radius);

    if (gradient == null) {
      final glass = LiquidGlass(
        borderRadius: shape,
        blur: 20,
        frost: palette.isDark ? 1.05 : 0.72,
        padding: padding,
        child: child,
      );
      if (onTap == null) return glass;
      return PressableScale(
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: glass,
        ),
      );
    }

    final decorated = Container(
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: shape,
        border: Border.all(
          color: borderColor ?? palette.border,
          width: 1,
        ),
        boxShadow: palette.cardShadow,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: shape,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );

    if (onTap == null) return decorated;
    return PressableScale(child: decorated);
  }
}
