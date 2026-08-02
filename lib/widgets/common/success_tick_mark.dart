import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Animated success tick matching the Figma share/upload confirmation:
/// concentric soft rings that pulse outward around a brand-green check circle.
///
/// Plays once on mount (scale-pop + ring expand). Use inside overlays or full
/// success screens.
class SuccessTickMark extends StatefulWidget {
  const SuccessTickMark({
    super.key,
    this.size = 96,
    this.autoPlay = true,
  });

  /// Diameter of the solid check circle.
  final double size;

  /// When false, stays at the end pose (for tests / static previews).
  final bool autoPlay;

  @override
  State<SuccessTickMark> createState() => _SuccessTickMarkState();
}

class _SuccessTickMarkState extends State<SuccessTickMark>
    with TickerProviderStateMixin {
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 720),
  );
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(begin: 0.55, end: 1.08)
          .chain(CurveTween(curve: Curves.easeOutBack)),
      weight: 70,
    ),
    TweenSequenceItem(
      tween: Tween(begin: 1.08, end: 1.0)
          .chain(CurveTween(curve: Curves.easeOutCubic)),
      weight: 30,
    ),
  ]).animate(_pop);

  late final Animation<double> _checkOpacity = CurvedAnimation(
    parent: _pop,
    curve: const Interval(0.25, 0.75, curve: Curves.easeOut),
  );

  @override
  void initState() {
    super.initState();
    if (widget.autoPlay) {
      _pop.forward();
      _pulse.repeat();
    } else {
      _pop.value = 1;
      _pulse.value = 0.35;
    }
  }

  @override
  void dispose() {
    _pop.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    // Outer canvas for the expanding rings.
    final canvas = size * 2.4;

    return SizedBox(
      width: canvas,
      height: canvas,
      child: AnimatedBuilder(
        animation: Listenable.merge([_pop, _pulse]),
        builder: (context, _) {
          return Stack(
            alignment: Alignment.center,
            children: [
              _PulseRing(
                progress: _pulse.value,
                delay: 0.0,
                baseSize: size,
              ),
              _PulseRing(
                progress: _pulse.value,
                delay: 0.45,
                baseSize: size,
              ),
              // Soft static halo behind the solid disc.
              Container(
                width: size * 1.55,
                height: size * 1.55,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primaryGreen.withValues(alpha: 0.10),
                ),
              ),
              Transform.scale(
                scale: _scale.value,
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppColors.brandGradient,
                    boxShadow: [
                      BoxShadow(
                        color:
                            AppColors.primaryGreen.withValues(alpha: 0.38),
                        blurRadius: 28,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Opacity(
                    opacity: _checkOpacity.value,
                    child: Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: size * 0.48,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PulseRing extends StatelessWidget {
  const _PulseRing({
    required this.progress,
    required this.delay,
    required this.baseSize,
  });

  final double progress;
  final double delay;
  final double baseSize;

  @override
  Widget build(BuildContext context) {
    // Stagger each ring so they don't expand in lockstep.
    var t = (progress - delay) % 1.0;
    if (t < 0) t += 1.0;
    final scale = 1.0 + (t * 1.15);
    final opacity = (1.0 - t).clamp(0.0, 1.0) * 0.35;

    return Transform.scale(
      scale: scale,
      child: Container(
        width: baseSize * 1.35,
        height: baseSize * 1.35,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: AppColors.primaryGreen.withValues(alpha: opacity),
            width: 2.5,
          ),
          color: AppColors.primaryGreen.withValues(alpha: opacity * 0.25),
        ),
      ),
    );
  }
}
