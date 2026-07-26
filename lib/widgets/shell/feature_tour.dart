import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';

/// One stop in the first-run feature tour.
class TourStep {
  const TourStep({
    required this.title,
    required this.body,
    required this.target,
    this.radius = 34,
  });

  final String title;
  final String body;

  /// Resolved lazily each frame so the spotlight lands on wherever the target
  /// actually is (e.g. the voice button found via its GlobalKey).
  final Offset Function() target;

  /// Spotlight radius around the target's centre.
  final double radius;
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
  Offset? _fromCenter;
  double _fromRadius = 34;

  TourStep get _step => widget.steps[_i];

  void _next() {
    HapticFeedback.selectionClick();
    if (_i == widget.steps.length - 1) {
      widget.onFinish();
      return;
    }
    setState(() {
      _fromCenter = _step.target();
      _fromRadius = _step.radius;
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
    final target = _step.target();

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
              final center = Offset.lerp(_fromCenter ?? target, target, t)!;
              final radius = _fromRadius + (_step.radius - _fromRadius) * t;
              // Card fades in during the tail of the slide so it never trails the
              // moving hole.
              final cardT = ((t - 0.35) / 0.65).clamp(0.0, 1.0);

              // Place the card above or below the spotlight, whichever has room.
              final below = center.dy < size.height * 0.55;
              final cardTop = below ? center.dy + radius + 22 : null;
              final cardBottom = below
                  ? null
                  : size.height - (center.dy - radius) + 22;

              return Stack(
                children: [
                  // Scrim with the punched spotlight. Tapping anywhere advances.
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _next,
                      child: CustomPaint(
                        painter: _SpotlightPainter(
                          center: center,
                          radius: radius,
                        ),
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
                                borderRadius: BorderRadius.circular(22),
                                border: Border.all(color: palette.border),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.25),
                                    blurRadius: 24,
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
  _SpotlightPainter({required this.center, required this.radius});

  final Offset center;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final hole = Path()
      ..addOval(Rect.fromCircle(center: center, radius: radius));
    final scrim = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      hole,
    );
    canvas.drawPath(
      scrim,
      Paint()..color = Colors.black.withValues(alpha: 0.62),
    );

    // Brand ring + soft outer glow around the hole.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..shader = const SweepGradient(
          colors: [
            AppColors.primaryGreen,
            Color(0xFF7FD3D8),
            AppColors.primaryGreen,
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
    canvas.drawCircle(
      center,
      radius + 3,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(6, radius * 0.16)
        ..color = AppColors.secondaryGreen.withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) =>
      old.center != center || old.radius != radius;
}
