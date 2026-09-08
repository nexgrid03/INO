import 'package:flutter/material.dart';

import '../pressable_scale.dart';
import '../common/ino_loader.dart';

/// Lifecycle of the capture button, which changes its look per state.
enum CaptureButtonState { idle, detected, capturing, success }

/// The scanner's bottom control bar: Gallery · Capture · Flash.
///
/// The capture button is the unmistakable primary action - a large 78dp ring
/// with a green→blue gradient core that morphs through idle → detected →
/// capturing (spinner) → success (check). Gallery and flash are quiet glassy
/// affordances flanking it.
class ScanControls extends StatelessWidget {
  const ScanControls({
    super.key,
    required this.onGallery,
    required this.onCapture,
    required this.onToggleFlash,
    required this.flashIcon,
    required this.flashLabel,
    required this.captureState,
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
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _GalleryButton(
          onTap: enabled ? onGallery : null,
        ),
        _CaptureButton(
          state: captureState,
          onTap: enabled ? onCapture : null,
        ),
        // Balanced spacer to keep the shutter button centered
        const SizedBox(width: 56),
      ],
    );
  }
}

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
      core = const InoLoader(size: 38, color: Colors.black);
    } else if (success) {
      core = const Icon(Icons.check_rounded, color: Colors.black, size: 32);
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
          child: Container(
            width: 56,
            height: 56,
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
        ),
      ),
    );
  }
}
