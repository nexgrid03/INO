import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io' show Platform;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../models/payment_qr.dart';
import '../../services/camera_permission_service.dart';
import '../../services/screen_security_service.dart';
import '../../services/secure_clipboard.dart';
import '../../services/deep_link_service.dart';
import '../../services/qr_crop_service.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/ino_back_button.dart';
import '../../widgets/scan/payment_app_sheet.dart';
import '../../widgets/scan/qr_scan_frame.dart';
import '../share/shared_documents_screen.dart';
import '../share/view_once_viewer_screen.dart';
import '../../widgets/common/ino_loader.dart';

/// Live QR scanner.
///
/// The reason this exists is payments: a scanned **UPI / BharatQR** code opens a
/// picker of the payment apps actually installed on the device (Google Pay,
/// PhonePe, Paytm, …) instead of silently handing the URI to whatever the OS
/// picked. Everything else a QR can hold is still handled sensibly - INO share
/// links open in-app, web links are offered to the browser behind a
/// confirmation, and anything else is shown as text.
///
/// Frames come from the [camera] plugin's image stream and are read by ML Kit's
/// barcode scanner - the same ML Kit stack the document scanner and OCR already
/// use, so no second vision pipeline enters the build.
class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

enum _Phase { initializing, ready, denied, permanentlyDenied, error }

class _QrScannerScreenState extends State<QrScannerScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  CameraDescription? _camera;
  _Phase _phase = _Phase.initializing;

  final BarcodeScanner _scanner =
      BarcodeScanner(formats: [BarcodeFormat.qrCode]);

  bool _streaming = false;
  bool _torch = false;

  /// True while a frame is inside ML Kit. Frames that arrive meanwhile are
  /// dropped - queueing them would build an unbounded backlog on a slow device.
  bool _analysing = false;

  /// Set the moment a code is accepted, so the stream can't fire the handler a
  /// second time while the sheet is opening.
  bool _handled = false;

  /// True while the gallery picker / decode is in flight, so the upload button
  /// can show progress and refuse a second tap.
  bool _picking = false;

  final Stopwatch _throttle = Stopwatch();

  /// ~8 reads/sec. Fast enough to feel instant, cheap enough not to heat the
  /// device or starve the preview.
  static const int _kSampleIntervalMs = 120;

  /// Maps the device's UI orientation to the rotation ML Kit needs on Android.
  static const Map<DeviceOrientation, int> _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  @override
  void initState() {
    super.initState();
    ScreenSecurityService.instance.enable();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  bool _isBootstrapping = false;
  bool _isRequestingPermission = false;

  @override
  void dispose() {
    ScreenSecurityService.instance.disable();
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    _scanner.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isRequestingPermission) {
      // The OS permission dialog temporarily pauses the app. Do not dispose the camera.
      return;
    }
    final controller = _controller;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      // Free the camera while backgrounded (also covers the moment a payment
      // app takes over the foreground).
      _controller = null;
      _streaming = false;
      controller?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      if (mounted) _bootstrap();
    }
  }

  // ---- Permissions + camera -------------------------------------------------

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
      _camera = back;

      final oldController = _controller;
      _controller = null;
      try {
        await oldController?.dispose();
      } catch (_) {}

      final controller = CameraController(
        back,
        // A QR needs far less resolution than a document scan, and a smaller
        // frame is markedly faster to hand to ML Kit.
        ResolutionPreset.high,
        enableAudio: false,
        // ML Kit reads NV21 on Android and BGRA8888 on iOS. Anything else has to
        // be converted per frame, which is exactly the cost worth avoiding here.
        imageFormatGroup:
            Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
      );
      await controller.initialize();
      await controller.setFlashMode(FlashMode.off);
      if (!mounted) {
        try {
          await controller.dispose();
        } catch (_) {}
        return;
      }
      _controller = controller;
      setState(() {
        _torch = false;
        _handled = false;
        _phase = _Phase.ready;
      });
      await _startStream();
    } catch (_) {
      if (mounted) setState(() => _phase = _Phase.error);
    }
  }

  Future<void> _startStream() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _streaming) {
      return;
    }
    _throttle
      ..reset()
      ..start();
    try {
      await controller.startImageStream(_onFrame);
      _streaming = true;
      if (kDebugMode) debugPrint('[QR] image stream started');
    } catch (e) {
      if (kDebugMode) debugPrint('[QR] image stream FAILED to start: $e');
      // Streaming unsupported on this device - the screen still shows the
      // preview, but nothing can be read, so say so rather than pretending.
      _streaming = false;
      if (mounted) setState(() => _phase = _Phase.error);
    }
  }

  // ---- Reading --------------------------------------------------------------

  /// Rate-limited diagnostic. Frames arrive several times a second, so this
  /// logs at most once a second to keep the log readable.
  DateTime _lastDiag = DateTime.fromMillisecondsSinceEpoch(0);
  void _diag(String message) {
    final now = DateTime.now();
    if (now.difference(_lastDiag).inMilliseconds < 1000) return;
    _lastDiag = now;
    // debugPrint, not developer.log: only stdout reaches `adb logcat`, and
    // developer.log goes to the VM service instead - invisible on-device.
    if (kDebugMode) debugPrint('[QR] $message');
  }

  Future<void> _onFrame(CameraImage image) async {
    if (_handled || _analysing || !mounted) return;
    if (_throttle.elapsedMilliseconds < _kSampleIntervalMs) return;
    _throttle.reset();

    final input = _toInputImage(image);
    if (input == null) {
      _diag('frame REJECTED fmt=${image.format.raw} planes=${image.planes.length}');
      return;
    }

    _analysing = true;
    try {
      final codes = await _scanner.processImage(input);
      _diag('frame ok fmt=${image.format.raw} planes=${image.planes.length} '
          '${image.width}x${image.height} → ${codes.length} code(s)');
      if (!mounted || _handled) return;
      for (final code in codes) {
        final raw = code.rawValue;
        if (raw != null && raw.trim().isNotEmpty) {
          await _onCode(raw);
          return;
        }
      }
    } catch (e) {
      developer.log('barcode read failed: $e', name: 'qr-scan');
    } finally {
      _analysing = false;
    }
  }

  /// Converts a camera frame into the buffer ML Kit expects, or null when the
  /// frame is in a layout we did not ask for (in which case it is simply
  /// skipped - the next one usually is).
  InputImage? _toInputImage(CameraImage image) {
    final camera = _camera;
    final controller = _controller;
    if (camera == null || controller == null) return null;

    final InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(camera.sensorOrientation);
    } else {
      final compensation =
          _orientations[controller.value.deviceOrientation] ?? 0;
      final degrees = camera.lensDirection == CameraLensDirection.front
          ? (camera.sensorOrientation + compensation) % 360
          : (camera.sensorOrientation - compensation + 360) % 360;
      rotation = InputImageRotationValue.fromRawValue(degrees);
    }
    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;
    // Both formats we request are single-plane; a multi-plane frame means the
    // request was not honoured and the bytes would be misread.
    if (image.planes.length != 1) return null;
    final plane = image.planes.first;

    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  // ---- Acting on a code -----------------------------------------------------

  Future<void> _onCode(String raw) async {
    _handled = true;
    HapticFeedback.mediumImpact();
    await _stopStream();
    if (!mounted) return;

    final scanned = ScannedQr.classify(raw);
    // Deliberately logs the KIND only. The payload of a payment QR is a payee's
    // VPA - never write that to the device log.
    if (kDebugMode) debugPrint('[QR] code detected kind=${scanned.kind}');

    switch (scanned.kind) {
      case ScannedQrKind.payment:
        await showPaymentAppSheet(context, scanned.payment!);
      case ScannedQrKind.inoShare:
        await _openInoShare(scanned.raw);
        return; // the viewer replaces this screen - don't resume scanning
      case ScannedQrKind.link:
        await _confirmOpenLink(scanned.raw);
      case ScannedQrKind.text:
        await _showText(scanned.raw);
    }

    // Back from the sheet without leaving the scanner - start looking again so
    // the user can scan the next code without re-entering the screen.
    if (!mounted) return;
    _handled = false;
    await _startStream();
  }

  /// Reads a QR out of a photo in the gallery instead of off the camera.
  ///
  /// Payment QRs very often arrive as an image rather than something to point a
  /// camera at — a shopkeeper WhatsApps their code, a biller emails one, or the
  /// user screenshots it from another app. Without this the only way to pay was
  /// to print the code or open it on a second screen.
  ///
  /// Reuses [QrCropService], which already runs ML Kit over a picked file and
  /// hands back the decoded payload, so this adds no new vision pipeline. The
  /// decoded string goes through the very same [_onCode] the camera path uses,
  /// so an uploaded payment QR reaches the payment-app picker by exactly the
  /// route a scanned one does.
  Future<void> _pickFromGallery() async {
    if (_picking || _handled) return;
    setState(() => _picking = true);
    // Free the camera while the OS picker is in front of us.
    await _stopStream();

    String? path;
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        // The code only needs to be legible, not full resolution.
        maxWidth: 2000,
        maxHeight: 2000,
      );
      path = file?.path;
    } catch (_) {
      path = null;
    }

    if (!mounted) return;

    if (path == null) {
      // Cancelled the picker — put the scanner back the way it was.
      setState(() => _picking = false);
      if (_phase == _Phase.ready) await _startStream();
      return;
    }

    String? payload;
    try {
      final result = await QrCropService.instance.cropFromFile(path);
      payload = result?.payload;
    } catch (_) {
      payload = null;
    }

    if (!mounted) return;
    setState(() => _picking = false);

    if (payload == null || payload.isEmpty) {
      _toast(AppLocalizations.of(context).t('qrNotFoundInImage'));
      if (_phase == _Phase.ready) await _startStream();
      return;
    }

    await _onCode(payload);
  }

  Future<void> _stopStream() async {
    final controller = _controller;
    if (controller == null || !_streaming) return;
    _streaming = false;
    try {
      await controller.stopImageStream();
    } catch (_) {
      // Already stopped / disposed - nothing to undo.
    }
  }

  /// An INO share QR belongs in the in-app viewer, not a browser. Reuses the
  /// same token parsing the deep-link handler uses, so a scanned link and a
  /// tapped link behave identically.
  Future<void> _openInoShare(String raw) async {
    final uri = Uri.tryParse(raw);
    final viewOnce = DeepLinkService.parseViewOnceToken(uri);
    final shareId = viewOnce == null ? DeepLinkService.parseShareId(uri) : null;
    if (!mounted) return;

    if (viewOnce != null) {
      await Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => ViewOnceViewerScreen(token: viewOnce),
      ));
    } else if (shareId != null) {
      await Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => SharedDocumentsScreen(token: shareId),
      ));
    } else {
      // Looked like a share link but carried no token - treat it as a link.
      await _confirmOpenLink(raw);
      if (!mounted) return;
      _handled = false;
      await _startStream();
    }
  }

  Future<void> _confirmOpenLink(String url) async {
    final l10n = AppLocalizations.of(context);
    final palette = AppPalette.of(context);
    final open = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: palette.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.large)),
        title: Text(l10n.t('openLinkTitle'),
            style: AppText.title.copyWith(color: palette.textPrimary)),
        content: Text(url,
            style: AppText.body.copyWith(color: palette.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.t('cancel'),
                style: TextStyle(color: palette.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.t('open'),
                style: const TextStyle(fontWeight: FontWeight.w700)
                    .copyWith(color: AppColors.primaryGreen)),
          ),
        ],
      ),
    );
    if (open != true) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) _toast(l10n.t('couldNotOpenLink'));
    }
  }

  Future<void> _showText(String text) async {
    final l10n = AppLocalizations.of(context);
    final palette = AppPalette.of(context);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: palette.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: palette.border),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.screen),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.t('scannedCode'),
                    style: AppText.subtitle.copyWith(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: AppSpacing.sm),
                SelectableText(text,
                    style:
                        AppText.body.copyWith(color: palette.textSecondary)),
                const SizedBox(height: AppSpacing.lg),
                SizedBox(
                  height: AppSizes.button,
                  child: FilledButton.icon(
                    onPressed: () async {
                      await SecureClipboard.copy(context, text, label: 'Scanned Text');
                      if (context.mounted) Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: Text(l10n.t('copy')),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryGreen,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _toggleTorch() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      final next = !_torch;
      await controller.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      if (mounted) setState(() => _torch = next);
    } catch (_) {
      // No torch on this device - leave the button visually unchanged.
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.critical,
    ));
  }

  // ---- UI -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_phase == _Phase.ready) _preview() else _placeholder(),
          _overlay(l10n),
        ],
      ),
    );
  }

  Widget _preview() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const ColoredBox(color: Colors.black);
    }
    // Cover the screen without distorting the preview's aspect ratio.
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: controller.value.previewSize?.height ?? 1,
        height: controller.value.previewSize?.width ?? 1,
        child: CameraPreview(controller),
      ),
    );
  }

  Widget _placeholder() => const ColoredBox(color: Colors.black);

  Widget _overlay(AppLocalizations l10n) {
    final size = MediaQuery.sizeOf(context);
    final frame = (size.width * 0.68).clamp(200.0, 300.0);

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screen, vertical: AppSpacing.sm),
            child: Row(
              children: [
                const InoBackButton(),
                const Spacer(),
                if (_phase == _Phase.ready)
                  _TorchButton(on: _torch, onTap: _toggleTorch),
              ],
            ),
          ),
          const Spacer(),
          if (_phase == _Phase.ready) ...[
            QrScanFrame(size: frame, accent: AppColors.primaryGreen),
            const SizedBox(height: AppSpacing.lg),
            _Hint(text: l10n.t('qrScanHint')),
          ] else
            _StatusPanel(
              phase: _phase,
              onRetry: _bootstrap,
              onSettings: CameraPermissionService.instance.openSettings,
            ),
          const SizedBox(height: AppSpacing.lg),
          // Offered in every phase on purpose: when the camera is blocked or
          // unavailable, uploading a saved payment QR is the only way through,
          // so this must not be gated behind `_Phase.ready`.
          _UploadQrButton(
            busy: _picking,
            label: l10n.t('qrUploadFromGallery'),
            onTap: _pickFromGallery,
          ),
          const Spacer(flex: 2),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// "Upload a QR image" affordance under the scan frame.
///
/// Deliberately a quiet glass pill rather than a filled button: scanning stays
/// the primary action, this is the fallback for a code that arrived as a photo.
class _UploadQrButton extends StatelessWidget {
  const _UploadQrButton({
    required this.busy,
    required this.label,
    required this.onTap,
  });

  final bool busy;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: !busy,
      label: label,
      child: GestureDetector(
        onTap: busy ? null : onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.internal, vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy)
                const InoLoader(size: 18, color: Colors.white)
              else
                const Icon(Icons.photo_library_rounded,
                    size: 18, color: Colors.white),
              const SizedBox(width: AppSpacing.xs),
              Text(
                label,
                style: AppText.label.copyWith(color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TorchButton extends StatelessWidget {
  const _TorchButton({required this.on, required this.onTap});

  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: on
              ? AppColors.primaryGreen
              : Colors.black.withValues(alpha: 0.45),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
        ),
        child: Icon(
          on ? Icons.flashlight_on_rounded : Icons.flashlight_off_rounded,
          color: Colors.white,
          size: 20,
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: AppText.body.copyWith(
          color: Colors.white.withValues(alpha: 0.92),
          height: 1.4,
        ),
      ),
    );
  }
}

/// Camera unavailable / denied. Says which it is and offers the one action that
/// can fix it, rather than a generic failure.
class _StatusPanel extends StatelessWidget {
  const _StatusPanel({
    required this.phase,
    required this.onRetry,
    required this.onSettings,
  });

  final _Phase phase;
  final VoidCallback onRetry;
  final Future<bool> Function() onSettings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (phase == _Phase.initializing) {
      return const InoLoader(color: Colors.white);
    }
    final permission = phase == _Phase.denied ||
        phase == _Phase.permanentlyDenied;
    final bodyKey = switch (phase) {
      _Phase.denied => 'cameraPermissionBody',
      _Phase.permanentlyDenied => 'cameraPermissionSettingsBody',
      _ => 'qrScannerUnavailable',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            permission
                ? Icons.no_photography_rounded
                : Icons.error_outline_rounded,
            color: Colors.white.withValues(alpha: 0.85),
            size: 44,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            l10n.t(bodyKey),
            textAlign: TextAlign.center,
            style: AppText.body.copyWith(
              color: Colors.white.withValues(alpha: 0.9),
              height: 1.45,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            onPressed: phase == _Phase.permanentlyDenied
                ? () => onSettings()
                : onRetry,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl, vertical: 12),
            ),
            child: Text(
              l10n.t(phase == _Phase.permanentlyDenied
                  ? 'openSettings'
                  : 'tryAgain'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
