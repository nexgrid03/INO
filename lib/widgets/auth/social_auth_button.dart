import 'package:flutter/material.dart';

import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../pressable_scale.dart';

/// A quiet, outlined "Continue with …" button for federated sign-in
/// (Google / Phone / Apple).
///
/// Deliberately understated — a theme-aware surface with a soft brand-tinted
/// border and the glyph seated in a small tinted well — so the gradient
/// primary CTA stays the clear focus. Pass [brand] as the leading glyph (see
/// [GoogleGlyph] / [Icon(Icons.apple)]).
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
            color: palette.surface,
            borderRadius: BorderRadius.circular(AppRadius.button),
            border: Border.all(
              color: AppColors.primaryGreen
                  .withValues(alpha: palette.isDark ? 0.30 : 0.14),
              width: 1.4,
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
              ? SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: palette.textSecondary,
                  ),
                )
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

/// A compact, recognisable Google "G" mark drawn without shipping an asset.
///
/// Uses Google's blue for a clean, on-brand glyph that reads instantly at small
/// sizes. Swap for the official multicolour asset later if desired.
class GoogleGlyph extends StatelessWidget {
  const GoogleGlyph({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Text(
      'G',
      style: TextStyle(
        fontSize: size,
        fontWeight: FontWeight.w800,
        color: const Color(0xFF4285F4),
        height: 1,
      ),
    );
  }
}
