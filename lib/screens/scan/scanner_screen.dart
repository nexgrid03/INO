import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../models/scan_models.dart';
import '../../services/camera_permission_service.dart';
import '../../services/gallery_import_service.dart';
import '../../widgets/scan/scan_controls.dart';
import 'scan_theme.dart';
import '../../widgets/common/ino_loader.dart';

/// Screen 1 – the manual document scanner.
///
/// Opens the device camera, manages runtime permissions and lifecycle, and
/// frames a live preview with INO overlay + controls. Capture is a plain
/// in-app still; no live detection, no auto-capture, no blue outline.
/// Gallery import feeds the same pipeline. The widget hands the resulting
/// image path back via [onCaptured].
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

  ScannerState _state = ScannerState.idle;

  int _flash = 0; // 0 = off, 1 = auto, 2 = on(torch)
  bool _blockBootstrap = false;
  bool _isBootstrapping = false;
  bool _isRequestingPermission = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final controller = _controller;
    _controller = null;
    _teardownCamera(controller);
    super.dispose();
  }

  Future<void> _teardownCamera(CameraController? controller) async {
    if (controller == null) return;
    try {
      await controller.dispose();
    } catch (_) {/* already disposed */}
  }

  // ---- Lifecycle -----------------------------------------------------------

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isRequestingPermission) return;
    final controller = _controller;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _controller = null;
      _teardownCamera(controller);
      if (mounted) setState(() => _state = ScannerState.idle);
    } else if (state == AppLifecycleState.resumed) {
      if (mounted && !_blockBootstrap) _bootstrap();
    }
  }

  // ---- Permissions + camera init ------------------------------------------

  Future<void> _bootstrap() async {
    if (_isBootstrapping) return;
    _isBootstrapping = true;
    if (mounted) setState(() => _phase = _Phase.initializing);
    try {
      var access = await CameraPermissionService.instance.cameraStatus();
      if (access == CameraAccess.denied) {
        _isRequestingPermission = true;
        try {
          access = await CameraPermissionService.instance.requestCamera();
        } finally {
          _isRequestingPermission = false;
        }
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
      if (mounted) setState(() => _phase = _Phase.error);
    } finally {
      _isBootstrapping = false;
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

      final oldController = _controller;
      _controller = null;
      await _teardownCamera(oldController);

      final controller = CameraController(
        back,
        ResolutionPreset.veryHigh,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      await controller.setFlashMode(FlashMode.off);
      if (!mounted) {
        await _teardownCamera(controller);
        return;
      }
      _controller = controller;
      setState(() {
        _flash = 0;
        _state = ScannerState.idle;
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
    final flashError = AppLocalizations.of(context).t('flashNotAvailable');
    try {
      await controller.setFlashMode(modes[next]);
      if (mounted) setState(() => _flash = next);
    } catch (_) {
      _snack(flashError);
    }
  }

  IconData get _flashIcon => switch (_flash) {
        1 => Icons.flash_auto_rounded,
        2 => Icons.flash_on_rounded,
        _ => Icons.flash_off_rounded,
      };

  String get _flashLabel => switch (_flash) {
        1 => AppLocalizations.of(context).t('flashAuto'),
        2 => AppLocalizations.of(context).t('on'),
        _ => AppLocalizations.of(context).t('off'),
      };

  Future<void> _capturePressed() async {
    final controller = _controller;
    if (_phase != _Phase.ready ||
        controller == null ||
        !controller.value.isInitialized ||
        _state == ScannerState.capturing) {
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() => _state = ScannerState.capturing);
    try {
      final file = await controller.takePicture();
      if (!mounted) return;
      HapticFeedback.lightImpact();
      setState(() => _state = ScannerState.success);
      // Brief pause so the success state is visible, then hand off.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;
      widget.onCaptured(file.path);
    } catch (_) {
      if (!mounted) return;
      setState(() => _state = ScannerState.idle);
      _snack(AppLocalizations.of(context).t('captureFailed'));
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
        _snack(AppLocalizations.of(context).t('galleryOpenFailed'));
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

  CaptureButtonState get _captureButtonState => switch (_state) {
        ScannerState.capturing => CaptureButtonState.capturing,
        ScannerState.success => CaptureButtonState.success,
        _ => CaptureButtonState.idle,
      };

  // ---- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final ready = _phase == _Phase.ready;
    final l10n = AppLocalizations.of(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _viewport(),
          if (ready) ...[
            SafeArea(
              bottom: false,
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _CleanIconButton(
                            icon: Icons.close_rounded,
                            onTap: widget.onClose,
                            tooltip: l10n.t('close'),
                          ),
                          _CleanIconButton(
                            icon: _flashIcon,
                            onTap: _cycleFlash,
                            tooltip: '${l10n.t('flash')}: $_flashLabel',
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const _InstructionPill(
                        message: 'Position your document and tap to capture',
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.94),
                ),
                padding: EdgeInsets.fromLTRB(28, 18, 28, bottomInset > 0 ? bottomInset + 8 : 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ScanControls(
                      onGallery: _galleryPressed,
                      onCapture: _capturePressed,
                      onToggleFlash: _cycleFlash,
                      flashIcon: _flashIcon,
                      flashLabel: _flashLabel,
                      flashActive: _flash != 0,
                      captureState: _captureButtonState,
                    ),
                    const SizedBox(height: 14),
                    const _PrivacyFooter(),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _viewport() {
    final l10n = AppLocalizations.of(context);
    switch (_phase) {
      case _Phase.ready:
        return _cameraViewport();
      case _Phase.initializing:
        return _CenterStatus(
          icon: Icons.photo_camera_rounded,
          title: l10n.t('startingCamera'),
          spinner: true,
        );
      case _Phase.denied:
        return _StatusView(
          icon: Icons.no_photography_rounded,
          title: l10n.t('cameraAccessNeeded'),
          message: l10n.t('cameraAccessMessage'),
          primaryLabel: l10n.t('grantCameraAccess'),
          onPrimary: _bootstrap,
        );
      case _Phase.permanentlyDenied:
        return _StatusView(
          icon: Icons.lock_rounded,
          title: l10n.t('cameraBlocked'),
          message: l10n.t('cameraBlockedMessage'),
          primaryLabel: l10n.t('openSettings'),
          onPrimary: () => CameraPermissionService.instance.openSettings(),
          secondaryLabel: l10n.t('recheck'),
          onSecondary: _bootstrap,
        );
      case _Phase.error:
        return _StatusView(
          icon: Icons.error_outline_rounded,
          title: l10n.t('cameraUnavailable'),
          message: l10n.t('cameraUnavailableMessage'),
          primaryLabel: l10n.t('retry'),
          onPrimary: _bootstrap,
          secondaryLabel: l10n.t('importFromGallery'),
          onSecondary: _galleryPressed,
        );
    }
  }

  Widget _cameraViewport() {
    final controller = _controller;
    if (controller != null && controller.value.isInitialized) {
      return _CoveredPreview(controller: controller);
    }
    if (!_isBootstrapping) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_isBootstrapping) _bootstrap();
      });
    }
    final l10n = AppLocalizations.of(context);
    return _CenterStatus(
      icon: Icons.photo_camera_rounded,
      title: l10n.t('startingCamera'),
      spinner: true,
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
            InoLoader(size: 22, color: ScanColors.accent),
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

class _CleanIconButton extends StatelessWidget {
  const _CleanIconButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        child: Icon(
          icon,
          color: Colors.white,
          size: 26,
        ),
      ),
    );
    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}

class _InstructionPill extends StatelessWidget {
  const _InstructionPill({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xE61E1E20),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
          width: 1,
        ),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _PrivacyFooter extends StatelessWidget {
  const _PrivacyFooter();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            'inoapp will have access only to the images that you scan',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 11.5,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Icon(
          Icons.info_outline_rounded,
          color: Colors.white.withValues(alpha: 0.85),
          size: 15,
        ),
      ],
    );
  }
}
