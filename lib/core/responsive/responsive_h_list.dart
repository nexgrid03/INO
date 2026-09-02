import 'package:flutter/material.dart';

import 'screen_breakpoints.dart';

/// Horizontal card strip with breakpoint + text-scale aware height so fixed
/// Column children do not yellow-black overflow on small phones.
class ResponsiveHList extends StatelessWidget {
  const ResponsiveHList({
    super.key,
    required this.baseHeight,
    required this.itemBuilder,
    required this.itemCount,
    this.padding,
    this.separatorWidth = 12,
    this.physics,
  });

  final double baseHeight;
  final IndexedWidgetBuilder itemBuilder;
  final int itemCount;
  final EdgeInsetsGeometry? padding;
  final double separatorWidth;
  final ScrollPhysics? physics;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final height = ScreenBreakpoints.getHorizontalCardHeight(
      width,
      base: baseHeight,
      textScale: textScale,
    );

    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        // Null inherits the app-wide InoScrollBehavior, so a horizontal rail
        // scrolls with exactly the same spring as the page behind it.
        physics: physics,
        padding: padding,
        itemCount: itemCount,
        separatorBuilder: (_, _) => SizedBox(width: separatorWidth),
        itemBuilder: itemBuilder,
      ),
    );
  }
}
