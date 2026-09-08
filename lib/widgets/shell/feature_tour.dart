import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';

/// One stop in the first-run feature tour.
class TourStep {
  const TourStep({
    this.name = 'TargetWidget',
    required this.title,
    required this.body,
    required this.target,
    this.padding = 8,
  });

  final String name;
  final String title;
  final String body;

  /// The target's bounds in screen coordinates, resolved lazily each frame so
  /// the spotlight lands on wherever the widget actually is (e.g. the voice
  /// tile found via its GlobalKey).
  ///
  /// Bounds - not a bare centre - because the spotlight is sized from them.
  /// A quick-action tile is a disc *plus* its caption and a nav tab is an icon
  /// *plus* its label, so a circle of guessed radius dropped on the tile's
  /// centre sits low and clips the very thing it is pointing at.
  final Rect Function() target;

  /// Breathing room between the target's bounds and the spotlight's edge.
  final double padding;

  /// The spotlight hole for this step: the target's bounds, padded, rounded so
  /// the shape suits what it is pointing at without ever cutting into it.
  ///
  /// A square target - a FAB, an icon button - is a disc in practice, so it
  /// gets a true circle. The tolerance is deliberately tight: a quick-action
  /// tile is 78x89, near enough to square to slip through a loose one, and
  /// circling it clips the caption's ends. Anything else gets a
  /// rounded rect whose corners are provably clear of the target's own: a
  /// target corner sits `r - padding` in from the corner arc's centre on both
  /// axes, so it stays inside while `(r - padding)·√2 ≤ r`, i.e.
  /// `r ≤ padding·√2/(√2−1)`.
  RRect hole() {
    final bounds = target();
    final rect = bounds.inflate(padding);
    // Squareness is judged on the widget itself, not on the padded box - the
    // padding would otherwise nudge a 64x68 tile over the line.
    if ((bounds.width - bounds.height).abs() <= bounds.shortestSide * 0.05) {
      final r = rect.longestSide / 2;
      return RRect.fromRectAndRadius(
        Rect.fromCircle(center: rect.center, radius: r),
        Radius.circular(r),
      );
    }
    // The containment bound above allows up to padding*sqrt2/(sqrt2-1) ~= 3.4x
    // padding; 2.5x keeps a comfortable margin off that ceiling while still
    // reading as a properly rounded frame.
    return RRect.fromRectAndRadius(
      rect,
      Radius.circular(math.min(rect.shortestSide / 2, padding * 2.5)),
    );
  }
}

/// The one-time, step-by-step coach-mark overlay shown the first time the user
/// lands in the app: a dimmed scrim with a spotlight punched over each nav
/// destination (and finally the voice assistant), a one-line explanation, and
/// Skip / Next controls. Deliberately terse - one short line per stop.
///
/// Rendered as a plain widget stacked ABOVE the shell's [Scaffold] so it also
/// covers the bottom navigation bar. Every position is resolved in screen
/// coordinates.
class FeatureTour extends StatefulWidget {
  const FeatureTour({super.key, required this.steps, required this.onFinish});

  final List<TourStep> steps;
  final VoidCallback onFinish;

  @override
  State<FeatureTour> createState() => _FeatureTourState();
}

class _FeatureTourState extends State<FeatureTour> {
  int _i = 0;

  // Where the spotlight is animating FROM (the previous step's hole).
  RRect? _fromHole;

  TourStep get _step => widget.steps[_i];

  void _next() {
    HapticFeedback.selectionClick();
    if (_i == widget.steps.length - 1) {
      widget.onFinish();
      return;
    }
    setState(() {
      _fromHole = _step.hole();
      _i++;
    });
  }

  void _skip() {
    HapticFeedback.lightImpact();
    widget.onFinish();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final isLast = _i == widget.steps.length - 1;
    final target = _step.hole();

    assert(() {
      // Once per step, not once per animation frame - this used to spam the
      // log ~60x a second for the whole tour.
      debugPrint('[Tutorial] Step=$_i Target=${_step.name} '
          'Hole=${target.outerRect}');
      return true;
    }());

    // The overlay fills the shell, so its own constraints - not MediaQuery -
    // are the truthful screen size (MediaQuery lies under test surfaces).
    //
    // Wrapped in a transparent Material because the tour sits ABOVE the
    // Scaffold - without a Material ancestor every Text here would render
    // with Flutter's debug yellow underline (same trap the scan menu hit).
    return Material(
      type: MaterialType.transparency,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;

          // Re-runs 0→1 on every step change (keyed), sliding the spotlight from
          // the previous hole to the new one while the card fades back in.
          return TweenAnimationBuilder<double>(
            key: ValueKey(_i),
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 340),
            curve: Curves.easeOutCubic,
            builder: (context, t, _) {
              final hole = RRect.lerp(_fromHole ?? target, target, t)!;

              // Card fades in during the tail of the slide so it never trails the
              // moving hole.
              final cardT = ((t - 0.35) / 0.65).clamp(0.0, 1.0);

              // Place the card above or below the spotlight, whichever has room,
              // measured from the hole's real edges rather than a nominal radius.
              final bounds = hole.outerRect;
              final below = bounds.center.dy < size.height * 0.55;
              final cardTop = below ? bounds.bottom + 22 : null;
              final cardBottom = below ? null : size.height - bounds.top + 22;

              return Stack(
                children: [
                  // Scrim with the punched spotlight. Tapping anywhere advances.
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _next,
                      child: CustomPaint(
                        painter: _SpotlightPainter(hole: hole),
                      ),
                    ),
                  ),

                  // The step card.
                  Positioned(
                    left: 26,
                    right: 26,
                    top: cardTop,
                    bottom: cardBottom,
                    child: Opacity(
                      opacity: cardT,
                      child: Transform.translate(
                        offset: Offset(0, (below ? 10 : -10) * (1 - cardT)),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                18,
                                20,
                                12,
                              ),
                              decoration: BoxDecoration(
                                color: palette.bgElevated,
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(color: palette.border),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.20),
                                    blurRadius: 26,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _step.title,
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.3,
                                      color: palette.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _step.body,
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      height: 1.4,
                                      fontWeight: FontWeight.w500,
                                      color: palette.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      // Step dots.
                                      for (
                                        var d = 0;
                                        d < widget.steps.length;
                                        d++
                                      )
                                        Container(
                                          width: d == _i ? 16 : 6,
                                          height: 6,
                                          margin: const EdgeInsets.only(
                                            right: 5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: d == _i
                                                ? AppColors.primaryGreen
                                                : palette.textFaint.withValues(
                                                    alpha: 0.4,
                                                  ),
                                            borderRadius: BorderRadius.circular(
                                              3,
                                            ),
                                          ),
                                        ),
                                      const Spacer(),
                                      TextButton(
                                        onPressed: _skip,
                                        style: TextButton.styleFrom(
                                          foregroundColor: palette.textFaint,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                          ),
                                        ),
                                        child: Text(
                                          AppLocalizations.of(context).t('skip'),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      FilledButton(
                                        onPressed: _next,
                                        style: FilledButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 18,
                                            vertical: 10,
                                          ),
                                          minimumSize: const Size(0, 38),
                                          shape: const StadiumBorder(),
                                        ),
                                        child: Text(
                                          AppLocalizations.of(context)
                                              .t(isLast ? 'done' : 'next'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

/// Dim everything except a soft-edged circular hole over the target, ringed by
/// a bright brand stroke so the eye lands exactly where the step points.
class _SpotlightPainter extends CustomPainter {
  _SpotlightPainter({required this.hole});

  /// The cut-out, already sized to the target's bounds. A square target rounds
  /// all the way to a circle; a wide nav tab becomes a stadium.
  final RRect hole;

  @override
  void paint(Canvas canvas, Size size) {
    final scrim = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addRRect(hole),
    );
    canvas.drawPath(
      scrim,
      Paint()..color = Colors.black.withValues(alpha: 0.62),
    );

    final bounds = hole.outerRect;

    // Brand ring + soft outer glow around the hole.
    canvas.drawRRect(
      hole,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..shader = SweepGradient(
          colors: [
            AppColors.primaryGreen,
            Color(0xFF7DD3FC),
            AppColors.primaryGreen,
          ],
        ).createShader(bounds),
    );
    canvas.drawRRect(
      hole.inflate(3),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth =
            math.max(6, math.min(bounds.width, bounds.height) * 0.16)
        ..color = AppColors.secondaryGreen.withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) => old.hole != hole;
}
