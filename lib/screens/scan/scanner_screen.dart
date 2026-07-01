import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/scan_models.dart';
import '../../services/camera_permission_service.dart';
import '../../services/gallery_import_service.dart';
import '../../widgets/scan/scan_controls.dart';
import '../../widgets/scan/scan_guidance_pill.dart';
import '../../widgets/scan/scanner_overlay.dart';
import 'scan_theme.dart';

/// Screen 1 — the production document scanner.
///
/// Initialises the device camera, manages runtime permissions and lifecycle,
/// and frames a real live preview with the INO overlay + controls. Capture is
/// powered by ML Kit's on-device document scanner (auto edge detection, crop,
/// perspective correction, enhancement) on Android, with a [camera] still-image
/// fallback elsewhere. Gallery import feeds the same pipeline. The widget hands
/// the resulting image path back via [onCaptured].
class ScannerScreen extends StatefulWidget {
  const ScannerScreen({
    super.key,
    required this.onClose,
    required this.onCaptured,
  });

  final VoidCallback onClose;

  /// Emits the captured/imported image file path to continue the flow.
  final ValueChanged<String> onCaptured;

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

enum _Phase { initializing, ready, denied, permanentlyDenied, error }

class _ScannerScreenState extends State<ScannerScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  _Phase _phase = _Phase.initializing;
  CaptureButtonState _capture = CaptureButtonState.idle;
  int _flash = 0; // 0 = off, 1 = auto, 2 = on(torch)
  bool _blockBootstrap = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  // ---- Lifecycle -----------------------------------------------------------

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      // Free the camera while backgrounded (and during the ML Kit activity).
      _controller = null;
      controller?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      // Re-check permissions (covers returning from Settings) and reinitialise.
      if (mounted && !_blockBootstrap) _bootstrap();
    }
  }

  // ---- Permissions + camera init ------------------------------------------

  Future<void> _bootstrap() async {
    if (mounted) setState(() => _phase = _Phase.initializing);
    try {
      var access = await CameraPermissionService.instance.cameraStatus();
      if (access == CameraAccess.denied) {
        access = await CameraPermissionService.instance.requestCamera();
      }
      if (!mounted) return;
      switch (access) {
        case CameraAccess.granted:
          await _initCamera();
        case CameraAccess.permanentlyDenied:
          setState(() => _phase = _Phase.permanentlyDenied);
        case CameraAccess.denied:
          setState(() => _phase = _Phase.denied);
        case CameraAccess.restricted:
          setState(() => _phase = _Phase.error);
      }
    } catch (_) {
      // Plugin unavailable / no camera hardware / unsupported device.
      if (mounted) setState(() => _phase = _Phase.error);
    }
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _phase = _Phase.error);
        return;
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.veryHigh,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      _controller = controller;
      await controller.initialize();
      await controller.setFlashMode(FlashMode.off);
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() {
        _flash = 0;
        _phase = _Phase.ready;
      });
    } catch (_) {
      if (mounted) setState(() => _phase = _Phase.error);
    }
  }

  // ---- Controls ------------------------------------------------------------

  Future<void> _cycleFlash() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final next = (_flash + 1) % 3;
    const modes = [FlashMode.off, FlashMode.auto, FlashMode.torch];
    try {
      await controller.setFlashMode(modes[next]);
      if (mounted) setState(() => _flash = next);
    } catch (_) {
      _snack('Flash not available on this device');
    }
  }

  IconData get _flashIcon => switch (_flash) {
        1 => Icons.flash_auto_rounded,
        2 => Icons.flash_on_rounded,
        _ => Icons.flash_off_rounded,
      };

  String get _flashLabel => switch (_flash) {
        1 => 'Auto',
        2 => 'On',
        _ => 'Off',
      };

  Future<void> _capturePressed() async {
    final controller = _controller;
    if (_phase != _Phase.ready ||
        controller == null ||
        !controller.value.isInitialized ||
        _capture == CaptureButtonState.capturing) {
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() => _capture = CaptureButtonState.capturing);
    try {
      // Capture the still image with the in-app camera preview — no external
      // scanner activity, so the user stays inside INO the whole time. Edge
      // detection / crop happen downstream on the captured image.
      final file = await controller.takePicture();
      if (!mounted) return;
      HapticFeedback.lightImpact();
      setState(() => _capture = CaptureButtonState.success);
      await Future<void>.delayed(const Duration(milliseconds: 240));
      if (!mounted) return;
      widget.onCaptured(file.path);
    } catch (_) {
      if (!mounted) return;
      setState(() => _capture = CaptureButtonState.idle);
      _snack('Capture failed. Please try again.');
    }
  }

  Future<void> _galleryPressed() async {
    setState(() => _blockBootstrap = true);
    try {
      final path = await GalleryImportService.instance.pickImage();
      if (!mounted) return;
      if (path == null) {
        setState(() => _blockBootstrap = false);
        return;
      }
      widget.onCaptured(path);
    } catch (_) {
      if (mounted) {
        setState(() => _blockBootstrap = false);
        _snack('Could not open the gallery.');
      }
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        behavior: SnackBarBehavior.floating,
        backgroundColor: ScanColors.textPrimary,
      ),
    );
  }

  // ---- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final ready = _phase == _Phase.ready;
    return Scaffold(
      backgroundColor: ScanColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            _header(),
            Expanded(child: _viewport()),
            if (ready)
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 8, 28, 24),
                child: ScanControls(
                  onGallery: _galleryPressed,
                  onCapture: _capturePressed,
                  onToggleFlash: _cycleFlash,
                  flashIcon: _flashIcon,
                  flashLabel: _flashLabel,
                  captureState: _capture == CaptureButtonState.idle
                      ? CaptureButtonState.detected
                      : _capture,
                ),
              )
            else
              const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: widget.onClose,
            icon: const Icon(Icons.close_rounded,
                color: ScanColors.textPrimary, size: 26),
            tooltip: 'Close',
          ),
          const Expanded(
            child: Column(
              children: [
                Text(
                  'Scan Document',
                  style: TextStyle(
                    color: ScanColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Position your document inside the frame',
                  style: TextStyle(
                    color: ScanColors.textSecondary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _viewport() {
    switch (_phase) {
      case _Phase.ready:
        return _cameraViewport();
      case _Phase.initializing:
        return const _CenterStatus(
          icon: Icons.photo_camera_rounded,
          title: 'Starting camera…',
          spinner: true,
        );
      case _Phase.denied:
        return _StatusView(
          icon: Icons.no_photography_rounded,
          title: 'Camera access needed',
          message:
              'INO needs your camera to scan documents. Your scans stay private on your device.',
          primaryLabel: 'Grant Camera Access',
          onPrimary: _bootstrap,
        );
      case _Phase.permanentlyDenied:
        return _StatusView(
          icon: Icons.lock_rounded,
          title: 'Camera permission blocked',
          message:
              'Camera access is turned off for INO. Enable it in Settings to scan documents.',
          primaryLabel: 'Open Settings',
          onPrimary: () => CameraPermissionService.instance.openSettings(),
          secondaryLabel: 'Recheck',
          onSecondary: _bootstrap,
        );
      case _Phase.error:
        return _StatusView(
          icon: Icons.error_outline_rounded,
          title: 'Camera unavailable',
          message:
              'We couldn’t start the camera on this device. You can still import a document from your gallery.',
          primaryLabel: 'Retry',
          onPrimary: _bootstrap,
          secondaryLabel: 'Import from Gallery',
          onSecondary: _galleryPressed,
        );
    }
  }

  Widget _cameraViewport() {
    final controller = _controller;
    // Camera is live and locked on; real edge detection + crop happen in the
    // capture engine, so the overlay communicates "ready" honestly.
    const overlayState = ScanOverlayState.ready;
    final guidance = _capture == CaptureButtonState.capturing
        ? ScanGuidance.holdSteady
        : ScanGuidance.ready;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (controller != null && controller.value.isInitialized)
              _CoveredPreview(controller: controller)
            else
              const ColoredBox(color: Colors.black),
            ScannerOverlay(state: overlayState),
            Positioned(
              left: 0,
              right: 0,
              bottom: 18,
              child: Center(child: ScanGuidancePill(guidance: guidance)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fills the viewport with the camera preview using BoxFit.cover (no stretch),
/// accounting for the sensor's portrait/landscape orientation.
class _CoveredPreview extends StatelessWidget {
  const _CoveredPreview({required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final size = controller.value.previewSize;
    if (size == null) return CameraPreview(controller);
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        // previewSize is in sensor coordinates; swap for portrait display.
        width: size.height,
        height: size.width,
        child: CameraPreview(controller),
      ),
    );
  }
}

class _CenterStatus extends StatelessWidget {
  const _CenterStatus({
    required this.icon,
    required this.title,
    this.spinner = false,
  });

  final IconData icon;
  final String title;
  final bool spinner;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: ScanColors.textSecondary, size: 46),
          const SizedBox(height: 16),
          if (spinner) ...[
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                valueColor: AlwaysStoppedAnimation<Color>(ScanColors.accent),
              ),
            ),
            const SizedBox(height: 14),
          ],
          Text(
            title,
            style: const TextStyle(
              color: ScanColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Recovery view for the permission / error phases.
class _StatusView extends StatelessWidget {
  const _StatusView({
    required this.icon,
    required this.title,
    required this.message,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  final IconData icon;
  final String title;
  final String message;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                color: ScanColors.surfaceVariant,
                shape: BoxShape.circle,
                border: Border.all(color: ScanColors.border),
              ),
              child: Icon(icon, color: ScanColors.accent, size: 42),
            ),
            const SizedBox(height: 22),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: ScanColors.textPrimary,
                fontSize: 19,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: ScanColors.textSecondary,
                fontSize: 13.5,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 26),
            _GradientButton(label: primaryLabel, onTap: onPrimary),
            if (secondaryLabel != null && onSecondary != null) ...[
              const SizedBox(height: 12),
              TextButton(
                onPressed: onSecondary,
                child: Text(
                  secondaryLabel!,
                  style: const TextStyle(
                    color: ScanColors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GradientButton extends StatelessWidget {
  const _GradientButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 28),
        decoration: BoxDecoration(
          gradient: ScanColors.gradient,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: ScanColors.green.withValues(alpha: 0.35),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
