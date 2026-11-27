import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:camera/camera.dart';
import 'package:document_scan/document_scan.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Live document borders from native engines:
/// - iOS: Apple Vision rectangle detection
/// - Android: OpenCV contour pipeline
///
/// Feeds frames from the existing `camera` stream into [DocumentDetector] and
/// emits stabilized four-corner quads for the in-app scanner overlay.
class NativeDocumentEdgeService {
  NativeDocumentEdgeService();

  final DocumentDetector _detector = DocumentDetector();
  final StreamController<ScanInput> _frames =
      StreamController<ScanInput>.broadcast();

  StreamSubscription<DetectionEvent>? _subscription;

  /// Stickier EMA on iOS so the blue border stays glued to the page.
  late final CornerStabilizer _stabilizer = CornerStabilizer(
    smoothing: _isIOS ? 0.28 : 0.18,
    resetDistance: _isIOS ? 0.22 : 0.28,
  );

  final StreamController<NativeEdgeEvent> _events =
      StreamController<NativeEdgeEvent>.broadcast();

  bool _running = false;
  bool _nativeFailed = false;
  int _errorStreak = 0;

  static bool get _isIOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// Corners are always in upright preview space when rotation is applied.
  bool get cornersAreUpright => true;

  /// True after repeated native failures — caller should use the local fallback.
  bool get shouldFallback => _nativeFailed || kIsWeb;

  Stream<NativeEdgeEvent> get events => _events.stream;

  Future<void> start({
    DetectionSensitivity? sensitivity,
  }) async {
    if (_running || shouldFallback) return;
    _running = true;
    _errorStreak = 0;

    // Live overlay: balanced finds real pages without snapping to desk edges
    // (lenient) or missing faint sheets (strict).
    final sense = sensitivity ??
        (_isIOS
            ? DetectionSensitivity.balanced
            : DetectionSensitivity.balanced);

    _subscription = _detector
        .detectStream(
          _frames.stream,
          stabilize: _stabilizer,
          // ~8–10 Hz — smooth overlay without thrashing Vision/OpenCV.
          minInterval: Duration(milliseconds: _isIOS ? 110 : 100),
          sensitivity: sense,
          // Reject table-edge slivers; still allow receipts (~0.24).
          minimumAspectRatio: _isIOS ? 0.16 : 0.12,
        )
        .listen(
          _onEvent,
          onError: (_) {
            _errorStreak++;
            if (_errorStreak >= 3) _nativeFailed = true;
          },
        );
  }

  Future<void> stop() async {
    _running = false;
    await _subscription?.cancel();
    _subscription = null;
  }

  void resetStabilizer() => _stabilizer.add(null);

  /// Push one camera frame into the native detector (non-blocking).
  void pushFrame(CameraImage image, {required int sensorOrientation}) {
    if (!_running || shouldFallback || _frames.isClosed) return;
    final input = _toScanInput(image, sensorOrientation: sensorOrientation);
    if (input == null) return;
    if (!_frames.isClosed) {
      _frames.add(input);
    }
  }

  void _onEvent(DetectionEvent event) {
    switch (event) {
      case DetectionSuccess(:final corners):
        _errorStreak = 0;
        // Drop non-convex / tiny quads — they produce garbage crops.
        if (!corners.isConvex || corners.area < 0.08) {
          if (!_events.isClosed) {
            _events.add(const NativeEdgeEvent(
              corners: null,
              confidence: 0,
              present: false,
            ));
          }
          return;
        }
        final pts = [
          Offset(corners.topLeft.x, corners.topLeft.y),
          Offset(corners.topRight.x, corners.topRight.y),
          Offset(corners.bottomRight.x, corners.bottomRight.y),
          Offset(corners.bottomLeft.x, corners.bottomLeft.y),
        ];
        if (!_events.isClosed) {
          _events.add(NativeEdgeEvent(
            corners: pts,
            confidence: corners.confidence ?? 0.7,
            present: true,
          ));
        }
      case DetectionEmpty():
        _errorStreak = 0;
        if (!_events.isClosed) {
          _events.add(const NativeEdgeEvent(
            corners: null,
            confidence: 0,
            present: false,
          ));
        }
      case DetectionSkipped():
        break;
      case DetectionError():
        _errorStreak++;
        if (_errorStreak >= 5) {
          _nativeFailed = true;
          if (!_events.isClosed) {
            _events.add(const NativeEdgeEvent(
              corners: null,
              confidence: 0,
              present: false,
              failed: true,
            ));
          }
        }
    }
  }

  /// Rotation that brings the camera buffer into upright (preview) space.
  ///
  /// Android always needs [sensorOrientation]. iOS BGRA is sometimes already
  /// preview-oriented; when the buffer is still landscape while the phone is
  /// portrait, pass sensor orientation so Vision returns upright corners that
  /// line up with [CameraPreview].
  static int frameRotation(CameraImage image, int sensorOrientation) {
    if (kIsWeb) return 0;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final landscapeBuffer = image.width >= image.height;
      final sensor = sensorOrientation % 360;
      if (landscapeBuffer && (sensor == 90 || sensor == 270)) {
        return sensor;
      }
      return 0;
    }
    return sensorOrientation % 360;
  }

  ScanInput? _toScanInput(
    CameraImage image, {
    required int sensorOrientation,
  }) {
    if (image.planes.isEmpty) return null;
    final rotation = frameRotation(image, sensorOrientation);

    if (image.format.group == ImageFormatGroup.bgra8888) {
      final plane = image.planes.first;
      return ScanInput.bgraFrame(
        width: image.width,
        height: image.height,
        rotation: rotation,
        bytes: plane.bytes,
        bytesPerRow: plane.bytesPerRow,
      );
    }

    // YUV420 — detector uses luma only; chroma can be empty placeholders.
    final y = image.planes[0];
    final Uint8List uBytes;
    final Uint8List vBytes;
    int uvRowStride = 0;
    int uvPixelStride = 1;
    if (image.planes.length >= 3) {
      uBytes = image.planes[1].bytes;
      vBytes = image.planes[2].bytes;
      uvRowStride = image.planes[1].bytesPerRow;
      uvPixelStride = image.planes[1].bytesPerPixel ?? 1;
    } else if (image.planes.length == 2) {
      uBytes = image.planes[1].bytes;
      vBytes = image.planes[1].bytes;
      uvRowStride = image.planes[1].bytesPerRow;
      uvPixelStride = image.planes[1].bytesPerPixel ?? 2;
    } else {
      uBytes = Uint8List(0);
      vBytes = Uint8List(0);
    }

    return ScanInput.yuvFrame(
      width: image.width,
      height: image.height,
      rotation: rotation,
      yBytes: y.bytes,
      uBytes: uBytes,
      vBytes: vBytes,
      yRowStride: y.bytesPerRow,
      uvRowStride: uvRowStride,
      uvPixelStride: uvPixelStride,
    );
  }

  Future<void> dispose() async {
    await stop();
    await _frames.close();
    await _events.close();
  }
}

class NativeEdgeEvent {
  const NativeEdgeEvent({
    required this.corners,
    required this.confidence,
    required this.present,
    this.failed = false,
  });

  final List<Offset>? corners;
  final double confidence;
  final bool present;
  final bool failed;
}
