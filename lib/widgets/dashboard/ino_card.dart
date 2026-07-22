import 'package:flutter/material.dart';

import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../pressable_scale.dart';

/// The premium surface primitive every dashboard section sits on.
///
/// Rounded, softly shadowed, hairline-bordered card that reads correctly in
/// both light and dark mode (it draws from [AppPalette], never hard-coded
/// white). When [onTap] is provided it gains an ink ripple + the brand
/// [PressableScale] "squish", matching the tactility used on the login screen.
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

  /// Optional gradient fill (e.g. hero cards). Falls back to the surface colour.
  final Gradient? gradient;

  /// Override the hairline border (e.g. a coloured status edge).
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final shape = BorderRadius.circular(radius);

    final decorated = Container(
      decoration: BoxDecoration(
        // Default fill is a subtle top-lit glass gradient; callers can override
        // with a solid/branded [gradient].
        gradient: gradient ?? palette.cardGradient,
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
