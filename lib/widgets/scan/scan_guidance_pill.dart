import 'package:flutter/material.dart';

import '../../models/scan_models.dart';
import '../../theme/app_theme.dart';

/// The floating real-time hint shown over the camera ("Hold steady",
/// "Document detected" …). A single calm pill that tints green once the scanner
/// has locked on, so the user always knows whether they can capture.
class ScanGuidancePill extends StatelessWidget {
  const ScanGuidancePill({super.key, required this.guidance});

  final ScanGuidance guidance;

  @override
  Widget build(BuildContext context) {
    final positive = guidance.isPositive;
    final accent = positive ? AppColors.primaryGreen : Colors.white;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.3),
            end: Offset.zero,
          ).animate(anim),
          child: child,
        ),
      ),
      child: Container(
        key: ValueKey(guidance),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: positive
              ? AppColors.primaryGreen.withValues(alpha: 0.18)
              : Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: positive
                ? AppColors.primaryGreen
                : Colors.white.withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(guidance.icon, size: 17, color: accent),
            const SizedBox(width: 8),
            Text(
              guidance.message,
              style: TextStyle(
                color: accent,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
