import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../pressable_scale.dart';
import 'liquid_glass.dart';

/// The app's one canonical back affordance: an iOS 26 Liquid Glass circle -
/// the page blurs through it, ringed by a bright hairline, with a rounded
/// arrow on top.
///
/// Drop it at the top-left of any pushed page. It renders nothing when the
/// route cannot pop (e.g. on tab roots), so it is always safe to include.
class InoBackButton extends StatelessWidget {
  const InoBackButton({super.key, this.onTap, this.size = 44});

  /// Defaults to `Navigator.maybePop`.
  final VoidCallback? onTap;

  final double size;

  @override
  Widget build(BuildContext context) {
    if (onTap == null && !(Navigator.of(context).canPop())) {
      return const SizedBox.shrink();
    }
    final palette = AppPalette.of(context);
    return PressableScale(
      pressedScale: 0.9,
      child: Tooltip(
        message: MaterialLocalizations.of(context).backButtonTooltip,
        child: LiquidGlass(
          circle: true,
          blur: 18,
          child: Material(
            type: MaterialType.transparency,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap ?? () => Navigator.of(context).maybePop(),
              child: SizedBox(
                width: size,
                height: size,
                child: Icon(
                  Icons.arrow_back_rounded,
                  size: size * 0.48,
                  color: palette.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
