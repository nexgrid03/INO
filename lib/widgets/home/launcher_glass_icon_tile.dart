import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../common/ino_svg_icon.dart';
import '../common/liquid_glass.dart';
import '../pressable_scale.dart';

/// Shared PhonePe-style launcher tile:
/// same neutral glass box for every item → large coloured icon →
/// optional count badge on the top-right → label under the box.
///
/// Never uses [BackdropFilter] — dense Home grids must stay smooth on
/// Flutter web (blur-per-tile caused blank content + severe lag).
class LauncherGlassIconTile extends StatelessWidget {
  const LauncherGlassIconTile({
    super.key,
    required this.label,
    required this.accent,
    required this.onTap,
    this.icon,
    this.svgAsset,
    this.count,
  }) : assert(icon != null || svgAsset != null, 'Provide icon or svgAsset');

  final String label;
  final Color accent;
  final VoidCallback onTap;
  final IconData? icon;
  final String? svgAsset;

  /// Shown as a corner badge when non-null.
  final int? count;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final dark = palette.isDark;

    return PressableScale(
      pressedScale: 0.96,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: LiquidGlass(
                      borderRadius: BorderRadius.circular(20),
                      enableBlur: false,
                      frost: dark ? 1.2 : 0.72,
                      shadow: false,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          // Finance / vault tiles: icon owns most of the cell.
                          final glyph =
                              (constraints.biggest.shortestSide * 0.70)
                                  .clamp(40.0, 60.0);
                          if (svgAsset != null) {
                            return Center(
                              child: InoSvgIcon(
                                svgAsset!,
                                size: glyph,
                                color: accent,
                              ),
                            );
                          }
                          return Center(
                            child: Icon(icon, color: accent, size: glyph),
                          );
                        },
                      ),
                    ),
                  ),
                  if (count != null)
                    Positioned(
                      top: -4,
                      right: -4,
                      child: _Badge(count: count!, accent: accent, dark: dark),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                height: 1.15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.count,
    required this.accent,
    required this.dark,
  });

  final int count;
  final Color accent;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: accent,
        shape: BoxShape.circle,
        border: Border.all(
          color: dark ? const Color(0xFF0B1220) : Colors.white,
          width: 2,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
  }
}
