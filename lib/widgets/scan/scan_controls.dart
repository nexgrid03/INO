import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../pressable_scale.dart';

/// The scanner's bottom control bar: Gallery · Capture · Flash.
///
/// The capture button is the unmistakable primary action — a large 76dp white
/// ring with a green gradient core and a generous touch target. Gallery and
/// flash are quiet secondary affordances flanking it.
class ScanControls extends StatelessWidget {
  const ScanControls({
    super.key,
    required this.onGallery,
    required this.onCapture,
    required this.onToggleFlash,
    required this.flashOn,
  });

  final VoidCallback onGallery;
  final VoidCallback onCapture;
  final VoidCallback onToggleFlash;
  final bool flashOn;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _SideButton(
          icon: Icons.photo_library_rounded,
          label: 'Gallery',
          onTap: onGallery,
        ),
        _CaptureButton(onTap: onCapture),
        _SideButton(
          icon: flashOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
          label: 'Flash',
          active: flashOn,
          onTap: onToggleFlash,
        ),
      ],
    );
  }
}

class _CaptureButton extends StatelessWidget {
  const _CaptureButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      pressedScale: 0.9,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 4),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryGreen.withValues(alpha: 0.45),
                blurRadius: 22,
                spreadRadius: 1,
              ),
            ],
          ),
          padding: const EdgeInsets.all(5),
          child: Container(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppColors.brandGradient,
            ),
            child: const Icon(Icons.camera_alt_rounded,
                color: Colors.white, size: 26),
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
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.primaryGreen : Colors.white;
    return PressableScale(
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
                        ? AppColors.primaryGreen
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
    );
  }
}
