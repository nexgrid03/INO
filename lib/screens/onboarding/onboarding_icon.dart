import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/directional_reveal.dart';
import '../../widgets/soft_glow.dart';

/// The animated circular onboarding icon.
///
/// Visually identical at rest to the original 160px gradient circle with an
/// 80px white icon — the layout box stays 160px. On top of that it adds:
///   • a soft glow halo behind the circle (overflows the 160 box via
///     [OverflowBox] so it does NOT change layout/spacing),
///   • a per-screen reveal of the inner icon:
///       – Screen 0 (folder): a gentle pop/bounce,
///       – Screen 1 (chart):  a left→right "draw" wipe + a sparkle,
///       – Screen 2 (QR):     a top→bottom build wipe + a scanning line.
///
/// All motion is driven by externally-owned animations so a single controller
/// keeps every phase in sync (and there are no per-frame allocations here).
class AnimatedOnboardingIcon extends StatelessWidget {
  const AnimatedOnboardingIcon({
    super.key,
    required this.index,
    required this.icon,
    required this.glow,
    required this.reveal,
    required this.folderPop,
  });

  final int index;
  final IconData icon;

  /// One-shot glow pulse behind the circle.
  final Animation<double> glow;

  /// 0→1 reveal used by the chart wipe / QR build / scan line.
  final Animation<double> reveal;

  /// Bouncy 0.8→1.0 pop used by the folder icon.
  final Animation<double> folderPop;

  @override
  Widget build(BuildContext context) {
    // Keep the laid-out size at 160 so surrounding spacing is unchanged.
    return SizedBox(
      width: 160,
      height: 160,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // Glow halo — rendered larger than 160 via OverflowBox so it bleeds
          // beyond the circle without expanding the layout box.
          Center(
            child: OverflowBox(
              maxWidth: 230,
              maxHeight: 230,
              child: SoftGlow(animation: glow, size: 230),
            ),
          ),

          // The original gradient circle (unchanged).
          Container(
            width: 160,
            height: 160,
            decoration: const BoxDecoration(
              gradient: AppColors.brandGradient,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: SizedBox(
              width: 80,
              height: 80,
              child: _innerIcon(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _innerIcon() {
    final iconWidget = Icon(icon, size: 80, color: Colors.white);

    switch (index) {
      case 1:
        // Wealth chart: "draw" the icon left→right, then a sparkle twinkles.
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            DirectionalReveal(
              progress: reveal,
              axis: Axis.horizontal,
              child: iconWidget,
            ),
            Positioned(
              top: -2,
              right: -2,
              child: _Sparkle(progress: reveal),
            ),
          ],
        );

      case 2:
        // QR: build the blocks top→bottom while a scan line sweeps down.
        return Stack(
          alignment: Alignment.center,
          children: [
            DirectionalReveal(
              progress: reveal,
              axis: Axis.vertical,
              child: iconWidget,
            ),
            _ScanLine(progress: reveal, area: 80),
          ],
        );

      case 0:
      default:
        // Folder: a subtle bouncy pop.
        return ScaleTransition(scale: folderPop, child: iconWidget);
    }
  }
}

/// A small star that fades/scales in then out near the end of [progress] —
/// a refined "sparkle on completion" for the wealth chart.
class _Sparkle extends StatelessWidget {
  const _Sparkle({required this.progress});

  final Animation<double> progress;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: progress,
      builder: (context, _) {
        // Active only in the last stretch of the reveal (0.6 → 1.0).
        final double local = ((progress.value - 0.6) / 0.4).clamp(0.0, 1.0);
        // Rise then fall: a single gentle twinkle.
        final double opacity = math.sin(math.pi * local);
        final double scale = 0.7 + 0.3 * local;
        return Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: scale,
            child: const Icon(
              Icons.auto_awesome,
              size: 18,
              color: Colors.white,
            ),
          ),
        );
      },
    );
  }
}

/// A thin glowing line that sweeps top→bottom once as [progress] runs, then
/// fades out — the "scanning" effect over the QR code.
class _ScanLine extends StatelessWidget {
  const _ScanLine({required this.progress, required this.area});

  final Animation<double> progress;

  /// Height/width of the icon area the line travels across.
  final double area;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: progress,
      builder: (context, _) {
        final double t = progress.value.clamp(0.0, 1.0);
        // Fade the line out over the final 25% so it leaves cleanly.
        final double opacity = (1 - ((t - 0.75) / 0.25)).clamp(0.0, 1.0);
        return Positioned(
          top: t * area,
          child: Opacity(
            opacity: opacity,
            child: Container(
              width: area,
              height: 2.5,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                gradient: const LinearGradient(
                  colors: [
                    Colors.transparent,
                    Colors.white,
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
