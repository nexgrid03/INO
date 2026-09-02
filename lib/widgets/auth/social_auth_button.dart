import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../pressable_scale.dart';
import '../common/ino_loader.dart';

/// A quiet, outlined "Continue with …" button for federated sign-in
/// (Google / Phone / Apple).
///
/// Deliberately understated - a theme-aware surface with a soft brand-tinted
/// border and the glyph seated in a small tinted well - so the gradient
/// primary CTA stays the clear focus. Pass [brand] as the leading glyph (see
/// [GoogleGlyph] / [AppleGlyph]).
class SocialAuthButton extends StatelessWidget {
  const SocialAuthButton({
    super.key,
    required this.label,
    required this.brand,
    required this.onPressed,
    this.busy = false,
  });

  final String label;
  final Widget brand;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return PressableScale(
      child: GestureDetector(
        onTap: busy ? null : onPressed,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: AppSizes.button,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: palette.isDark
                ? palette.surface
                : Colors.white.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(AppRadius.button),
            border: Border.all(
              color: palette.isDark
                  ? AppColors.primaryGreen.withValues(alpha: 0.30)
                  : AppColors.tealPale,
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: palette.shadow
                    .withValues(alpha: 0.04 * palette.shadowStrength),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: busy
              ? InoLoader(size: 20, color: palette.textSecondary)
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: AppColors.primaryGreen
                            .withValues(alpha: palette.isDark ? 0.16 : 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(child: brand),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Icon-only social affordance — circular well with the brand glyph, no label.
/// Used in a horizontal row under the OR divider on Login.
class SocialAuthIconButton extends StatelessWidget {
  const SocialAuthIconButton({
    super.key,
    required this.brand,
    required this.onPressed,
    required this.tooltip,
    this.busy = false,
    this.size = 52,
  });

  final Widget brand;
  final VoidCallback? onPressed;
  final String tooltip;
  final bool busy;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    // Hover tooltips on web linger over the footer ("Continue with Google").
    // Long-press keeps accessibility without a sticky overlay.
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 600),
      preferBelow: true,
      triggerMode: TooltipTriggerMode.longPress,
      child: PressableScale(
        child: GestureDetector(
          onTap: busy ? null : onPressed,
          behavior: HitTestBehavior.opaque,
          child: Semantics(
            button: true,
            label: tooltip,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: palette.isDark
                    ? palette.surface
                    : Colors.white.withValues(alpha: 0.9),
                shape: BoxShape.circle,
                border: Border.all(
                  color: palette.isDark
                      ? AppColors.primaryGreen.withValues(alpha: 0.30)
                      : AppColors.tealPale,
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: palette.shadow
                        .withValues(alpha: 0.05 * palette.shadowStrength),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: busy
                  ? InoLoader(size: 22, color: palette.textSecondary)
                  : brand,
            ),
          ),
        ),
      ),
    );
  }
}

/// Official multicolour Google "G" mark (SVG, full viewBox — no clipping).
class GoogleGlyph extends StatelessWidget {
  const GoogleGlyph({super.key, this.size = 22});

  final double size;

  /// Official Google "G" paths (48×48 viewBox).
  static const _svg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48">
  <path fill="#EA4335" d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z"/>
  <path fill="#4285F4" d="M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z"/>
  <path fill="#FBBC05" d="M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 9.78l7.97-6.19z"/>
  <path fill="#34A853" d="M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z"/>
</svg>
''';

  @override
  Widget build(BuildContext context) {
    return SvgPicture.string(
      _svg,
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }
}

/// Apple logo for Sign in with Apple.
class AppleGlyph extends StatelessWidget {
  const AppleGlyph({super.key, this.size = 24, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Icon(
      Icons.apple,
      size: size,
      color: color ?? (palette.isDark ? Colors.white : Colors.black),
    );
  }
}
