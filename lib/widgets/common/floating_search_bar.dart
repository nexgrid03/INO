import 'package:flutter/material.dart';

import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../pressable_scale.dart';

/// The design-system floating search bar: 52dp tall, radius 16, white surface
/// with a soft floating shadow and a leading search icon.
///
/// Two modes:
///   • **Launcher** — pass [onTap] (and no [controller]); the bar is a tappable
///     affordance that opens a dedicated search screen.
///   • **Live field** — pass a [controller] / [onChanged]; the bar edits text
///     in place.
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

  bool get _isLauncher => onTap != null && controller == null;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final bar = Container(
      height: height ?? AppSizes.search,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(AppRadius.search),
        border: Border.all(color: palette.border),
        boxShadow: palette.cardShadow,
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 21, color: palette.textFaint),
          const SizedBox(width: 10),
          Expanded(
            child: _isLauncher
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
    );

    if (!_isLauncher) return bar;
    return PressableScale(
      pressedScale: 0.98,
      child: GestureDetector(onTap: onTap, child: bar),
    );
  }
}
