import 'package:flutter/material.dart';

/// Equal-width grid tile for Wrap layouts. Uses a shared [minHeight] so rows
/// stay uniform without undersizing content (avoids bottom overflow).
class ResponsiveGridTile extends StatelessWidget {
  const ResponsiveGridTile({
    super.key,
    required this.width,
    required this.minHeight,
    required this.child,
    this.height,
  });

  final double width;
  final double minHeight;
  final double? height;
  final Widget child;

  /// Tile width for a [columns]-wide Wrap inside [availableWidth].
  static double tileWidth({
    required double availableWidth,
    required int columns,
    required double gap,
  }) {
    final cols = columns.clamp(1, 12);
    if (cols == 1) return availableWidth;
    return (availableWidth - gap * (cols - 1)) / cols;
  }

  @override
  Widget build(BuildContext context) {
    final h = height;
    return SizedBox(
      width: width,
      height: h,
      child: h == null
          ? ConstrainedBox(
              constraints: BoxConstraints(minHeight: minHeight),
              child: child,
            )
          : child,
    );
  }
}
