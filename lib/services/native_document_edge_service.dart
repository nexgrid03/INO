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
/// emits stabilized four-corner quads for the in-app scanner overlay. Keeps the
/// custom UI; only the edge engine is swapped for a product-grade one.
class NativeDocumentEdgeService {
  NativeDocumentEdgeService();

  final DocumentDetector _detector = DocumentDetector();
  final StreamController<ScanInput> _frames =
      StreamController<ScanInput>.broadcast();

  StreamSubscription<DetectionEvent>? _subscription;
  final CornerStabilizer _stabilizer = CornerStabilizer(
    // Lower = stickier border (Photos-like lock), higher resetDistance =
    // only jump when the page truly moves.
    smoothing: 0.22,
    resetDistance: 0.25,
  );

  final StreamController<NativeEdgeEvent> _events =
      StreamController<NativeEdgeEvent>.broadcast();

  bool _running = false;
  bool _nativeFailed = false;
  int _errorStreak = 0;

  /// Whether corners are in upright preview space (native applied [rotation]).
  bool get cornersAreUpright =>
      !kIsWeb && defaultTargetPlatform != TargetPlatform.iOS;

  /// True after repeated native failures — caller should use the local fallback.
  bool get shouldFallback => _nativeFailed || kIsWeb;

  Stream<NativeEdgeEvent> get events => _events.stream;

  Future<void> start({
    DetectionSensitivity sensitivity = DetectionSensitivity.balanced,
  }) async {
    if (_running || shouldFallback) return;
    _running = true;
    _errorStreak = 0;
    _subscription = _detector
        .detectStream(
          _frames.stream,
          stabilize: _stabilizer,
          minInterval: const Duration(milliseconds: 120),
          sensitivity: sensitivity,
          minimumAspectRatio: 0.12,
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

  ScanInput? _toScanInput(
    CameraImage image, {
    required int sensorOrientation,
  }) {
    if (image.planes.isEmpty) return null;
    final isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    // iOS preview already matches the stream; Android buffers stay in sensor
    // orientation so Vision/OpenCV need the upright rotation.
    final rotation = isIOS ? 0 : (sensorOrientation % 360);

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
      // NV21 / NV12 semi-planar — pass the chroma plane twice; luma is enough.
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
