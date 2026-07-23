import 'dart:io';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/image_enhancer.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/dashboard/fade_slide_in.dart';
import '../../widgets/pressable_scale.dart';
import 'document_crop_editor.dart';

/// The review screen deliberately commits to the premium DARK camera chrome
/// (matching the scanner viewport it follows) in both app themes, so the flow
/// reads as one continuous capture experience. All colours come from the
/// [AppPalette.dark] token set — never ad-hoc hex values.
const AppPalette _chrome = AppPalette.dark;

/// Screen 2 — review the capture.
///
/// Shows the captured page large inside a dark viewport with edge-detection
/// corner anchors, and offers the four standard adjustments
/// (Crop · Rotate · Enhance · Retake) in a floating control sheet before
/// committing to OCR. Deliberately minimal — a preview, a row of tools, and
/// one clear Continue.
class ScanReviewScreen extends StatefulWidget {
  const ScanReviewScreen({
    super.key,
    required this.imagePath,
    required this.onRetake,
    required this.onContinue,
    required this.onClose,
  });

  /// Path to the captured/imported page, or null (renders a placeholder).
  final String? imagePath;
  final VoidCallback onRetake;

  /// Called with the *edited* image path (crop / rotate / enhance baked in) so
  /// OCR and the saved document use exactly what the user sees.
  final ValueChanged<String?> onContinue;
  final VoidCallback onClose;

  @override
  State<ScanReviewScreen> createState() => _ScanReviewScreenState();
}

class _ScanReviewScreenState extends State<ScanReviewScreen> {
  /// The committed edited image (crop / rotate baked in). Starts as the capture.
  String? _workingPath;

  /// The enhanced variant of [_workingPath], shown while [_enhanced] is on.
  String? _enhancedPath;
  bool _enhanced = false;
  bool _enhancing = false;
  bool _processing = false; // crop/rotate baking in progress

  @override
  void initState() {
    super.initState();
    _workingPath = widget.imagePath;
  }

  /// The path currently shown and used for OCR: the enhanced variant when the
  /// toggle is on, otherwise the committed working image.
  String? get _effectivePath =>
      _enhanced ? (_enhancedPath ?? _workingPath) : _workingPath;

  /// Opens the 4-corner crop editor and commits the perspective-corrected result.
  Future<void> _openCrop() async {
    final base = _effectivePath;
    if (base == null || !File(base).existsSync()) {
      _toast(AppLocalizations.of(context).t('addCaptureBeforeCrop'));
      return;
    }
    final cropped = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => DocumentCropEditor(imagePath: base)),
    );
    if (cropped == null || !mounted) return;
    setState(() {
      _workingPath = cropped;
      _enhanced = false; // enhance is now baked into history
      _enhancedPath = null;
    });
    _toast(AppLocalizations.of(context).t('cropApplied'));
  }

  /// Bakes a real 90° rotation into the working image.
  Future<void> _rotate() async {
    final base = _effectivePath;
    if (base == null || !File(base).existsSync()) return;
    setState(() => _processing = true);
    final rotated = await ImageEnhancer.rotate90(base);
    if (!mounted) return;
    setState(() {
      _workingPath = rotated;
      _enhanced = false;
      _enhancedPath = null;
      _processing = false;
    });
  }

  Future<void> _toggleEnhance() async {
    if (_enhanced) {
      setState(() => _enhanced = false);
      return;
    }
    final base = _workingPath;
    if (base == null) {
      setState(() => _enhanced = true); // placeholder mode (no real file)
      return;
    }
    setState(() => _enhancing = true);
    final result = await ImageEnhancer.enhance(base);
    if (!mounted) return;
    setState(() {
      _enhancedPath = result;
      _enhanced = true;
      _enhancing = false;
    });
  }

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
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: _chrome.bg,
      body: SafeArea(
        // The control sheet bleeds to the physical bottom edge (it carries its
        // own bottom SafeArea), matching the Stitch capture chrome.
        bottom: false,
        child: Column(
          children: [
            FadeSlideIn(child: _Header(onBack: widget.onClose)),
            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
                child: Center(
                  child: FadeSlideIn(
                    delay: const Duration(milliseconds: 60),
                    child: _CapturePreview(
                      imagePath: _effectivePath,
                      enhanced: _enhanced,
                      enhancing: _enhancing || _processing,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            // Floating control sheet: adjustment tools + the Continue action.
            FadeSlideIn(
              delay: const Duration(milliseconds: 120),
              child: _ControlSheet(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _Tool(
                        icon: Icons.crop_rounded,
                        label: l10n.t('crop'),
                        onTap: _openCrop,
                      ),
                      _Tool(
                        icon: Icons.rotate_90_degrees_cw_rounded,
                        label: l10n.t('rotate'),
                        onTap: _rotate,
                      ),
                      _Tool(
                        icon: Icons.auto_fix_high_rounded,
                        label: l10n.t('enhance'),
                        active: _enhanced,
                        onTap: _toggleEnhance,
                      ),
                      _Tool(
                        icon: Icons.refresh_rounded,
                        label: l10n.t('retake'),
                        onTap: widget.onRetake,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _ContinueButton(
                      onContinue: () => widget.onContinue(_effectivePath)),
                ],
              ),
            ),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xs),
      child: Row(
        children: [
          // Glass circular back control (Stitch scanner chrome).
          PressableScale(
            pressedScale: 0.9,
            child: Material(
              color: _chrome.surface,
              shape: CircleBorder(side: BorderSide(color: _chrome.border)),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onBack,
                child: SizedBox(
                  width: AppSizes.iconContainerSm,
                  height: AppSizes.iconContainerSm,
                  child: Icon(Icons.arrow_back_rounded,
                      size: 21, color: _chrome.textPrimary),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(AppLocalizations.of(context).t('reviewCapture'),
                    style: AppText.headline
                        .copyWith(color: _chrome.textPrimary, fontSize: 21)),
                const SizedBox(height: 2),
                Text(AppLocalizations.of(context).t('reviewCaptureSubtitle'),
                    style: AppText.caption
                        .copyWith(color: _chrome.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The captured page preview inside the dark viewport. Renders the real
/// captured/imported image when a path is available, otherwise a styled
/// placeholder (no-path / test contexts). Four glowing corner anchors echo the
/// scanner's edge-detection language.
class _CapturePreview extends StatelessWidget {
  const _CapturePreview({
    required this.imagePath,
    required this.enhanced,
    required this.enhancing,
  });

  final String? imagePath;
  final bool enhanced;
  final bool enhancing;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 0.7,
      child: Stack(
        clipBehavior: Clip.none,
        fit: StackFit.expand,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F2F0),
              borderRadius: BorderRadius.circular(AppRadius.large),
              border: Border.all(
                color: AppColors.primaryGreen
                    .withValues(alpha: enhanced ? 0.7 : 0.35),
                width: enhanced ? 2 : 1.4,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 28,
                  offset: const Offset(0, 14),
                ),
                // Teal ambient halo lifting the page off the dark viewport.
                BoxShadow(
                  color: _chrome.ambient.withValues(alpha: 0.10),
                  blurRadius: 34,
                  spreadRadius: -2,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (imagePath != null)
                  Image.file(
                    File(imagePath!),
                    key: ValueKey(imagePath),
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const _PlaceholderPage(),
                  )
                else
                  const _PlaceholderPage(),
                if (enhancing)
                  ColoredBox(
                    color: Colors.black.withValues(alpha: 0.25),
                    child: const Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(
                            AppColors.primaryGreen),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Edge-detection corner anchors (Stitch scanner pins).
          const Positioned(top: -5, left: -5, child: _CornerPin()),
          const Positioned(top: -5, right: -5, child: _CornerPin()),
          const Positioned(bottom: -5, left: -5, child: _CornerPin()),
          const Positioned(bottom: -5, right: -5, child: _CornerPin()),
        ],
      ),
    );
  }
}

/// A small glowing anchor dot marking a detected page corner.
class _CornerPin extends StatelessWidget {
  const _CornerPin();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: AppColors.primaryGreen,
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.9),
          width: 1.5,
        ),
        boxShadow: AppShadows.glow(AppColors.primaryGreen, opacity: 0.5),
      ),
    );
  }
}

/// Styled document silhouette used when no real image is available.
class _PlaceholderPage extends StatelessWidget {
  const _PlaceholderPage();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.badge_rounded,
              size: 40, color: AppColors.primaryGreen.withValues(alpha: 0.5)),
          const SizedBox(height: 20),
          for (var i = 0; i < 6; i++)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              width: (i.isEven ? 1.0 : 0.6) * 180,
              height: 9,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
        ],
      ),
    );
  }
}

/// The dark rounded-top control sheet hosting the tools and the CTA — the
/// Stitch "preview & filter" panel, translated to the teal system.
class _ControlSheet extends StatelessWidget {
  const _ControlSheet({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _chrome.bgElevated,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(AppRadius.large)),
        border: Border.all(color: _chrome.border),
        boxShadow: _chrome.cardShadow,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.sm,
              AppSpacing.screen, AppSpacing.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Sheet grabber accent.
              Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: _chrome.border,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              ...children,
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
    final color = active ? AppColors.primaryGreen : _chrome.textPrimary;
    return PressableScale(
      pressedScale: 0.9,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Circular glass control (Stitch capture chrome).
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: active
                    ? AppColors.primaryGreen.withValues(alpha: 0.16)
                    : _chrome.surfaceVariant,
                shape: BoxShape.circle,
                border: Border.all(
                  color: active ? AppColors.primaryGreen : _chrome.border,
                ),
                boxShadow: active
                    ? AppShadows.glow(AppColors.primaryGreen, opacity: 0.25)
                    : null,
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 7),
            Text(label,
                style: AppText.caption.copyWith(
                    color: _chrome.textSecondary,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _ContinueButton extends StatelessWidget {
  const _ContinueButton({required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: Container(
        height: AppSizes.button,
        decoration: BoxDecoration(
          gradient: AppGradients.primary,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          boxShadow:
              AppShadows.glow(AppColors.primaryGreen, opacity: 0.32),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onContinue,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(AppLocalizations.of(context).t('extractText'),
                      style: AppText.subtitle.copyWith(
                          color: Colors.white, fontWeight: FontWeight.w700)),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward_rounded,
                      color: Colors.white, size: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
