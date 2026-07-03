import 'package:flutter/material.dart';

import '../../services/net_worth_service.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../pressable_scale.dart';

/// An interactive net-worth line chart: a range selector (7D / 30D / 3M / 6M /
/// 1Y), an animated draw-in, and tap-to-inspect with a tooltip that snaps to the
/// nearest point. Pure `CustomPaint` — no charting dependency.
class NetWorthChart extends StatefulWidget {
  const NetWorthChart({super.key, this.height = 200});

  final double height;

  @override
  State<NetWorthChart> createState() => _NetWorthChartState();
}

class _NetWorthChartState extends State<NetWorthChart>
    with SingleTickerProviderStateMixin {
  NetWorthRange _range = NetWorthRange.month;
  late List<NetWorthPoint> _points = NetWorthService.instance.seriesFor(_range);
  int? _selected;

  late final AnimationController _draw = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..forward();

  @override
  void dispose() {
    _draw.dispose();
    super.dispose();
  }

  void _selectRange(NetWorthRange range) {
    if (range == _range) return;
    setState(() {
      _range = range;
      _points = NetWorthService.instance.seriesFor(range);
      _selected = null;
    });
    _draw
      ..reset()
      ..forward();
  }

  void _handleTouch(Offset local, Size size) {
    if (_points.length < 2) return;
    final dx = local.dx.clamp(0.0, size.width);
    final index = ((dx / size.width) * (_points.length - 1)).round();
    if (index != _selected) {
      setState(() => _selected = index.clamp(0, _points.length - 1));
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _RangeSelector(selected: _range, onSelect: _selectRange),
        const SizedBox(height: AppSpacing.md),
        LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, widget.height);
            return GestureDetector(
              onTapDown: (d) => _handleTouch(d.localPosition, size),
              onHorizontalDragUpdate: (d) =>
                  _handleTouch(d.localPosition, size),
              onHorizontalDragEnd: (_) => setState(() => _selected = null),
              onTapUp: (_) => setState(() => _selected = null),
              child: AnimatedBuilder(
                animation: _draw,
                builder: (context, _) => CustomPaint(
                  size: size,
                  painter: _ChartPainter(
                    points: _points,
                    progress: Curves.easeOutCubic.transform(_draw.value),
                    selected: _selected,
                    line: AppColors.primaryGreen,
                    fillTop: AppColors.primaryGreen.withValues(alpha: 0.22),
                    fillBottom: AppColors.primaryGreen.withValues(alpha: 0.0),
                    grid: palette.border,
                    dotBorder: palette.surface,
                    tooltipBg: palette.textPrimary,
                    tooltipFg: palette.surface,
                    isDark: palette.isDark,
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: AppSpacing.xs),
        _AxisLabels(points: _points, range: _range, palette: palette),
      ],
    );
  }
}

class _RangeSelector extends StatelessWidget {
  const _RangeSelector({required this.selected, required this.onSelect});

  final NetWorthRange selected;
  final ValueChanged<NetWorthRange> onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: palette.surfaceVariant,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        children: [
          for (final r in NetWorthRange.values)
            Expanded(
              child: PressableScale(
                pressedScale: 0.96,
                child: GestureDetector(
                  onTap: () => onSelect(r),
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: r == selected ? palette.surface : Colors.transparent,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      boxShadow: r == selected ? palette.cardShadow : null,
                    ),
                    child: Text(
                      r.label,
                      textAlign: TextAlign.center,
                      style: AppText.label.copyWith(
                        color: r == selected
                            ? AppColors.primaryGreen
                            : palette.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AxisLabels extends StatelessWidget {
  const _AxisLabels(
      {required this.points, required this.range, required this.palette});

  final List<NetWorthPoint> points;
  final NetWorthRange range;
  final AppPalette palette;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _fmt(DateTime d) {
    switch (range) {
      case NetWorthRange.week:
      case NetWorthRange.month:
        return '${d.day} ${_months[d.month - 1]}';
      default:
        return '${_months[d.month - 1]} ${d.year % 100}';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(_fmt(points.first.date),
            style: AppText.label
                .copyWith(color: palette.textFaint, fontSize: 11)),
        Text(_fmt(points.last.date),
            style: AppText.label
                .copyWith(color: palette.textFaint, fontSize: 11)),
      ],
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.points,
    required this.progress,
    required this.selected,
    required this.line,
    required this.fillTop,
    required this.fillBottom,
    required this.grid,
    required this.dotBorder,
    required this.tooltipBg,
    required this.tooltipFg,
    required this.isDark,
  });

  final List<NetWorthPoint> points;
  final double progress;
  final int? selected;
  final Color line;
  final Color fillTop;
  final Color fillBottom;
  final Color grid;
  final Color dotBorder;
  final Color tooltipBg;
  final Color tooltipFg;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    final values = points.map((p) => p.value).toList();
    final minV = values.reduce((a, b) => a < b ? a : b);
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final range = (maxV - minV).abs() < 1 ? 1 : (maxV - minV);
    const topPad = 10.0;
    final chartH = size.height - topPad - 4;

    Offset at(int i) {
      final x = size.width * (i / (points.length - 1));
      final norm = (values[i] - minV) / range;
      final y = topPad + chartH * (1 - norm);
      return Offset(x, y);
    }

    // Horizontal grid lines.
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var g = 0; g <= 3; g++) {
      final y = topPad + chartH * (g / 3);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Build the full path, then reveal it by [progress].
    final full = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < points.length; i++) {
      final p0 = at(i - 1);
      final p1 = at(i);
      final midX = (p0.dx + p1.dx) / 2;
      full.cubicTo(midX, p0.dy, midX, p1.dy, p1.dx, p1.dy);
    }

    final revealWidth = size.width * progress;
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, revealWidth, size.height));

    // Gradient fill under the line.
    final fillPath = Path.from(full)
      ..lineTo(at(points.length - 1).dx, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [fillTop, fillBottom],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    // The line.
    canvas.drawPath(
      full,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.8
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();

    // Selected point → vertical guide, dot and tooltip.
    if (selected != null && selected! >= 0 && selected! < points.length) {
      final p = at(selected!);
      canvas.drawLine(
        Offset(p.dx, topPad),
        Offset(p.dx, size.height),
        Paint()
          ..color = line.withValues(alpha: 0.35)
          ..strokeWidth = 1.5,
      );
      canvas.drawCircle(p, 6, Paint()..color = line);
      canvas.drawCircle(
          p, 6, Paint()
        ..color = dotBorder
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5);
      _paintTooltip(canvas, size, p, points[selected!]);
    }
  }

  void _paintTooltip(Canvas canvas, Size size, Offset p, NetWorthPoint point) {
    final label = formatInr(point.value);
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
            color: tooltipFg, fontSize: 12, fontWeight: FontWeight.w800),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    const padH = 9.0;
    const padV = 6.0;
    final w = tp.width + padH * 2;
    final h = tp.height + padV * 2;
    var left = p.dx - w / 2;
    left = left.clamp(0.0, size.width - w);
    var top = p.dy - h - 12;
    if (top < 0) top = p.dy + 12;

    final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, w, h), const Radius.circular(8));
    canvas.drawRRect(rect, Paint()..color = tooltipBg);
    tp.paint(canvas, Offset(left + padH, top + padV));
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) =>
      old.progress != progress ||
      old.selected != selected ||
      old.points != points;
}
