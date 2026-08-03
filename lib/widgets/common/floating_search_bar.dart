import 'package:flutter/material.dart';

import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_style.dart';
import '../pressable_scale.dart';
import 'liquid_glass.dart';

/// Design-system floating search bar.
///
/// • **Launcher theme** — plain translucent pill (no milky/white frost).
/// • **Other themes** — frosted [LiquidGlass] surface.
///
/// Two input modes:
///   • **Tap launcher** — pass [onTap] (no [controller]); opens a search screen.
///   • **Live field** — pass [controller] / [onChanged]; edits text in place.
class FloatingSearchBar extends StatelessWidget {
  const FloatingSearchBar({
    super.key,
    required this.hint,
    this.onTap,
    this.controller,
    this.onChanged,
    this.autofocus = false,
    this.trailing,
    this.height,
  });

  final String hint;
  final VoidCallback? onTap;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final bool autofocus;

  /// Optional trailing control (e.g. a filter or clear button).
  final Widget? trailing;

  /// Optional height override (defaults to the design-system 52dp).
  final double? height;

  bool get _isTapOnly => onTap != null && controller == null;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final launcher = InoStyle.usesDivineGlass(context);
    final h = height ?? AppSizes.search;

    final field = SizedBox(
      height: h,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            Icon(Icons.search_rounded, size: 21, color: palette.textFaint),
            const SizedBox(width: 10),
            Expanded(
              child: _isTapOnly
                  ? Text(
                      hint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body.copyWith(color: palette.textFaint),
                    )
                  : TextField(
                      controller: controller,
                      onChanged: onChanged,
                      autofocus: autofocus,
                      style: AppText.body.copyWith(color: palette.textPrimary),
                      cursorColor: AppColors.primaryGreen,
                      decoration: InputDecoration(
                        hintText: hint,
                        hintStyle: AppText.body.copyWith(
                          color: palette.textFaint,
                        ),
                        border: InputBorder.none,
                        isCollapsed: true,
                      ),
                    ),
            ),
            ?trailing,
          ],
        ),
      ),
    );

    final Widget bar;
    if (launcher) {
      // Plain translucent — sky shows through; no white fill / frost.
      bar = DecoratedBox(
        decoration: BoxDecoration(
          color: palette.isDark
              ? Colors.white.withValues(alpha: 0.06)
              : AppColors.primaryGreen.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(AppRadius.search),
          border: Border.all(
            color: palette.isDark
                ? Colors.white.withValues(alpha: 0.14)
                : AppColors.primaryGreen.withValues(alpha: 0.18),
          ),
        ),
        child: field,
      );
    } else {
      bar = LiquidGlass(
        borderRadius: BorderRadius.circular(AppRadius.search),
        blur: 18,
        frost: palette.isDark ? 1.0 : 0.72,
        shadow: true,
        padding: EdgeInsets.zero,
        child: field,
      );
    }

    if (!_isTapOnly) return bar;
    return PressableScale(
      pressedScale: 0.98,
      child: GestureDetector(onTap: onTap, child: bar),
    );
  }
}
