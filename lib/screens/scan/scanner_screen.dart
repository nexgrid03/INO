import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:document_scan/document_scan.dart'
    show
        AutoCaptureAnalyzer,
        AutoCaptureStatus,
        DetectionSensitivity,
        DocumentCorners;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../models/scan_models.dart';
import '../../services/camera_permission_service.dart';
import '../../services/gallery_import_service.dart';
import '../../services/image_enhancer.dart';
import '../../services/live_document_detector.dart';
import '../../services/native_document_edge_service.dart';
import '../../services/scan_capture_processor.dart';
import '../../services/scan_pdf_service.dart';
import '../../widgets/common/ino_loader.dart';
import '../../widgets/scan/document_highlight.dart';
import '../../widgets/scan/scan_controls.dart';
import '../../widgets/scan/scanner_overlay.dart' show ScanOverlayState;
import 'scan_pdf_preview_screen.dart';
import 'scan_theme.dart';

/// The production in-app document scanner matching the high-end reference experience.
///
/// Features:
/// - Real-time camera preview with automatic document edge detection
/// - Animated blue boundary overlay with glowing edges and corner ticks (DocumentHighlight)
/// - Automatic perspective-correct crop & alignment of document edges
/// - Support for both portrait and landscape documents
/// - Flash, Filters (Original, Enhanced, B&W, Grayscale) and Shutter (Auto/Manual) controls
/// - Large circular capture button with state animation
/// - Seamless multi-page scanning session
/// - Captured page thumbnail with real-time page count badge
/// - Retake option and vibrant blue checkmark button to finish scanning
/// - Automatic assembly into a single high-quality PDF with integrated PDF preview
class ScannerScreen extends StatefulWidget {
  const ScannerScreen({
    super.key,
    required this.onClose,
    this.onCaptured,
    this.onCompleted,
  });

  final VoidCallback onClose;

  /// Emits the resulting file path (single image or assembled PDF).
  final ValueChanged<String>? onCaptured;

  /// Emits the assembled PDF file path and list of individual page paths.
  final void Function(String pdfPath, List<String> pages)? onCompleted;

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

enum _Phase { initializing, ready, denied, permanentlyDenied, error }

class _ScannerScreenState extends State<ScannerScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  _Phase _phase = _Phase.initializing;

  ScannerState _state = ScannerState.idle;
  bool _isAutoMode = true;
  bool _cropping = false;
  bool _buildingPdf = false;
  bool _captureFlash = false;
  bool _showPageSavedToast = false;
  int _flash = 0; // 0 = off, 1 = auto, 2 = on(torch)
  bool _blockBootstrap = false;
  bool _isBootstrapping = false;
  bool _isRequestingPermission = false;
  /// Prevents Continue / dispose from double-disposing the camera (iOS crash).
  bool _cameraTeardownStarted = false;
  bool _committing = false;

  // Multi-page session state
  final List<String> _scannedPages = [];
  /// Default is always full-color original. B&W / grayscale only if user picks them.
  ScanColorMode _activeFilter = ScanColorMode.original;

  // Live document detection — native Vision/OpenCV first, local fallback.
  final LiveDocumentDetector _localDetector = LiveDocumentDetector();
  final NativeDocumentEdgeService _nativeEdges = NativeDocumentEdgeService();
  /// iOS: package auto-capture gate (confidence + area + steadiness).
  final AutoCaptureAnalyzer _iosAuto = AutoCaptureAnalyzer(
    requiredSteadyFrames: 3,
    minConfidence: 0.42,
    minArea: 0.10,
    maxJitter: 0.042,
  );
  StreamSubscription<NativeEdgeEvent>? _nativeSub;
  final Stopwatch _throttle = Stopwatch();
  bool _streaming = false;
  bool _useNativeEdges = true;
  /// Native detector returns upright corners when rotation is applied.
  bool _nativeUpright = false;

  final ValueNotifier<List<Offset>?> _docCorners =
      ValueNotifier<List<Offset>?>(null);

  List<Offset>? _lastStableCorners;
  int _consecutiveMissedFrames = 0;
  /// Hold the last locked quad across brief detector drops (~1s at 85ms).
  static const int _kMaxToleratedMissed = 12;

  int _presentFrames = 0;
  int _absentFrames = 0;
  DateTime? _stableStart;
  bool _focusLocked = false;
  DateTime? _lastFocusMeterAt;

  static const int _kSampleIntervalMs = 70;
  static const int _kConfirmFrames = 2;
  /// Require several weak frames before dropping a lock - autofocus hunting
  /// routinely dips confidence for a sample or two without the page leaving.
  static const int _kLoseFrames = 5;
  /// Silhouette contrast detects blank pages; keep this reachable for them.
  static const double _kDetectConfidence = 0.34;
  static const double _kLoseConfidence = 0.22;
  static const Duration _kStableDuration = Duration(milliseconds: 420);
  /// Corner jitter below this (normalised) is treated as hand tremor and ignored.
  static const double _kCornerDeadband = 0.030;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _streaming = false;
    _nativeSub?.cancel();
    _nativeSub = null;
    // If Continue already detached the camera, do not dispose it again —
    // double CameraController.dispose() jetsams the iOS app.
    if (!_cameraTeardownStarted) {
      _cameraTeardownStarted = true;
      final controller = _controller;
      _controller = null;
      unawaited(_teardownCamera(controller));
      unawaited(_nativeEdges.dispose());
    }
    _docCorners.dispose();
    super.dispose();
  }

  Future<void> _teardownCamera(CameraController? controller) async {
    if (controller == null) return;
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (_) {}
    try {
      await controller.dispose();
    } catch (_) {}
  }

  /// True while shutter / crop / PDF work is in flight. iOS briefly reports
  /// [AppLifecycleState.inactive] during `takePicture` — tearing the camera
  /// down then kills the capture and looks like the scanner "went back".
  bool get _captureSessionBusy =>
      _blockBootstrap ||
      _cropping ||
      _buildingPdf ||
      _state == ScannerState.capturing ||
      _state == ScannerState.success;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isRequestingPermission || _captureSessionBusy) return;

    final isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    final controller = _controller;

    // iOS: ignore brief `inactive` (Control Center, shutter, banners).
    // Only release the camera when the app is actually backgrounded.
    if (state == AppLifecycleState.inactive && isIOS) {
      return;
    }

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _controller = null;
      _streaming = false;
      _teardownCamera(controller);
      if (mounted) setState(() => _state = ScannerState.idle);
    } else if (state == AppLifecycleState.resumed) {
      if (mounted && !_blockBootstrap && !_captureSessionBusy) {
        _bootstrap();
      }
    }
  }

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
      if (access == CameraAccess.permanentlyDenied) {
        setState(() => _phase = _Phase.permanentlyDenied);
        return;
      }
      if (access != CameraAccess.granted) {
        setState(() => _phase = _Phase.denied);
        return;
      }

      final cameras = await availableCameras();
      if (!mounted) return;
      if (cameras.isEmpty) {
        setState(() => _phase = _Phase.error);
        return;
      }

      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
      // High on both — sharp stills + Vision accuracy. Smoothness comes from
      // throttling detection, not from lowering capture resolution.
      final controller = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup:
            isIOS ? ImageFormatGroup.bgra8888 : ImageFormatGroup.yuv420,
      );

      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }

      try {
        await controller.setFlashMode(FlashMode.off);
      } catch (_) {}
      // Continuous autofocus. Never lock on iOS — locked AF blurs and stutters.
      try {
        await controller.setFocusMode(FocusMode.auto);
        await controller.setFocusPoint(const Offset(0.5, 0.5));
        await controller.setExposurePoint(const Offset(0.5, 0.5));
      } catch (_) {}
      _focusLocked = false;
      _iosAuto.reset();

      _controller = controller;
      setState(() => _phase = _Phase.ready);
      _startDetection();
    } catch (_) {
      if (mounted) setState(() => _phase = _Phase.error);
    } finally {
      _isBootstrapping = false;
    }
  }

  // ---- Real-time Document Detection ---------------------------------------

  Future<void> _startDetection() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _streaming) {
      return;
    }
    _localDetector.reset();
    _resetDetectionState();
    _throttle
      ..reset()
      ..start();

    _useNativeEdges = !_nativeEdges.shouldFallback;
    _nativeUpright = false;
    await _nativeSub?.cancel();
    _nativeSub = null;

    if (_useNativeEdges) {
      try {
        await _nativeEdges.start(
          sensitivity: DetectionSensitivity.balanced,
        );
        _nativeUpright = _nativeEdges.cornersAreUpright;
        _nativeSub = _nativeEdges.events.listen(_onNativeEdge);
      } catch (_) {
        _useNativeEdges = false;
        _nativeUpright = false;
      }
    }

    try {
      await controller.startImageStream(_onFrame);
      _streaming = true;
    } catch (_) {
      _streaming = false;
    }
  }

  Future<void> _stopDetection() async {
    final controller = _controller;
    _streaming = false;
    await _nativeSub?.cancel();
    _nativeSub = null;
    await _nativeEdges.stop();
    if (controller != null && controller.value.isStreamingImages) {
      try {
        await controller.stopImageStream();
      } catch (_) {}
    }
  }

  void _resetDetectionState() {
    _presentFrames = 0;
    _absentFrames = 0;
    _stableStart = null;
    _docCorners.value = null;
    _lastStableCorners = null;
    _consecutiveMissedFrames = 0;
    _iosAuto.reset();
    _nativeEdges.resetStabilizer();
    _setFocusLocked(false);
  }

  void _onNativeEdge(NativeEdgeEvent event) {
    if (!mounted || _phase != _Phase.ready) return;
    if (_state == ScannerState.capturing || _state == ScannerState.success) {
      return;
    }
    if (event.failed) {
      _useNativeEdges = false;
      _nativeUpright = false;
      return;
    }

    final isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    final corners = event.corners;
    final present =
        event.present && corners != null && corners.length == 4;

    // iOS: Vision-only + AutoCaptureAnalyzer (no local silhouette fighting).
    if (isIOS) {
      _handleIosNative(present ? corners : null, event.confidence);
      return;
    }

    final bool steady = present && event.confidence >= 0.45;
    final confidence = present
        ? (event.confidence < 0.55 ? 0.55 : event.confidence)
        : 0.0;
    _handleSignal(confidence, steady);
    if (present) {
      _applyCorners(corners);
    } else {
      _handleMissedDetection();
    }
  }

  /// iOS path: map Vision hits through [AutoCaptureAnalyzer] for Photos-like
  /// lock (confident + large enough + steady), and meter AF onto the page.
  void _handleIosNative(List<Offset>? corners, double confidence) {
    if (corners != null && corners.length == 4) {
      _consecutiveMissedFrames = 0;
      _applyCorners(corners);
      // Build DocumentCorners for the analyzer from the live outline.
      final dc = _iosDocumentCorners(corners, confidence);
      final status = _iosAuto.add(dc).status;
      switch (status) {
        case AutoCaptureStatus.searching:
          _enter(ScannerState.idle);
        case AutoCaptureStatus.detecting:
          if (_state != ScannerState.readyToScan) {
            _enter(ScannerState.documentDetected);
          }
        case AutoCaptureStatus.ready:
          _enter(ScannerState.readyToScan);
      }
      _meterOnDocumentThrottled();
    } else {
      _iosAuto.add(null);
      _handleMissedDetection();
      if (_consecutiveMissedFrames >= _kMaxToleratedMissed) {
        _enter(ScannerState.idle);
      }
    }
  }

  void _meterOnDocumentThrottled() {
    final now = DateTime.now();
    if (_lastFocusMeterAt != null &&
        now.difference(_lastFocusMeterAt!) < const Duration(milliseconds: 650)) {
      return;
    }
    _lastFocusMeterAt = now;
    unawaited(_meterOnDocument());
  }

  DocumentCorners _iosDocumentCorners(List<Offset> corners, double confidence) {
    return DocumentCorners.fromUnordered(
      [
        (x: corners[0].dx, y: corners[0].dy),
        (x: corners[1].dx, y: corners[1].dy),
        (x: corners[2].dx, y: corners[2].dy),
        (x: corners[3].dx, y: corners[3].dy),
      ],
      confidence: confidence.clamp(0.0, 1.0),
    );
  }

  void _onFrame(CameraImage image) {
    if (!mounted || _phase != _Phase.ready) return;
    if (_state == ScannerState.capturing || _state == ScannerState.success) {
      return;
    }

    final isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    // Native detectStream already rate-limits; only light-gate the push.
    final intervalMs = isIOS ? 90 : _kSampleIntervalMs;
    if (_throttle.elapsedMilliseconds < intervalMs) return;
    _throttle.reset();

    if (_useNativeEdges && !_nativeEdges.shouldFallback) {
      final controller = _controller;
      _nativeEdges.pushFrame(
        image,
        sensorOrientation: controller?.description.sensorOrientation ?? 90,
      );
      // iOS: Vision only — local silhouette was fighting borders and stuttering.
      // Android keeps native-only here too; local runs only on fallback below.
      return;
    }

    // Local silhouette fallback when native edge engine is unavailable.
    final signal = _localDetector.analyze(image);
    _handleSignal(signal.confidence, signal.steady);
    final rawCorners = signal.corners;
    if (rawCorners != null && rawCorners.length == 4) {
      _applyCorners(rawCorners);
    } else {
      _handleMissedDetection();
    }
  }

  void _applyCorners(List<Offset> rawCorners) {
    _consecutiveMissedFrames = 0;
    final shouldShow = switch (_state) {
      ScannerState.detecting ||
      ScannerState.documentDetected ||
      ScannerState.readyToScan =>
        true,
      _ => false,
    };

    if (!shouldShow) {
      _handleMissedDetection();
      return;
    }

    final ordered = LiveDocumentDetector.orderClockwise(rawCorners);
    final prev = _docCorners.value ?? _lastStableCorners;

    if (_state == ScannerState.readyToScan &&
        prev != null &&
        prev.length == 4) {
      final aligned = LiveDocumentDetector.alignCorners(prev, ordered);
      double totalDist = 0;
      for (int i = 0; i < 4; i++) {
        totalDist += (aligned[i] - prev[i]).distance;
      }
      if (totalDist / 4.0 < 0.065) {
        if (_docCorners.value == null) {
          _docCorners.value = prev;
        }
        return;
      }
      _stableStart = null;
      _setFocusLocked(false);
      _enter(ScannerState.documentDetected);
    }

    if (prev != null && prev.length == 4) {
      final aligned = LiveDocumentDetector.alignCorners(prev, ordered);
      double totalDist = 0;
      for (int i = 0; i < 4; i++) {
        totalDist += (aligned[i] - prev[i]).distance;
      }
      final avgDist = totalDist / 4.0;
      if (avgDist < _kCornerDeadband) {
        if (_docCorners.value == null) {
          _docCorners.value = prev;
        }
        return;
      }
      final double alpha = (avgDist * 2.0).clamp(0.12, 0.45);
      final smoothed = [
        for (int i = 0; i < 4; i++) Offset.lerp(prev[i], aligned[i], alpha)!,
      ];
      _docCorners.value = smoothed;
      _lastStableCorners = smoothed;
    } else {
      _docCorners.value = ordered;
      _lastStableCorners = ordered;
    }
  }

  void _handleMissedDetection() {
    _consecutiveMissedFrames++;
    // Keep the last stable quad on screen across transient drops so the
    // border does not blink off while the camera re-focuses.
    if (_consecutiveMissedFrames >= _kMaxToleratedMissed) {
      _docCorners.value = null;
    }
  }

  void _handleSignal(double confidence, bool steady) {
    final bool present = confidence >= _kDetectConfidence;
    final bool stillPresent = confidence >= _kLoseConfidence;

    switch (_state) {
      case ScannerState.idle:
      case ScannerState.detecting:
        if (present) {
          _presentFrames++;
          _absentFrames = 0;
          if (_presentFrames >= _kConfirmFrames) {
            _presentFrames = 0;
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
          _absentFrames++;
          if (_absentFrames >= _kLoseFrames) {
            _resetDetectionState();
            _enter(ScannerState.idle);
          }
          return;
        }
        _absentFrames = 0;
        if (steady) {
          _stableStart ??= DateTime.now();
          if (DateTime.now().difference(_stableStart!) >= _kStableDuration) {
            _enter(ScannerState.readyToScan);
          }
        } else {
          // Brief shake while locked: keep the ready outline. A real reframe
          // is handled in `_onFrame` via corner displacement.
          if (_state == ScannerState.readyToScan && _focusLocked) {
            return;
          }
          _stableStart = null;
          _enter(ScannerState.documentDetected);
        }

      case ScannerState.capturing:
      case ScannerState.success:
        break;
    }
  }

  void _enter(ScannerState next) {
    if (_state == next || !mounted) return;
    final prev = _state;
    final bool newDetection = next == ScannerState.documentDetected &&
        (prev == ScannerState.idle || prev == ScannerState.detecting);

    setState(() {
      _state = next;
    });

    final isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    if (newDetection) {
      HapticFeedback.selectionClick();
      // Meter on the page. Lock optics on Android only — iOS lock causes lag.
      _meterOnDocument();
      if (!isIOS) _setFocusLocked(true);
    } else if (next == ScannerState.readyToScan) {
      HapticFeedback.lightImpact();
      _meterOnDocument();
      if (!isIOS) _setFocusLocked(true);
      if (_isAutoMode &&
          _state != ScannerState.capturing &&
          _state != ScannerState.success) {
        _capturePressed();
      }
    } else if (next == ScannerState.idle || next == ScannerState.detecting) {
      if (!isIOS) _setFocusLocked(false);
    }
  }

  /// Point focus/exposure at the document centre (preview-normalised 0..1).
  Future<void> _meterOnDocument() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final corners = _docCorners.value ?? _lastStableCorners;
    Offset point = const Offset(0.5, 0.5);
    if (corners != null && corners.length == 4) {
      final cx =
          corners.map((c) => c.dx).reduce((a, b) => a + b) / corners.length;
      final cy =
          corners.map((c) => c.dy).reduce((a, b) => a + b) / corners.length;
      point = Offset(cx.clamp(0.05, 0.95), cy.clamp(0.05, 0.95));
    }
    try {
      await controller.setFocusPoint(point);
      await controller.setExposurePoint(point);
    } catch (_) {}
  }

  Future<void> _setFocusLocked(bool locked) async {
    if (_focusLocked == locked) return;
    // iOS: keep continuous AF — locking freezes/blurs and makes the UI stutter.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      await _meterOnDocument();
      _focusLocked = false;
      return;
    }
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      if (locked) {
        await _meterOnDocument();
        await controller.setFocusMode(FocusMode.locked);
      } else {
        await controller.setFocusMode(FocusMode.auto);
      }
      _focusLocked = locked;
    } catch (_) {
      // Some devices reject lock; leave autofocus running.
      _focusLocked = false;
    }
  }

  // ---- Controls & Actions -------------------------------------------------

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
        _state == ScannerState.capturing ||
        _captureSessionBusy) {
      return;
    }

    final isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

    // Freeze the border the user saw — require a real lock on iOS so we never
    // silently save a random desk photo as a "scan".
    final outline = List<Offset>.from(
      _docCorners.value ?? _lastStableCorners ?? const <Offset>[],
    );
    final captureOutline = outline.length == 4 ? outline : null;
    if (isIOS && captureOutline == null) {
      _snack('Point at a document until the blue border locks');
      return;
    }
    HapticFeedback.mediumImpact();
    if (captureOutline != null) {
      _docCorners.value = captureOutline;
      _lastStableCorners = captureOutline;
    }

    // Keep lifecycle from disposing the camera mid-shutter (critical on iOS).
    _blockBootstrap = true;

    // Settle continuous AF on the page BEFORE stopping the stream.
    await _meterOnDocument();
    if (isIOS) {
      await Future<void>.delayed(const Duration(milliseconds: 380));
    } else {
      await _setFocusLocked(true);
    }

    await _stopDetection();
    if (!mounted) {
      _blockBootstrap = false;
      return;
    }
    setState(() => _state = ScannerState.capturing);

    try {
      // iOS needs a gap after stopping the image stream or takePicture fails.
      await Future<void>.delayed(
        Duration(milliseconds: isIOS ? 280 : 120),
      );
      if (!mounted) return;
      if (!controller.value.isInitialized) {
        throw StateError('camera not ready');
      }

      setState(() => _captureFlash = true);
      final file = await controller.takePicture();
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() {
        _captureFlash = false;
        _state = ScannerState.success;
      });

      // Copy off the volatile camera temp path before heavy processing.
      final stablePath = await _persistCapture(file.path);

      setState(() => _cropping = true);
      String processed;
      try {
        final uprightLive = captureOutline == null
            ? null
            : [
                for (final c in captureOutline)
                  rotateSensorPoint(
                    c,
                    quarterTurns: _cropQuarterTurns,
                    mirror: controller.description.lensDirection ==
                        CameraLensDirection.front,
                  ),
              ];
        processed = await ScanCaptureProcessor.process(
          capturePath: stablePath,
          liveOutline: uprightLive,
        );
      } finally {
        if (mounted) setState(() => _cropping = false);
      }

      // Color by default. Only B&W / grayscale / enhanced when user picked them.
      if (_activeFilter != ScanColorMode.original) {
        processed =
            await ImageEnhancer.applyColorMode(processed, _activeFilter);
      }

      if (!mounted) return;

      setState(() {
        _scannedPages.add(processed);
        _showPageSavedToast = true;
      });

      // Hold the shutter checkmark + "saved" toast, stay on scanner.
      await Future<void>.delayed(const Duration(milliseconds: 650));
      if (!mounted) return;
      setState(() {
        _showPageSavedToast = false;
        _state = ScannerState.idle;
      });
      _blockBootstrap = false;
      if (_controller == null || !_controller!.value.isInitialized) {
        await _bootstrap();
      } else {
        _startDetection();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _captureFlash = false;
        _showPageSavedToast = false;
        _state = ScannerState.idle;
      });
      _docCorners.value = null;
      _blockBootstrap = false;
      _snack(AppLocalizations.of(context).t('captureFailed'));
      if (_controller == null || !_controller!.value.isInitialized) {
        await _bootstrap();
      } else {
        _startDetection();
      }
    }
  }

  /// Camera temp files can disappear on iOS once the session churns — copy first.
  Future<String> _persistCapture(String path) async {
    try {
      final src = File(path);
      if (!await src.exists()) return path;
      final dir = src.parent.path;
      final dest =
          '$dir/ino_capture_${DateTime.now().microsecondsSinceEpoch}.jpg';
      await src.copy(dest);
      return dest;
    } catch (_) {
      return path;
    }
  }

  int get _sensorQuarterTurns {
    final controller = _controller;
    if (controller == null) return 1;
    return outlineQuarterTurns(
      streamMatchesPreview:
          !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS,
      sensorOrientation: controller.description.sensorOrientation,
    );
  }

  /// Overlay / crop turns for the active detector coordinate space.
  int get _overlayQuarterTurns =>
      (_useNativeEdges && _nativeUpright) ? 0 : _sensorQuarterTurns;

  int get _cropQuarterTurns => _overlayQuarterTurns;

  Future<void> _galleryPressed() async {
    setState(() => _blockBootstrap = true);
    try {
      final path = await GalleryImportService.instance.pickImage();
      if (!mounted) return;
      if (path == null) {
        setState(() => _blockBootstrap = false);
        return;
      }
      var processed = path;
      if (_activeFilter != ScanColorMode.original) {
        processed = await ImageEnhancer.applyColorMode(path, _activeFilter);
      }
      setState(() {
        _scannedPages.add(processed);
        _blockBootstrap = false;
      });
      _snack('Page ${_scannedPages.length} imported');
    } catch (_) {
      setState(() => _blockBootstrap = false);
    }
  }

  void _retakeLastPage() {
    if (_scannedPages.isEmpty) return;
    setState(() {
      final removed = _scannedPages.removeLast();
      try {
        File(removed).deleteSync();
      } catch (_) {}
    });
    HapticFeedback.selectionClick();
    _snack('Last page discarded. Ready to retake.');
    _startDetection();
  }

  void _showPagesManager() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1B232D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final height = MediaQuery.sizeOf(ctx).height * 0.72;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: SizedBox(
                height: height,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Scanned Pages (${_scannedPages.length})',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _scannedPages.isEmpty
                                ? null
                                : () {
                                    Navigator.of(ctx).pop();
                                    _retakeLastPage();
                                  },
                            icon: const Icon(Icons.refresh_rounded,
                                size: 18, color: Colors.amber),
                            label: const Text(
                              'Retake Last',
                              style: TextStyle(
                                  color: Colors.amber,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: _scannedPages.isEmpty
                            ? const Center(
                                child: Text(
                                  'No pages yet',
                                  style: TextStyle(color: Colors.white54),
                                ),
                              )
                            : GridView.builder(
                                physics: const BouncingScrollPhysics(
                                  parent: AlwaysScrollableScrollPhysics(),
                                ),
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  mainAxisSpacing: 10,
                                  crossAxisSpacing: 10,
                                  childAspectRatio: 0.72,
                                ),
                                itemCount: _scannedPages.length,
                                itemBuilder: (context, index) {
                                  final page = _scannedPages[index];
                                  return Stack(
                                    children: [
                                      Positioned.fill(
                                        child: Container(
                                          decoration: BoxDecoration(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            border: Border.all(
                                                color: ScanColors.accent),
                                          ),
                                          clipBehavior: Clip.antiAlias,
                                          child: Image.file(
                                            File(page),
                                            fit: BoxFit.cover,
                                            cacheWidth: 240,
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        top: 6,
                                        left: 6,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.black87,
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            'P${index + 1}',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        top: 4,
                                        right: 4,
                                        child: GestureDetector(
                                          onTap: () {
                                            setState(() {
                                              final removed =
                                                  _scannedPages.removeAt(index);
                                              try {
                                                File(removed).deleteSync();
                                              } catch (_) {}
                                            });
                                            setSheetState(() {});
                                            if (_scannedPages.isEmpty) {
                                              Navigator.of(ctx).pop();
                                            }
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.all(4),
                                            decoration: const BoxDecoration(
                                              color: Colors.redAccent,
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(
                                              Icons.close_rounded,
                                              size: 14,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: ScanColors.accent,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: const Text(
                            'Back to Camera',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showFilterSelector() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1B232D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Document Filters',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Default is Color (Original). B&W only if you pick it.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _filterChip(ScanColorMode.original, 'Color', Icons.image_rounded),
                  _filterChip(ScanColorMode.enhanced, 'Enhanced', Icons.auto_fix_high_rounded),
                  _filterChip(ScanColorMode.blackWhite, 'B & W', Icons.contrast_rounded),
                  _filterChip(ScanColorMode.grayscale, 'Grayscale', Icons.filter_b_and_w_rounded),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filterChip(ScanColorMode mode, String label, IconData icon) {
    final active = _activeFilter == mode;
    return GestureDetector(
      onTap: () {
        setState(() => _activeFilter = mode);
        Navigator.of(context).pop();
        _snack('Filter: $label');
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: active ? ScanColors.accent : Colors.white.withValues(alpha: 0.1),
              shape: BoxShape.circle,
              border: Border.all(
                color: active ? Colors.white : Colors.transparent,
                width: 2,
              ),
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              color: active ? ScanColors.accentDeep : Colors.white70,
              fontSize: 12,
              fontWeight: active ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  /// Triggered by the blue checkmark button:
  /// Combines all scanned pages into a single PDF and opens PDF Preview
  Future<void> _finishScanning() async {
    if (_scannedPages.isEmpty || _committing) return;
    HapticFeedback.mediumImpact();

    final isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    if (isIOS) {
      // Freeze camera and detection immediately on iPhone when tapping Done
      await _stopDetection();
    }

    _blockBootstrap = true;
    setState(() => _buildingPdf = true);

    try {
      // Freeze camera before heavy PDF work — prevents iOS jetsam/exit.
      await _stopDetection();
      final pdfPath = await ScanPdfService.instance.buildPdf(_scannedPages);
      if (!mounted) return;
      setState(() => _buildingPdf = false);

      // Preview pops with the PDF path on Continue; null = back / add pages.
      final committed = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (ctx) => ScanPdfPreviewScreen(
            pdfPath: pdfPath,
            pages: List<String>.from(_scannedPages),
            onContinue: (committedPdf) {
              if (ctx.mounted) Navigator.of(ctx).pop(committedPdf);
            },
            onAddMorePages: () {
              _blockBootstrap = false;
              if (_controller == null || !_controller!.value.isInitialized) {
                _bootstrap();
              } else {
                _startDetection();
              }
            },
          ),
        ),
      );

      if (committed != null && mounted) {
        await _safeCommitResult(committed);
        return;
      }
      // Returned from preview without continuing — allow camera again.
      if (mounted) _blockBootstrap = false;
    } catch (e) {
      if (!mounted) return;
      setState(() => _buildingPdf = false);
      _blockBootstrap = false;
      _snack('Failed to generate PDF: $e');
      if (_controller == null || !_controller!.value.isInitialized) {
        _bootstrap();
      } else {
        _startDetection();
      }
    }
  }

  /// Leave the scanner without awaiting camera dispose on the UI path —
  /// awaiting dispose then popping raced and killed the iOS process.
  Future<void> _safeCommitResult(String pdfPath) async {
    if (!mounted || _committing) return;
    _committing = true;
    _blockBootstrap = true;

    final pages = List<String>.from(_scannedPages);
    final onCompleted = widget.onCompleted;
    final onCaptured = widget.onCaptured;

    final cam = _controller;
    _controller = null;
    _streaming = false;
    if (!_cameraTeardownStarted) {
      _cameraTeardownStarted = true;
      unawaited(_nativeSub?.cancel());
      _nativeSub = null;
      // Hardware teardown AFTER we navigate away (next event-loop turn).
      scheduleMicrotask(() async {
        try {
          await _nativeEdges.stop();
        } catch (_) {}
        try {
          await _teardownCamera(cam);
        } catch (_) {}
        try {
          await _nativeEdges.dispose();
        } catch (_) {}
      });
    }

    if (!mounted) return;
    try {
      if (onCompleted != null) {
        onCompleted(pdfPath, pages);
      } else if (onCaptured != null) {
        onCaptured(pdfPath);
      } else if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop(pdfPath);
      }
    } catch (_) {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop(pdfPath);
      }
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF1E293B),
      ),
    );
  }

  String _statusBubbleText(AppLocalizations l10n) {
    if (_scannedPages.isNotEmpty) {
      if (_state == ScannerState.readyToScan) {
        return _isAutoMode ? 'Holding steady... auto-capturing' : 'Hold steady to capture';
      }
      if (_state == ScannerState.documentDetected) {
        return 'Document detected • Page ${_scannedPages.length + 1}';
      }
      return '${_scannedPages.length} ${_scannedPages.length == 1 ? 'page' : 'pages'} scanned • Position next page or tap Done';
    }
    if (_state == ScannerState.readyToScan) {
      return _isAutoMode ? 'Holding steady... auto-capturing' : 'Hold steady to capture';
    }
    if (_state == ScannerState.documentDetected) {
      return 'Document detected';
    }
    if (_state == ScannerState.success) {
      return 'Page captured';
    }
    return 'Position document within blue frame';
  }

  // ---- Build --------------------------------------------------------------

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
            _documentHighlight(),
            // Shutter white-flash (Photos / Lens style)
            IgnorePointer(
              child: AnimatedOpacity(
                opacity: _captureFlash ? 1 : 0,
                duration: const Duration(milliseconds: 70),
                child: const ColoredBox(color: Colors.white),
              ),
            ),
            if (_cropping) const _CroppingScrim(),
            if (_buildingPdf) const _BuildingPdfScrim(),
            // "Page saved" confirmation toast
            if (_showPageSavedToast)
              SafeArea(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 72),
                    child: _PageSavedToast(pageNumber: _scannedPages.length),
                  ),
                ),
              ),
            // Top Controls Bar
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
                          Row(
                            children: [
                              _CleanIconButton(
                                icon: Icons.tune_rounded,
                                onTap: _showFilterSelector,
                                tooltip: 'Filters',
                              ),
                              const SizedBox(width: 8),
                              _CleanIconButton(
                                icon: _flashIcon,
                                onTap: _cycleFlash,
                                tooltip: '${l10n.t('flash')}: $_flashLabel',
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _InstructionPill(
                        message: _statusBubbleText(l10n),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Bottom Controls Bar
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.95),
                      Colors.black.withValues(alpha: 0.7),
                      Colors.transparent,
                    ],
                  ),
                ),
                padding: EdgeInsets.fromLTRB(24, 20, 24, bottomInset > 0 ? bottomInset + 10 : 26),
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
                      scannedPages: _scannedPages,
                      onTapThumbnail: _showPagesManager,
                      onRetake: _retakeLastPage,
                      onFinishScanning: _finishScanning,
                      onToggleFilter: _showFilterSelector,
                      activeFilter: _activeFilter,
                    ),
                    const SizedBox(height: 16),
                    _AutoManualToggle(
                      isAuto: _isAutoMode,
                      onChanged: (isAuto) => setState(() => _isAutoMode = isAuto),
                    ),
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
          icon: Icons.settings_rounded,
          title: l10n.t('cameraPermissionRequired'),
          message: l10n.t('cameraAccessSettings'),
          primaryLabel: l10n.t('openSettings'),
          onPrimary: () async {
            setState(() => _blockBootstrap = true);
            await CameraPermissionService.instance.openSettings();
            setState(() => _blockBootstrap = false);
          },
        );
      case _Phase.error:
        return _StatusView(
          icon: Icons.error_outline_rounded,
          title: l10n.t('couldNotStartCamera'),
          message: l10n.t('cameraInitErrorMessage'),
          primaryLabel: l10n.t('tryAgain'),
          onPrimary: _bootstrap,
        );
    }
  }

  Widget _cameraViewport() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.shrink();
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (details) {
        final box = context.findRenderObject() as RenderBox?;
        if (box == null || !box.hasSize) return;
        final local = details.localPosition;
        final nx = (local.dx / box.size.width).clamp(0.05, 0.95);
        final ny = (local.dy / box.size.height).clamp(0.05, 0.95);
        unawaited(_focusAt(Offset(nx, ny)));
      },
      child: _CoverCameraPreview(controller: controller),
    );
  }

  Future<void> _focusAt(Offset normalized) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      await controller.setFocusMode(FocusMode.auto);
      await controller.setFocusPoint(normalized);
      await controller.setExposurePoint(normalized);
    } catch (_) {}
  }

  Widget _documentHighlight() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.shrink();
    }
    return DocumentHighlight(
      corners: _docCorners,
      state: _overlayState,
      sourceSize: _previewDisplaySize(controller),
      quarterTurns: _overlayQuarterTurns,
      mirror: controller.description.lensDirection == CameraLensDirection.front,
    );
  }

  Size _previewDisplaySize(CameraController controller) {
    final preview = controller.value.previewSize;
    if (preview == null) return const Size(1, 1);
    // Matches `_CoverCameraPreview`'s swapped FittedBox when the overlay is
    // already in upright space, or when the sensor buffer needs a 90° turn.
    final turns = _overlayQuarterTurns;
    if (_useNativeEdges && _nativeUpright) {
      return Size(preview.height, preview.width);
    }
    return (turns % 2 == 1)
        ? Size(preview.height, preview.width)
        : Size(preview.width, preview.height);
  }

  ScanOverlayState get _overlayState => switch (_state) {
        ScannerState.detecting ||
        ScannerState.documentDetected =>
          ScanOverlayState.detected,
        ScannerState.readyToScan => ScanOverlayState.ready,
        _ => ScanOverlayState.idle,
      };

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

class _CoverCameraPreview extends StatelessWidget {
  const _CoverCameraPreview({required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return ClipRect(
          child: SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: controller.value.previewSize?.height ?? 1,
                height: controller.value.previewSize?.width ?? 1,
                child: CameraPreview(controller),
              ),
            ),
          ),
        );
      },
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
    final button = Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(
            icon,
            color: Colors.white,
            size: 22,
          ),
        ),
      ),
    );

    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

class _PageSavedToast extends StatelessWidget {
  const _PageSavedToast({required this.pageNumber});

  final int pageNumber;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          color: ScanColors.green,
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: ScanColors.green.withValues(alpha: 0.40),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_rounded, size: 18, color: Colors.white),
            const SizedBox(width: 8),
            Text(
              'Page $pageNumber saved',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CroppingScrim extends StatelessWidget {
  const _CroppingScrim();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.55),
          child: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InoLoader(size: 36, color: ScanColors.accent),
                SizedBox(height: 14),
                Text(
                  'Saving color scan…',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
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

class _BuildingPdfScrim extends StatelessWidget {
  const _BuildingPdfScrim();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.75),
          child: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InoLoader(size: 40, color: ScanColors.accent),
                SizedBox(height: 16),
                Text(
                  'Assembling High-Quality PDF…',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
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

class _InstructionPill extends StatelessWidget {
  const _InstructionPill({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: ScanColors.accent.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: Text(
          message,
          key: ValueKey(message),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.2,
          ),
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
        color: const Color(0xFF242B35),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSegment(
            label: 'Manual',
            active: !isAuto,
            onTap: () => onChanged(false),
          ),
          _buildSegment(
            label: 'Auto capture',
            active: isAuto,
            onTap: () => onChanged(true),
          ),
        ],
      ),
    );
  }

  Widget _buildSegment({
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: active ? ScanColors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(17),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
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
          if (spinner)
            const InoLoader(size: 36, color: ScanColors.accent)
          else
            Icon(icon, size: 48, color: Colors.white54),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusView extends StatelessWidget {
  const _StatusView({
    required this.icon,
    required this.title,
    required this.message,
    required this.primaryLabel,
    required this.onPrimary,
  });

  final IconData icon;
  final String title;
  final String message;
  final String primaryLabel;
  final VoidCallback onPrimary;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Colors.white70),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: ScanColors.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: onPrimary,
              child: Text(primaryLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
