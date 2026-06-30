import 'package:flutter/material.dart';

import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/pressable_scale.dart';

/// Screen 2 — review the capture.
///
/// Shows the captured page large and offers the four standard adjustments
/// (Crop · Rotate · Enhance · Retake) before committing to OCR. Deliberately
/// minimal — a preview, a row of tools, and one clear Continue.
class ScanReviewScreen extends StatefulWidget {
  const ScanReviewScreen({
    super.key,
    required this.onRetake,
    required this.onContinue,
    required this.onClose,
  });

  final VoidCallback onRetake;
  final VoidCallback onContinue;
  final VoidCallback onClose;

  @override
  State<ScanReviewScreen> createState() => _ScanReviewScreenState();
}

class _ScanReviewScreenState extends State<ScanReviewScreen> {
  // Cosmetic-only adjustments so the tools feel responsive in the prototype.
  int _quarterTurns = 0;
  bool _enhanced = false;

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.primaryGreen,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: Column(
          children: [
            _Header(onBack: widget.onClose),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.screen),
                child: Center(
                  child: AnimatedRotation(
                    turns: _quarterTurns / 4,
                    duration: const Duration(milliseconds: 250),
                    child: _CapturePreview(enhanced: _enhanced),
                  ),
                ),
              ),
            ),
            // Adjustment tools.
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screen, vertical: AppSpacing.md),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _Tool(
                    icon: Icons.crop_rounded,
                    label: 'Crop',
                    onTap: () => _toast('Crop — drag the handles'),
                  ),
                  _Tool(
                    icon: Icons.rotate_90_degrees_cw_rounded,
                    label: 'Rotate',
                    onTap: () =>
                        setState(() => _quarterTurns = (_quarterTurns + 1) % 4),
                  ),
                  _Tool(
                    icon: Icons.auto_fix_high_rounded,
                    label: 'Enhance',
                    active: _enhanced,
                    onTap: () => setState(() => _enhanced = !_enhanced),
                  ),
                  _Tool(
                    icon: Icons.refresh_rounded,
                    label: 'Retake',
                    onTap: widget.onRetake,
                  ),
                ],
              ),
            ),
            _ContinueBar(onContinue: widget.onContinue),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xs),
      child: Row(
        children: [
          PressableScale(
            pressedScale: 0.9,
            child: Material(
              color: palette.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.chip),
                side: BorderSide(color: palette.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onBack,
                child: SizedBox(
                  width: AppSizes.iconContainerSm,
                  height: AppSizes.iconContainerSm,
                  child: Icon(Icons.arrow_back_rounded,
                      size: 21, color: palette.textPrimary),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Review Capture',
                    style: AppText.headline
                        .copyWith(color: palette.textPrimary, fontSize: 21)),
                const SizedBox(height: 2),
                Text('Crop, rotate or enhance before extracting',
                    style:
                        AppText.caption.copyWith(color: palette.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The captured page preview (a styled placeholder standing in for the real
/// captured image).
class _CapturePreview extends StatelessWidget {
  const _CapturePreview({required this.enhanced});

  final bool enhanced;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 0.7,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        decoration: BoxDecoration(
          color: enhanced ? Colors.white : const Color(0xFFF1F2F0),
          borderRadius: BorderRadius.circular(AppRadius.large),
          border: Border.all(
            color: AppColors.primaryGreen.withValues(alpha: enhanced ? 0.5 : 0.2),
            width: enhanced ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 28,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.badge_rounded,
                  size: 40,
                  color: AppColors.primaryGreen
                      .withValues(alpha: enhanced ? 0.9 : 0.5)),
              const SizedBox(height: 20),
              for (var i = 0; i < 6; i++)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  width: (i.isEven ? 1.0 : 0.6) * 180,
                  height: 9,
                  decoration: BoxDecoration(
                    color: Colors.black
                        .withValues(alpha: enhanced ? 0.30 : 0.16),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tool extends StatelessWidget {
  const _Tool({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final color = active ? AppColors.primaryGreen : palette.textPrimary;
    return PressableScale(
      pressedScale: 0.9,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: active
                    ? AppColors.primaryGreen.withValues(alpha: 0.12)
                    : palette.surface,
                borderRadius: BorderRadius.circular(AppRadius.chip),
                border: Border.all(
                  color: active ? AppColors.primaryGreen : palette.border,
                ),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 7),
            Text(label,
                style: AppText.caption.copyWith(
                    color: palette.textSecondary, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _ContinueBar extends StatelessWidget {
  const _ContinueBar({required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        color: palette.bg,
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.sm,
              AppSpacing.screen, AppSpacing.sm),
          child: PressableScale(
            child: Container(
              height: AppSizes.button,
              decoration: BoxDecoration(
                gradient: AppColors.brandGradient,
                borderRadius: BorderRadius.circular(AppRadius.button),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryGreen.withValues(alpha: 0.32),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onContinue,
                  borderRadius: BorderRadius.circular(AppRadius.button),
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Extract Text',
                            style: AppText.subtitle.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward_rounded,
                            color: Colors.white, size: 20),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
