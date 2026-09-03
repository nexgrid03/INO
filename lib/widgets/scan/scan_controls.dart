import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
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
    final l10n = AppLocalizations.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _SideButton(
          icon: Icons.photo_library_rounded,
          label: l10n.t('gallery'),
          onTap: enabled ? onGallery : null,
        ),
        _CaptureButton(
          state: captureState,
          onTap: enabled ? onCapture : null,
        ),
        const SizedBox(width: 64),
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
      // Sized to the button's white inner disc (76 - 3.5px ring - 4.5px
      // inset = 58), so the mark fills it without touching the edge.
      core = const InoLoader(size: 40, color: Colors.black);
    } else if (success) {
      core = const Icon(Icons.check_rounded, color: Colors.black, size: 30);
    } else {
      core = const SizedBox.shrink();
    }

    return PressableScale(
      pressedScale: 0.92,
      child: GestureDetector(
        onTap: busy ? null : onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black.withValues(alpha: 0.3),
            border: Border.all(
              color: Colors.white,
              width: 3.5,
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

class _SideButton extends StatelessWidget {
  const _SideButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.4 : 1,
      child: PressableScale(
        pressedScale: 0.9,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: 64,
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
                      color: Colors.white.withValues(alpha: 0.4),
                      width: 1.5,
                    ),
                  ),
                  child: Icon(icon, color: Colors.white, size: 23),
                ),
                const SizedBox(height: 7),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
