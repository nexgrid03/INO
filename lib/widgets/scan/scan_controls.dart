import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/perf/image_decode.dart';
import '../../screens/scan/scan_theme.dart';
import '../../services/image_enhancer.dart';
import '../common/ino_loader.dart';
import '../pressable_scale.dart';

/// Lifecycle of the capture button, which changes its look per state.
enum CaptureButtonState { idle, detected, capturing, success }

/// The scanner's bottom control bar:
/// - Left: Gallery button (when 0 pages) OR Captured Page Thumbnail with Page Count Badge + Retake
/// - Center: Large 80dp circular Capture / Shutter button with state animations
/// - Right: Filter toggle button (when 0 pages) OR vibrant Blue Checkmark button to finish scanning
class ScanControls extends StatelessWidget {
  const ScanControls({
    super.key,
    required this.onGallery,
    required this.onCapture,
    required this.onToggleFlash,
    required this.flashIcon,
    required this.flashLabel,
    required this.captureState,
    this.scannedPages = const [],
    this.onTapThumbnail,
    this.onRetake,
    this.onFinishScanning,
    this.onToggleFilter,
    this.activeFilter = ScanColorMode.original,
    this.flashActive = false,
    this.enabled = true,
  });

  final VoidCallback onGallery;
  final VoidCallback onCapture;
  final VoidCallback onToggleFlash;
  final IconData flashIcon;
  final String flashLabel;
  final bool flashActive;
  final CaptureButtonState captureState;
  final List<String> scannedPages;
  final VoidCallback? onTapThumbnail;
  final VoidCallback? onRetake;
  final VoidCallback? onFinishScanning;
  final VoidCallback? onToggleFilter;
  final ScanColorMode activeFilter;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final hasPages = scannedPages.isNotEmpty;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Left slot: Thumbnail with badge + Retake, or Gallery button
        SizedBox(
          width: 80,
          child: hasPages
              ? _ThumbnailWithBadge(
                  latestPagePath: scannedPages.last,
                  pageCount: scannedPages.length,
                  onTap: enabled ? onTapThumbnail : null,
                  onRetake: enabled ? onRetake : null,
                )
              : _GalleryButton(
                  onTap: enabled ? onGallery : null,
                ),
        ),

        // Center slot: Large capture button
        _CaptureButton(
          state: captureState,
          onTap: enabled ? onCapture : null,
        ),

        // Right slot: Blue checkmark to finish scanning OR Filter button
        SizedBox(
          width: 80,
          child: hasPages
              ? _FinishScanButton(
                  onTap: enabled ? onFinishScanning : null,
                )
              : _FilterButton(
                  active: activeFilter != ScanColorMode.original,
                  onTap: enabled ? onToggleFilter : null,
                ),
        ),
      ],
    );
  }
}

/// Large 80dp capture button with state animation
class _CaptureButton extends StatelessWidget {
  const _CaptureButton({required this.state, required this.onTap});

  final CaptureButtonState state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final busy = state == CaptureButtonState.capturing;
    final success = state == CaptureButtonState.success;

    Widget core;
    if (busy) {
      core = const InoLoader(size: 38, color: ScanColors.accent);
    } else if (success) {
      core = const Icon(Icons.check_rounded, color: ScanColors.accent, size: 36);
    } else {
      core = const SizedBox.shrink();
    }

    return PressableScale(
      pressedScale: 0.92,
      child: GestureDetector(
        onTap: busy ? null : onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white,
              width: 4.0,
            ),
          ),
          padding: const EdgeInsets.all(4.5),
          child: Container(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
            child: Center(child: core),
          ),
        ),
      ),
    );
  }
}

/// Blue checkmark button to finish multi-page scanning session
class _FinishScanButton extends StatelessWidget {
  const _FinishScanButton({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      pressedScale: 0.92,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: ScanColors.accent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.85),
                  width: 2.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: ScanColors.accent.withValues(alpha: 0.45),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Center(
                child: Icon(
                  Icons.check_rounded,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Done',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Thumbnail of the latest captured page with a page-count badge
class _ThumbnailWithBadge extends StatelessWidget {
  const _ThumbnailWithBadge({
    required this.latestPagePath,
    required this.pageCount,
    required this.onTap,
    this.onRetake,
  });

  final String latestPagePath;
  final int pageCount;
  final VoidCallback? onTap;
  final VoidCallback? onRetake;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PressableScale(
          pressedScale: 0.92,
          child: GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: ScanColors.accent,
                      width: 2.0,
                    ),
                    color: Colors.black45,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.file(
                    File(latestPagePath),
                    fit: BoxFit.cover,
                    cacheWidth: context.decodeWidthFor(52),
                  ),
                ),
                // Page count badge
                Positioned(
                  top: -6,
                  right: -6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: ScanColors.accent,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.4),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                    child: Center(
                      child: Text(
                        '$pageCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (onRetake != null) ...[
          const SizedBox(height: 3),
          GestureDetector(
            onTap: onRetake,
            child: const Text(
              'Retake',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w500,
                decoration: TextDecoration.underline,
                decorationColor: Colors.white54,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Gallery button when 0 pages have been scanned
class _GalleryButton extends StatelessWidget {
  const _GalleryButton({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.4 : 1.0,
      child: PressableScale(
        pressedScale: 0.92,
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
                  color: Colors.black.withValues(alpha: 0.4),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white,
                    width: 2.0,
                  ),
                ),
                child: const Icon(
                  Icons.photo_outlined,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Gallery',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Filter toggle button
class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.active, required this.onTap});

  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      pressedScale: 0.92,
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
                    ? ScanColors.accent.withValues(alpha: 0.3)
                    : Colors.black.withValues(alpha: 0.4),
                shape: BoxShape.circle,
                border: Border.all(
                  color: active ? ScanColors.accent : Colors.white70,
                  width: 2.0,
                ),
              ),
              child: Icon(
                Icons.auto_awesome_rounded,
                color: active ? ScanColors.accentDeep : Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Filters',
              style: TextStyle(
                color: active ? ScanColors.accentDeep : Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
