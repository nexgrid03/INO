import 'package:flutter/material.dart';

import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../dashboard/ino_card.dart';

/// Loading placeholder for the document list — a gently pulsing stack of
/// skeleton tiles shown while the wallet loads, instead of a bare spinner. The
/// silhouette mirrors a real [DocumentCard] (icon chip · two text lines ·
/// trailing dot) so the transition to live content feels seamless.
class DocumentSkeleton extends StatefulWidget {
  const DocumentSkeleton({super.key, this.count = 5});

  final int count;

  @override
  State<DocumentSkeleton> createState() => _DocumentSkeletonState();
}

class _DocumentSkeletonState extends State<DocumentSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        // 0.45 → 1.0 opacity breathing.
        final t = 0.45 + (_c.value * 0.55);
        return Column(
          children: [
            for (var i = 0; i < widget.count; i++)
              Padding(
                padding: EdgeInsets.only(bottom: i == widget.count - 1 ? 0 : 10),
                child: Opacity(opacity: t, child: const _SkeletonTile()),
              ),
          ],
        );
      },
    );
  }
}

class _SkeletonTile extends StatelessWidget {
  const _SkeletonTile();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final block = palette.surfaceVariant;
    return InoCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          _Box(width: 46, height: 46, radius: 13, color: block),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Box(width: 150, height: 13, radius: 6, color: block),
                const SizedBox(height: 8),
                _Box(width: 100, height: 11, radius: 6, color: block),
                const SizedBox(height: 9),
                _Box(width: 64, height: 16, radius: 7, color: block),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _Box(width: 18, height: 18, radius: 9, color: block),
        ],
      ),
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({
    required this.width,
    required this.height,
    required this.radius,
    required this.color,
  });

  final double width;
  final double height;
  final double radius;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// A skeleton stand-in for the summary card, matching its ≈150dp footprint.
class SummarySkeleton extends StatelessWidget {
  const SummarySkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final block = palette.surfaceVariant;
    return InoCard(
      radius: AppRadius.large,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < 3; i++)
                _Box(width: 56, height: 38, radius: 10, color: block),
            ],
          ),
          const SizedBox(height: 18),
          _Box(width: double.infinity, height: 1, radius: 0, color: block),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _Box(width: 110, height: 14, radius: 6, color: block),
              _Box(width: 96, height: 34, radius: 12, color: block),
            ],
          ),
        ],
      ),
    );
  }
}
