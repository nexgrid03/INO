import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../models/scan_models.dart';
import '../../services/camera_permission_service.dart';
import '../../services/document_crop_service.dart';
import '../../services/gallery_import_service.dart';
import '../../services/image_enhancer.dart';
import '../../services/live_document_detector.dart';
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
  int _flash = 0; // 0 = off, 1 = auto, 2 = on(torch)
  bool _blockBootstrap = false;
  bool _isBootstrapping = false;
  bool _isRequestingPermission = false;

  // Multi-page session state
  final List<String> _scannedPages = [];
  ScanColorMode _activeFilter = ScanColorMode.original;

  // Live document detection
  final LiveDocumentDetector _detector = LiveDocumentDetector();
  final Stopwatch _throttle = Stopwatch();
  bool _streaming = false;

  final ValueNotifier<List<Offset>?> _docCorners =
      ValueNotifier<List<Offset>?>(null);

  List<Offset>? _lastStableCorners;
  int _consecutiveMissedFrames = 0;
  static const int _kMaxToleratedMissed = 4;

  int _presentFrames = 0;
  DateTime? _stableStart;

  static const int _kSampleIntervalMs = 85;
  static const int _kConfirmFrames = 2;
  static const double _kDetectConfidence = 0.45;
  static const double _kLoseConfidence = 0.30;
  static const Duration _kStableDuration = Duration(milliseconds: 650);

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
    _streaming = false;
    _teardownCamera(controller);
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
    _detector.reset();
    _resetDetectionState();
    _throttle
      ..reset()
      ..start();
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
    if (controller != null && controller.value.isStreamingImages) {
      try {
        await controller.stopImageStream();
      } catch (_) {}
    }
  }

  void _resetDetectionState() {
    _presentFrames = 0;
    _stableStart = null;
    _docCorners.value = null;
    _lastStableCorners = null;
    _consecutiveMissedFrames = 0;
  }

  void _onFrame(CameraImage image) {
    if (!mounted || _phase != _Phase.ready) return;
    if (_state == ScannerState.capturing || _state == ScannerState.success) {
      return;
    }
    if (_throttle.elapsedMilliseconds < _kSampleIntervalMs) return;
    _throttle.reset();

    final signal = _detector.analyze(image);
    _handleSignal(signal.confidence, signal.steady);

    final rawCorners = signal.corners;
    if (rawCorners != null && rawCorners.length == 4) {
      _consecutiveMissedFrames = 0;
      final shouldShow = switch (_state) {
        ScannerState.detecting ||
        ScannerState.documentDetected ||
        ScannerState.readyToScan =>
          true,
        _ => false,
      };

      if (shouldShow) {
        final ordered = LiveDocumentDetector.orderClockwise(rawCorners);
        final prev = _docCorners.value;
        if (prev != null && prev.length == 4) {
          // Align corners to prevent index rotation / cross-interpolation
          final aligned = LiveDocumentDetector.alignCorners(prev, ordered);

          // Calculate average corner displacement
          double totalDist = 0;
          for (int i = 0; i < 4; i++) {
            totalDist += (aligned[i] - prev[i]).distance;
          }
          final avgDist = totalDist / 4.0;

          // DEADBAND: If movement is tiny (< 2.0% of screen), hand jitter is ignored!
          // Pin firmly to the page!
          if (avgDist < 0.020) {
            // Keep exactly on the page, rock-solid
            return;
          }

          // Smooth glide: adaptive alpha
          final double alpha = (avgDist * 2.5).clamp(0.16, 0.40);
          final smoothed = [
            for (int i = 0; i < 4; i++)
              Offset.lerp(prev[i], aligned[i], alpha)!,
          ];
          _docCorners.value = smoothed;
          _lastStableCorners = smoothed;
        } else {
          _docCorners.value = ordered;
          _lastStableCorners = ordered;
        }
      } else {
        _handleMissedDetection();
      }
    } else {
      _handleMissedDetection();
    }
  }

  void _handleMissedDetection() {
    _consecutiveMissedFrames++;
    // Hold the existing stable quad for up to ~350ms across transient drops
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
          _resetDetectionState();
          _enter(ScannerState.idle);
          return;
        }
        if (steady) {
          _stableStart ??= DateTime.now();
          if (DateTime.now().difference(_stableStart!) >= _kStableDuration) {
            _enter(ScannerState.readyToScan);
          }
        } else {
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
        _state == ScannerState.capturing) {
      return;
    }
    HapticFeedback.mediumImpact();

    final outline = _docCorners.value ?? _lastStableCorners;
    await _stopDetection();
    if (!mounted) return;
    setState(() => _state = ScannerState.capturing);

    try {
      final file = await controller.takePicture();
      if (!mounted) return;
      HapticFeedback.lightImpact();
      setState(() => _state = ScannerState.success);

      // Automatically crop and align document edges
      var processed = await _cropToOutline(file.path, outline);

      // Apply active filter if one was selected
      if (_activeFilter != ScanColorMode.original) {
        processed = await ImageEnhancer.applyColorMode(processed, _activeFilter);
      }

      if (!mounted) return;

      setState(() {
        _scannedPages.add(processed);
        _state = ScannerState.idle;
      });

      _snack('Page ${_scannedPages.length} scanned');

      // Resume detection for multi-page scanning session
      _startDetection();
    } catch (e) {
      if (!mounted) return;
      setState(() => _state = ScannerState.idle);
      _docCorners.value = null;
      _snack(AppLocalizations.of(context).t('captureFailed'));
      _startDetection();
    }
  }

  Future<String> _cropToOutline(String path, List<Offset>? outline) async {
    if (outline == null || outline.length != 4) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      return path;
    }
    final controller = _controller;
    final upright = [
      for (final c in outline)
        rotateSensorPoint(
          c,
          quarterTurns: _sensorQuarterTurns,
          mirror: controller?.description.lensDirection ==
              CameraLensDirection.front,
        ),
    ];
    setState(() => _cropping = true);
    try {
      final cropped = await DocumentCropService.rectify(path, upright);
      return cropped ?? path;
    } finally {
      if (mounted) setState(() => _cropping = false);
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
      backgroundColor: const Color(0xFF1B232D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Scanned Pages (${_scannedPages.length})',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          _retakeLastPage();
                        },
                        icon: const Icon(Icons.refresh_rounded, size: 18, color: Colors.amber),
                        label: const Text(
                          'Retake Last',
                          style: TextStyle(color: Colors.amber, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 140,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _scannedPages.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 12),
                      itemBuilder: (context, index) {
                        final page = _scannedPages[index];
                        return Stack(
                          children: [
                            Container(
                              width: 100,
                              height: 140,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: ScanColors.accent),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Image.file(File(page), fit: BoxFit.cover),
                            ),
                            Positioned(
                              top: 6,
                              left: 6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.black87,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'P${index + 1}',
                                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 4,
                              right: 4,
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    final removed = _scannedPages.removeAt(index);
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
                                  child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: ScanColors.accent,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('Back to Camera', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
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
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _filterChip(ScanColorMode.original, 'Original', Icons.image_rounded),
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
    if (_scannedPages.isEmpty) return;
    HapticFeedback.mediumImpact();
    setState(() => _buildingPdf = true);

    try {
      final pdfPath = await ScanPdfService.instance.buildPdf(_scannedPages);
      if (!mounted) return;
      setState(() => _buildingPdf = false);

      // Open PDF Preview screen
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (ctx) => ScanPdfPreviewScreen(
            pdfPath: pdfPath,
            pages: List<String>.from(_scannedPages),
            onContinue: (committedPdf) {
              Navigator.of(ctx).pop(); // pop preview
              _commitResult(committedPdf);
            },
            onAddMorePages: () {
              // resume camera
              _startDetection();
            },
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _buildingPdf = false);
      _snack('Failed to generate PDF: $e');
    }
  }

  void _commitResult(String pdfPath) {
    if (widget.onCompleted != null) {
      widget.onCompleted!(pdfPath, List<String>.from(_scannedPages));
    } else if (widget.onCaptured != null) {
      widget.onCaptured!(pdfPath);
    } else {
      Navigator.of(context).pop(pdfPath);
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
            if (_cropping) const _CroppingScrim(),
            if (_buildingPdf) const _BuildingPdfScrim(),
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
    return _CoverCameraPreview(controller: controller);
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
      quarterTurns: _sensorQuarterTurns,
      mirror: controller.description.lensDirection == CameraLensDirection.front,
    );
  }

  Size _previewDisplaySize(CameraController controller) {
    final preview = controller.value.previewSize;
    if (preview == null) return const Size(1, 1);
    final turns = _sensorQuarterTurns;
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

class _CroppingScrim extends StatelessWidget {
  const _CroppingScrim();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.6),
          child: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InoLoader(size: 36, color: ScanColors.accent),
                SizedBox(height: 14),
                Text(
                  'Aligning edges…',
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
