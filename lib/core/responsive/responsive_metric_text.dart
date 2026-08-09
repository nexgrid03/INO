import 'package:flutter/material.dart';

/// Single-line metric / currency text that scales down to fit instead of
/// overflowing. Use for hero totals and dense result values.
class ResponsiveMetricText extends StatelessWidget {
  const ResponsiveMetricText(
    this.text, {
    super.key,
    this.style,
    this.textAlign = TextAlign.start,
    this.maxLines = 1,
    this.alignment,
  });

  final String text;
  final TextStyle? style;
  final TextAlign textAlign;
  final int maxLines;
  final AlignmentGeometry? alignment;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: alignment ??
          switch (textAlign) {
            TextAlign.center => Alignment.center,
            TextAlign.end || TextAlign.right => Alignment.centerRight,
            _ => Alignment.centerLeft,
          },
      child: Text(
        text,
        maxLines: maxLines,
        softWrap: maxLines > 1,
        overflow: TextOverflow.ellipsis,
        textAlign: textAlign,
        style: style,
      ),
    );
  }
}
