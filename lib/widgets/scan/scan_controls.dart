import 'package:flutter/material.dart';

import '../../screens/scan/scan_theme.dart';
import '../pressable_scale.dart';

/// Lifecycle of the capture button, which changes its look per state.
enum CaptureButtonState { idle, detected, capturing, success }

/// The scanner's bottom control bar: Gallery · Capture · Flash.
///
/// The capture button is the unmistakable primary action — a large 78dp ring
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
    this.enabled = true,
  });

  final VoidCallback onGallery;
  final VoidCallback onCapture;
  final VoidCallback onToggleFlash;
  final IconData flashIcon;
  final String flashLabel;
  final CaptureButtonState captureState;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _SideButton(
          icon: Icons.photo_library_rounded,
          label: 'Gallery',
          onTap: enabled ? onGallery : null,
        ),
        _CaptureButton(
          state: captureState,
          onTap: enabled ? onCapture : null,
        ),
        _SideButton(
          icon: flashIcon,
          label: flashLabel,
          active: flashLabel != 'Off',
          onTap: enabled ? onToggleFlash : null,
        ),
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
    final detected = state == CaptureButtonState.detected;

    Widget core;
    if (busy) {
      core = const Padding(
        padding: EdgeInsets.all(18),
        child: CircularProgressIndicator(
          strokeWidth: 3,
          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
        ),
      );
    } else if (success) {
      core = const Icon(Icons.check_rounded, color: Colors.white, size: 30);
    } else {
      core = const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 26);
    }

    return PressableScale(
      pressedScale: 0.9,
      child: GestureDetector(
        onTap: busy ? null : onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: 78,
          height: 78,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white,
              width: detected ? 5 : 4,
            ),
            boxShadow: [
              BoxShadow(
                color: ScanColors.green.withValues(alpha: detected ? 0.7 : 0.45),
                blurRadius: detected ? 28 : 20,
                spreadRadius: detected ? 2 : 1,
              ),
            ],
          ),
          padding: const EdgeInsets.all(5),
          child: Container(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: ScanColors.gradient,
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
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? ScanColors.green : Colors.white;
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
                    color: Colors.white.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: active
                          ? ScanColors.green
                          : Colors.white.withValues(alpha: 0.18),
                    ),
                  ),
                  child: Icon(icon, color: color, size: 23),
                ),
                const SizedBox(height: 7),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
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
