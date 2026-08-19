import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../models/scan_models.dart';
import '../../services/camera_permission_service.dart';
import '../../services/gallery_import_service.dart';
import '../../services/live_document_detector.dart';
import '../../widgets/scan/scan_controls.dart';
import 'scan_theme.dart';

/// Screen 1 - the production document scanner.
///
/// Initialises the device camera, manages runtime permissions and lifecycle,
/// and frames a real live preview with the INO overlay + controls. A live
/// image-stream detector ([LiveDocumentDetector]) drives the on-screen state
/// machine ([ScannerState]) so the "Document Detected" / "Ready to Scan" badges
/// only ever appear in response to a real document in frame - never by default.
/// Capture is a plain in-app still (edge detection / crop happen downstream on
/// the captured image). Gallery import feeds the same pipeline. The widget hands
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

  /// Detection/capture state - starts at [ScannerState.idle] and only ever
  /// advances in response to real camera frames or a capture press. Never
  /// pre-loaded to a "detected"/"ready" value.
  ScannerState _state = ScannerState.idle;

  bool _isAutoMode = true;
  int _flash = 0; // 0 = off, 1 = auto, 2 = on(torch)
  bool _blockBootstrap = false;

  // ---- Live document detection --------------------------------------------
  final LiveDocumentDetector _detector = LiveDocumentDetector();
  final Stopwatch _throttle = Stopwatch();
  bool _streaming = false;

  /// Consecutive qualifying frames seen while searching (debounces the jump
  /// from idle → documentDetected so a single noisy frame can't flash a badge).
  int _presentFrames = 0;

  /// When the document first became stable - the anchor for the "held steady
  /// for 1–2s" requirement before promoting to readyToScan.
  DateTime? _stableStart;

  // Tunables (may be calibrated per device).
  static const int _kSampleIntervalMs = 150; // process ~6–7 frames/sec
  static const int _kConfirmFrames = 2; // ~300ms of presence before badge
  static const double _kDetectConfidence = 0.5; // enter "detected"
  static const double _kLoseConfidence = 0.35; // hysteresis: drop back to idle
  static const Duration _kStableDuration = Duration(milliseconds: 1200);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Stop the frame stream BEFORE disposing. Disposing a CameraController that
    // is still streaming makes CameraX block the main thread during shutdown
    // (the "CameraX shutdown → INO isn't responding → Lost connection" freeze,
    // with no Dart/native exception). dispose() can't await, so hand the
    // controller to a fire-and-forget teardown that stops the stream first.
    final controller = _controller;
    _controller = null;
    _streaming = false;
    _teardownCamera(controller);
    super.dispose();
  }

  /// Stops the image stream (if running) and THEN disposes the controller, so
  /// CameraX never tears down with frames in flight — which is what hangs the
  /// UI thread on shutdown.
  Future<void> _teardownCamera(CameraController? controller) async {
    if (controller == null) return;
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (_) {/* already stopped / not streaming */}
    try {
      await controller.dispose();
    } catch (_) {/* already disposed */}
  }

  // ---- Lifecycle -----------------------------------------------------------

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      // Free the camera while backgrounded (and during the ML Kit activity).
      // Stop the stream before disposing (see [_teardownCamera]) so CameraX
      // shutdown never blocks the main thread when the app goes inactive.
      _controller = null;
      _streaming = false;
      _teardownCamera(controller);
      // Tear down detection so it restarts clean (at idle) on resume.
      _detector.reset();
      _resetDetectionState();
      _clearTransientFeedback();
      _state = ScannerState.idle;
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
        // YUV420 so we can run the live image stream for real-time detection;
        // still capture (takePicture) returns a JPEG regardless of this group.
        imageFormatGroup: ImageFormatGroup.yuv420,
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
        _state = ScannerState.idle; // always start fresh - no pre-loaded badge
        _phase = _Phase.ready;
      });
      await _startDetection();
    } catch (_) {
      if (mounted) setState(() => _phase = _Phase.error);
    }
  }

  // ---- Real-time detection -------------------------------------------------

  /// Begins streaming camera frames into the [LiveDocumentDetector]. If the
  /// platform can't stream, detection simply stays idle and capture remains
  /// fully usable - we never fake a detection.
  Future<void> _startDetection() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _streaming) {
      return;
    }
    _detector.reset();
    _resetDetectionState();
    _throttle
      ..reset()
      ..start();
    try {
      await controller.startImageStream(_onFrame);
      _streaming = true;
    } catch (_) {
      _streaming = false; // streaming unsupported - degrade gracefully
    }
  }

  /// Stops the image stream (before a still capture, or when freeing the
  /// camera).
  Future<void> _stopDetection() async {
    final controller = _controller;
    _streaming = false;
    if (controller != null && controller.value.isStreamingImages) {
      try {
        await controller.stopImageStream();
      } catch (_) {}
    }
  }

  void _resetDetectionState() {
    _presentFrames = 0;
    _stableStart = null;
  }

  void _onFrame(CameraImage image) {
    if (!mounted || _phase != _Phase.ready) return;
    // Detection is paused while capturing / after success.
    if (_state == ScannerState.capturing || _state == ScannerState.success) {
      return;
    }
    // Throttle the heavier work to a handful of frames per second.
    if (_throttle.elapsedMilliseconds < _kSampleIntervalMs) return;
    _throttle.reset();

    final signal = _detector.analyze(image);
    _handleSignal(signal.confidence, signal.steady);
  }

  /// The state machine: idle → detecting → documentDetected → readyToScan,
  /// collapsing straight back to idle the moment the document is lost.
  void _handleSignal(double confidence, bool steady) {
    final bool present = confidence >= _kDetectConfidence;
    final bool stillPresent = confidence >= _kLoseConfidence;

    switch (_state) {
      case ScannerState.idle:
      case ScannerState.detecting:
        if (present) {
          _presentFrames++;
          if (_presentFrames >= _kConfirmFrames) {
            _stableStart = steady ? DateTime.now() : null;
            _enter(ScannerState.documentDetected);
          } else {
            _enter(ScannerState.detecting);
          }
        } else {
          _presentFrames = 0;
          _enter(ScannerState.idle);
        }

      case ScannerState.documentDetected:
      case ScannerState.readyToScan:
        if (!stillPresent) {
          // Document moved out of frame → hide badges immediately.
          _resetDetectionState();
          _enter(ScannerState.idle);
          return;
        }
        if (steady) {
          final start = _stableStart ??= DateTime.now();
          if (DateTime.now().difference(start) >= _kStableDuration) {
            _enter(ScannerState.readyToScan);
          } else {
            _enter(ScannerState.documentDetected);
          }
        } else {
          // Movement restarts the "held steady" window.
          _stableStart = null;
          _enter(ScannerState.documentDetected);
        }

      case ScannerState.capturing:
      case ScannerState.success:
        break; // detection paused during capture
    }
  }

  /// Applies a new [ScannerState] (only when it actually changed).
  ///
  /// The transient success toast + "hold steady" hint fire ONLY on a genuine
  /// `idle`/`detecting → documentDetected` transition - never when returning
  /// from `readyToScan` - so a document that lingers in frame can't re-spam the
  /// popup. Collapsing back to `idle` clears any lingering feedback.
  void _enter(ScannerState next) {
    if (_state == next || !mounted) return;
    final prev = _state;
    final bool newDetection = next == ScannerState.documentDetected &&
        (prev == ScannerState.idle || prev == ScannerState.detecting);

    setState(() {
      _state = next;
    });

    if (newDetection) {
      HapticFeedback.selectionClick();
    } else if (next == ScannerState.readyToScan) {
      HapticFeedback.lightImpact();
      if (_isAutoMode &&
          _state != ScannerState.capturing &&
          _state != ScannerState.success) {
        _capturePressed();
      }
    }
  }

  void _clearTransientFeedback() {}

  // ---- Controls ------------------------------------------------------------

  Future<void> _cycleFlash() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final next = (_flash + 1) % 3;
    const modes = [FlashMode.off, FlashMode.auto, FlashMode.torch];
    // Resolve the failure message before the await (context is unsafe after).
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
    // Free the image stream before a still capture (they can't run together).
    await _stopDetection();
    if (!mounted) return;
    setState(() => _state = ScannerState.capturing);
    try {
      // Capture the still image with the in-app camera preview - no external
      // scanner activity, so the user stays inside INO the whole time. Edge
      // detection / crop happen downstream on the captured image.
      final file = await controller.takePicture();
      if (!mounted) return;
      HapticFeedback.lightImpact();
      setState(() => _state = ScannerState.success);
      await Future<void>.delayed(const Duration(milliseconds: 240));
      if (!mounted) return;
      widget.onCaptured(file.path);
    } catch (_) {
      if (!mounted) return;
      setState(() => _state = ScannerState.idle);
      _snack(AppLocalizations.of(context).t('captureFailed'));
      _startDetection(); // resume live detection after a failed shot
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

  // ---- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final ready = _phase == _Phase.ready;
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _viewport(),
          if (ready) ...[
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _FloatingGlassButton(
                            icon: Icons.close_rounded,
                            onTap: widget.onClose,
                            tooltip: 'Close',
                          ),
                          _FloatingGlassButton(
                            icon: _flashIcon,
                            active: _flash != 0,
                            onTap: _cycleFlash,
                            tooltip: '${l10n.t('flash')}: $_flashLabel',
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const _InstructionPill(),
                    ],
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 8, 28, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _AutoManualToggle(
                        isAuto: _isAutoMode,
                        onChanged: (isAuto) => setState(() => _isAutoMode = isAuto),
                      ),
                      const SizedBox(height: 18),
                      ScanControls(
                        onGallery: _galleryPressed,
                        onCapture: _capturePressed,
                        onToggleFlash: _cycleFlash,
                        flashIcon: _flashIcon,
                        flashLabel: _flashLabel,
                        flashActive: _flash != 0,
                        captureState: _captureButtonState,
                      ),
                    ],
                  ),
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
    return const ColoredBox(color: Colors.black);
  }

  /// Capture button visuals derived from the detection state - idle (neutral)
  /// until a document is actually detected.
  CaptureButtonState get _captureButtonState => switch (_state) {
        ScannerState.idle ||
        ScannerState.detecting =>
          CaptureButtonState.idle,
        ScannerState.documentDetected ||
        ScannerState.readyToScan =>
          CaptureButtonState.detected,
        ScannerState.capturing => CaptureButtonState.capturing,
        ScannerState.success => CaptureButtonState.success,
      };


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

class _FloatingGlassButton extends StatelessWidget {
  const _FloatingGlassButton({
    required this.icon,
    required this.onTap,
    this.active = false,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool active;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.25),
            width: 1.5,
          ),
        ),
        child: Icon(
          icon,
          color: Colors.white,
          size: 22,
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
  const _InstructionPill();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.15),
          width: 1,
        ),
      ),
      child: Text(
        l10n.t('positionDocument'),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _AutoManualToggle extends StatelessWidget {
  const _AutoManualToggle({
    required this.isAuto,
    required this.onChanged,
  });

  final bool isAuto;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.15),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildOption(label: 'AUTO', active: isAuto, onTap: () => onChanged(true)),
          _buildOption(label: 'MANUAL', active: !isAuto, onTap: () => onChanged(false)),
        ],
      ),
    );
  }

  Widget _buildOption({
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.black : Colors.white.withValues(alpha: 0.7),
            fontSize: 11.5,
            fontWeight: active ? FontWeight.w700 : FontWeight.w600,
            letterSpacing: 0.8,
          ),
        ),
      ),
    );
  }
}
