import 'package:flutter/material.dart';

import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';

/// A shimmering gradient sweep applied to its child's shape — the base of every
/// skeleton loader. Wrap skeleton boxes in one [Shimmer] so they animate in sync.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});

  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final base = palette.surfaceVariant;
    final highlight = Color.alphaBlend(
        Colors.white.withValues(alpha: palette.isDark ? 0.06 : 0.5), base);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            final dx = bounds.width * (_c.value * 2 - 0.5);
            return LinearGradient(
              colors: [base, highlight, base],
              stops: const [0.35, 0.5, 0.65],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              transform: _SlideGradient(dx / bounds.width),
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _SlideGradient extends GradientTransform {
  const _SlideGradient(this.slide);
  final double slide;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * slide, 0, 0);
}

/// A single neutral placeholder block.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    required this.width,
    required this.height,
    this.radius = 8,
  });

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: palette.surfaceVariant,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// The full Home dashboard skeleton shown while the first load is in flight.
class DashboardSkeleton extends StatelessWidget {
  const DashboardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    Widget card(Widget child) => Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.internal),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(AppRadius.large),
            border: Border.all(color: palette.border),
          ),
          child: child,
        );

    return Shimmer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Net-worth hero.
          card(Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              SkeletonBox(width: 120, height: 12),
              SizedBox(height: 12),
              SkeletonBox(width: 180, height: 30),
              SizedBox(height: 14),
              SkeletonBox(width: double.infinity, height: 120, radius: 14),
            ],
          )),
          const SizedBox(height: AppSpacing.md),
          // Quick actions row.
          Row(
            children: [
              for (var i = 0; i < 4; i++) ...[
                if (i > 0) const SizedBox(width: AppSpacing.xs),
                const Expanded(
                  child: SkeletonBox(width: double.infinity, height: 84, radius: 16),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          // Activity list.
          card(Column(
            children: [
              for (var i = 0; i < 4; i++) ...[
                if (i > 0) const SizedBox(height: 16),
                Row(
                  children: const [
                    SkeletonBox(width: 44, height: 44, radius: 12),
                    SizedBox(width: 12),
                    Expanded(child: SkeletonBox(width: double.infinity, height: 14)),
                    SizedBox(width: 12),
                    SkeletonBox(width: 40, height: 10),
                  ],
                ),
              ],
            ],
          )),
        ],
      ),
    );
  }
}
