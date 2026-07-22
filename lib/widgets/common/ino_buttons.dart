import 'package:flutter/material.dart';

import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../pressable_scale.dart';

/// The primary CTA of the design system: a 56dp, radius-18 pill filled with the
/// brand teal→cyan gradient, white semibold label, soft brand glow, optional
/// leading icon and a busy spinner state. Use for the single most important
/// action on a screen.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;

  /// When true (default) the button stretches to the available width.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    final child = Container(
      height: AppSizes.button,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        gradient: AppGradients.primary,
        borderRadius: BorderRadius.circular(AppRadius.button),
        boxShadow: enabled ? AppShadows.glow(AppColors.primaryGreen) : null,
      ),
      child: Opacity(
        opacity: enabled || busy ? 1 : 0.55,
        child: Center(
          child: busy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : Row(
                  mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                    ],
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.subtitle.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 15.5,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
    return PressableScale(
      child: GestureDetector(onTap: enabled ? onPressed : null, child: child),
    );
  }
}

/// The secondary action: white (surface) fill, light hairline border, same
/// 56dp/radius-18 geometry so button pairs read as one family.
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return PressableScale(
      child: Material(
        color: palette.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
          side: BorderSide(color: palette.border),
        ),
        child: InkWell(
          onTap: onPressed,
          child: Container(
            height: AppSizes.button,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, color: palette.textPrimary, size: 20),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.subtitle.copyWith(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
