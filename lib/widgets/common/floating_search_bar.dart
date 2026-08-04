import 'package:flutter/material.dart';

import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_style.dart';
import '../pressable_scale.dart';
import 'liquid_glass.dart';

/// Design-system floating search bar.
///
/// • **Launcher / Aqua** — solid white (or dark surface) pill with hairline.
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
                      // Theme InputDecoration is filled white — that stacks a
                      // second plate on the bar chrome (Property etc.). Match
                      // Wallets: chrome only, transparent field.
                      decoration: InputDecoration(
                        hintText: hint,
                        hintStyle: AppText.body.copyWith(
                          color: palette.textFaint,
                        ),
                        isCollapsed: true,
                        filled: false,
                        fillColor: Colors.transparent,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        errorBorder: InputBorder.none,
                        focusedErrorBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
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
      // Solid surface pill — translucent tint vanished on sky washes
      // (Property / module hubs). Same white plate as filter chips.
      bar = DecoratedBox(
        decoration: BoxDecoration(
          color: palette.isDark ? palette.surface : Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.search),
          border: Border.all(color: palette.border),
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
