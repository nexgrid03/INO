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
/// [AppPalette.dark] token set - never ad-hoc hex values.
const AppPalette _chrome = AppPalette.dark;

/// Screen 2 - review the capture.
///
/// Shows the captured page(s) large inside a dark viewport and offers the
/// standard adjustments before committing to OCR:
///
///  • **copy modes** - Original · Enhanced · B&W · Grayscale, the WhatsApp /
///    Adobe Scan filter set, rendered by the shared document-grade pipeline
///    ([ImageEnhancer.applyColorMode], Bradley–Roth adaptive B&W);
///  • **Crop / Rotate / Retake** tools (single-page captures; multi-page scans
///    arrive pre-cropped + perspective-corrected by the ML Kit scanner, whose
///    own UI already offered per-page adjustment).
///
/// Multi-page scans render as a swipeable page carousel with a page badge; the
/// selected copy mode applies to EVERY page on Continue.
class ScanReviewScreen extends StatefulWidget {
  const ScanReviewScreen({
    super.key,
    required this.imagePath,
    this.pages,
    required this.onRetake,
    required this.onContinue,
    this.onContinueAll,
    required this.onClose,
  });

  /// Path to the captured/imported page, or null (renders a placeholder).
  /// Ignored when [pages] holds more than one page.
  final String? imagePath;

  /// All scanned pages (ML Kit multi-page path). When it has 2+ entries the
  /// review runs in multi-page mode: carousel preview, geometry tools hidden,
  /// [onContinueAll] invoked with every processed page.
  final List<String>? pages;

  final VoidCallback onRetake;

  /// Called with the *edited* image path (crop / rotate / copy mode baked in)
  /// so OCR and the saved document use exactly what the user sees.
  final ValueChanged<String?> onContinue;

  /// Multi-page continue: every page with the selected copy mode applied, in
  /// scan order. Required when [pages] has 2+ entries.
  final ValueChanged<List<String>>? onContinueAll;

  final VoidCallback onClose;

  @override
  State<ScanReviewScreen> createState() => _ScanReviewScreenState();
}

class _ScanReviewScreenState extends State<ScanReviewScreen> {
  /// The committed edited image in single-page mode (crop / rotate baked in).
  String? _workingPath;

  /// Multi-page sources (geometry final - ML Kit already cropped/rectified).
  late final List<String> _pages =
      (widget.pages != null && widget.pages!.isNotEmpty)
          ? List<String>.from(widget.pages!)
          : [if (widget.imagePath != null) widget.imagePath!];

  bool get _isMulti => _pages.length > 1;

  int _previewIndex = 0;
  final PageController _pageController = PageController();

  /// The selected copy mode, applied to the preview live and to every page on
  /// Continue.
  ScanColorMode _mode = ScanColorMode.original;

  /// Rendered variants, keyed `'<sourcePath>|<mode>'` so switching modes (or
  /// pages) back and forth never recomputes.
  final Map<String, String> _modeCache = {};

  bool _busy = false; // mode render / crop / rotate / continue in progress

  @override
  void initState() {
    super.initState();
    _workingPath = widget.imagePath ?? (_pages.isNotEmpty ? _pages.first : null);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  String? _sourceAt(int index) {
    if (_isMulti) return index < _pages.length ? _pages[index] : null;
    return _workingPath;
  }

  /// The path shown for [index] right now: the mode-rendered variant when
  /// available, else the source (render may still be in flight).
  String? _shownAt(int index) {
    final src = _sourceAt(index);
    if (src == null || _mode == ScanColorMode.original) return src;
    return _modeCache['$src|${_mode.name}'] ?? src;
  }

  /// The single-page path OCR + save should use.
  String? get _effectivePath => _shownAt(_previewIndex);

  /// Renders [mode] for the page at [index] (cached).
  Future<void> _renderMode(int index, ScanColorMode mode) async {
    final src = _sourceAt(index);
    if (src == null || mode == ScanColorMode.original) return;
    final key = '$src|${mode.name}';
    if (_modeCache.containsKey(key)) return;
    final out = await ImageEnhancer.applyColorMode(src, mode);
    _modeCache[key] = out;
  }

  Future<void> _selectMode(ScanColorMode mode) async {
    if (_busy || mode == _mode) return;
    setState(() {
      _mode = mode;
      _busy = mode != ScanColorMode.original;
    });
    if (mode != ScanColorMode.original) {
      await _renderMode(_previewIndex, mode);
    }
    if (mounted) setState(() => _busy = false);
  }

  /// Swiping to a page renders the current mode for it on demand.
  Future<void> _onPageChanged(int index) async {
    setState(() => _previewIndex = index);
    if (_mode == ScanColorMode.original) return;
    setState(() => _busy = true);
    await _renderMode(index, _mode);
    if (mounted) setState(() => _busy = false);
  }

  /// Opens the 4-corner crop editor and commits the perspective-corrected
  /// result (single-page mode only - ML Kit pages are already rectified).
  Future<void> _openCrop() async {
    final base = _workingPath;
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
      _pages[0] = cropped;
      _modeCache.clear(); // geometry changed → mode variants are stale
    });
    if (_mode != ScanColorMode.original) {
      setState(() => _busy = true);
      await _renderMode(0, _mode);
      if (mounted) setState(() => _busy = false);
    }
    if (mounted) _toast(AppLocalizations.of(context).t('cropApplied'));
  }

  /// Bakes a real 90° rotation into the working image (single-page mode).
  Future<void> _rotate() async {
    final base = _workingPath;
    if (base == null || !File(base).existsSync()) return;
    setState(() => _busy = true);
    final rotated = await ImageEnhancer.rotate90(base);
    if (!mounted) return;
    setState(() {
      _workingPath = rotated;
      _pages[0] = rotated;
      _modeCache.clear();
    });
    if (_mode != ScanColorMode.original) await _renderMode(0, _mode);
    if (mounted) setState(() => _busy = false);
  }

  /// Continue: single-page hands the effective path on; multi-page renders the
  /// selected mode for EVERY page first, then hands the whole set on.
  Future<void> _continue() async {
    if (_busy) return;
    if (!_isMulti) {
      widget.onContinue(_effectivePath);
      return;
    }
    setState(() => _busy = true);
    final out = <String>[];
    for (var i = 0; i < _pages.length; i++) {
      await _renderMode(i, _mode);
      out.add(_shownAt(i) ?? _pages[i]);
    }
    if (!mounted) return;
    setState(() => _busy = false);
    final onAll = widget.onContinueAll;
    if (onAll != null) {
      onAll(out);
    } else {
      widget.onContinue(out.isNotEmpty ? out.first : null);
    }
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
                    child: _isMulti ? _pagedPreview() : _singlePreview(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            // Floating control sheet: copy modes + tools + Continue.
            FadeSlideIn(
              delay: const Duration(milliseconds: 120),
              child: _ControlSheet(
                children: [
                  _ModeSelector(
                    mode: _mode,
                    enabled: !_busy,
                    onSelect: _selectMode,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      if (!_isMulti) ...[
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
                      ],
                      _Tool(
                        icon: Icons.refresh_rounded,
                        label: l10n.t('retake'),
                        onTap: widget.onRetake,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _ContinueButton(onContinue: _continue),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _singlePreview() {
    return _CapturePreview(
      imagePath: _effectivePath,
      accent: _mode != ScanColorMode.original,
      busy: _busy,
    );
  }

  /// Multi-page: swipeable carousel + "current / total" page badge + dots.
  Widget _pagedPreview() {
    return Column(
      children: [
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            itemCount: _pages.length,
            onPageChanged: _onPageChanged,
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Center(
                child: _CapturePreview(
                  imagePath: _shownAt(i),
                  accent: _mode != ScanColorMode.original,
                  busy: _busy && i == _previewIndex,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _chrome.surfaceVariant,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(color: _chrome.border),
              ),
              child: Text(
                '${_previewIndex + 1} / ${_pages.length}',
                style: AppText.caption.copyWith(
                  color: _chrome.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            for (var i = 0; i < _pages.length && i < 8; i++)
              Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i == _previewIndex
                      ? AppColors.primaryGreen
                      : _chrome.border,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// The copy-mode selector: Original · Enhanced · B&W · Grayscale chips - the
/// WhatsApp / Adobe Scan filter row.
class _ModeSelector extends StatelessWidget {
  const _ModeSelector({
    required this.mode,
    required this.enabled,
    required this.onSelect,
  });

  final ScanColorMode mode;
  final bool enabled;
  final ValueChanged<ScanColorMode> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final m in ScanColorMode.values) ...[
            PressableScale(
              pressedScale: 0.95,
              child: GestureDetector(
                onTap: enabled ? () => onSelect(m) : null,
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: m == mode
                        ? AppColors.tealMist
                        : AppColors.tealFoam,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    border: Border.all(
                      color: m == mode
                          ? AppColors.primaryGreen
                          : AppBorders.line,
                    ),
                  ),
                  child: Text(
                    l10n.t(m.labelKey),
                    style: AppText.caption.copyWith(
                      color: m == mode
                          ? AppColors.primaryGreen
                          : AppColors.textMuted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
          ],
        ],
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
/// scanner's edge-detection language. The frame adapts to the available space
/// (portrait-page proportions upright, wider in landscape) instead of a fixed
/// aspect.
class _CapturePreview extends StatelessWidget {
  const _CapturePreview({
    required this.imagePath,
    required this.accent,
    required this.busy,
  });

  final String? imagePath;
  final bool accent;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Portrait-document proportions when tall space is available; relax
        // toward the available shape in landscape / short viewports.
        final available = constraints.maxHeight > 0 && constraints.maxWidth > 0
            ? constraints.maxWidth / constraints.maxHeight
            : 0.7;
        final aspect = available.clamp(0.62, 1.45).toDouble();
        return AspectRatio(
          aspectRatio: aspect < 1 ? 0.7 : aspect,
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
                        .withValues(alpha: accent ? 0.7 : 0.35),
                    width: accent ? 2 : 1.4,
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
                    if (busy)
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
      },
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

/// The rounded-top control sheet hosting the tools and the CTA - the
/// Stitch "preview & filter" panel. The stage above stays dark, but the
/// chrome itself is a Divine Glass white sheet with a hairline sky border.
class _ControlSheet extends StatelessWidget {
  const _ControlSheet({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(AppRadius.large)),
        border: Border.all(color: AppBorders.line),
        boxShadow: AppShadows.floating,
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
                  color: AppColors.tealPale,
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
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Tools no longer carry a persistent "active" state - the copy-mode chips
    // above communicate the selected filter.
    return PressableScale(
      pressedScale: 0.9,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Circular pastel glass control (Divine Glass icon chip).
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: AppColors.tealFoam,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.tealPale),
              ),
              child: Icon(icon, color: AppColors.primaryGreen, size: 22),
            ),
            const SizedBox(height: 7),
            Text(label,
                style: AppText.caption.copyWith(
                    color: AppColors.textMuted,
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
