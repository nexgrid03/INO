import 'dart:ui' show Offset;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform, visibleForTesting;
import 'package:flutter/services.dart'
    show MethodChannel, MissingPluginException;

/// One frame detection reading from the native iOS Vision engine
/// (`VNDetectDocumentSegmentationRequest` with strict rectangle fallback).
class IosVisionFrameResult {
  const IosVisionFrameResult({
    required this.corners,
    required this.confidence,
    required this.sharpness,
    required this.brightness,
    required this.source,
  });

  /// Four corners ordered TL, TR, BR, BL in normalized upright preview space (0..1).
  final List<Offset> corners;

  /// Vision detection confidence (0..1).
  final double confidence;

  /// Laplacian variance sharpness score of the frame (higher = sharper).
  final double sharpness;

  /// Mean luminance (0..255) for exposure/lighting checks.
  final double brightness;

  /// Detection source: `'segmentation'` or `'rectangle'`.
  final String source;
}

/// Output of native iOS still-photo document segmentation + CoreImage
/// perspective correction (`CIPerspectiveCorrection`).
class IosProcessedCapture {
  const IosProcessedCapture({
    required this.path,
    required this.cropped,
    required this.width,
    required this.height,
  });

  final String path;
  final bool cropped;
  final int width;
  final int height;
}

/// Native iOS Vision document detection & GPU perspective-crop bridge.
///
/// Channel: `ino/vision_document_scanner` (implemented in `ios/Runner/AppDelegate.swift`).
///
/// Uses Apple's iOS 15+ ML document segmentation (`VNDetectDocumentSegmentationRequest`)
/// for live frame detection (plus Laplacian blur + exposure metrics) and full-res
/// still perspective correction (`CIPerspectiveCorrection`), avoiding the inaccurate
/// generic rectangle detector and coordinate-space mismatches of the old iOS path.
class IosVisionScannerService {
  IosVisionScannerService._({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(_channelName);

  @visibleForTesting
  factory IosVisionScannerService.forTesting(MethodChannel channel) =>
      IosVisionScannerService._(channel: channel);

  static const String _channelName = 'ino/vision_document_scanner';
  static final IosVisionScannerService instance = IosVisionScannerService._();

  final MethodChannel _channel;
  bool _inFlight = false;
  bool _channelUnavailable = false;

  static bool get isIosPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  bool get isAvailable => isIosPlatform && !_channelUnavailable;

  /// Computes the rotation (in degrees CW: 0, 90, 180, 270) required to bring
  /// an iOS [CameraImage] buffer into upright portrait preview space.
  ///
  /// On iOS `camera_avfoundation`, `AVCaptureConnection.videoOrientation`
  /// usually delivers BGRA frames ALREADY upright (width < height in portrait).
  /// Never blindly rotate by 90°: only apply [sensorOrientation] when the raw
  /// buffer is still landscape (`width > height`) while sensor orientation is
  /// 90 or 270.
  @visibleForTesting
  static int computeFrameRotation({
    required int width,
    required int height,
    required int sensorOrientation,
  }) {
    final normalizedSensor = ((sensorOrientation % 360) + 360) % 360;
    if (width > height && (normalizedSensor == 90 || normalizedSensor == 270)) {
      return normalizedSensor;
    }
    return 0;
  }

  /// Runs native `VNDetectDocumentSegmentationRequest` on a live BGRA camera frame.
  ///
  /// Returns `null` if no document was found, if a previous frame is still in
  /// flight (backpressure drop), or if the native channel is unavailable.
  Future<IosVisionFrameResult?> detectFrame(
    CameraImage image, {
    required int sensorOrientation,
  }) async {
    if (_channelUnavailable || _inFlight || image.planes.isEmpty) return null;
    if (image.format.group != ImageFormatGroup.bgra8888) return null;

    final plane = image.planes.first;
    final rotation = computeFrameRotation(
      width: image.width,
      height: image.height,
      sensorOrientation: sensorOrientation,
    );

    _inFlight = true;
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'detectFrame',
        <String, dynamic>{
          'bytes': plane.bytes,
          'width': image.width,
          'height': image.height,
          'bytesPerRow': plane.bytesPerRow,
          'rotation': rotation,
        },
      );
      return parseFrameResult(raw);
    } on MissingPluginException {
      _channelUnavailable = true;
      return null;
    } catch (_) {
      return null;
    } finally {
      _inFlight = false;
    }
  }

  /// Runs native `VNDetectDocumentSegmentationRequest` + GPU `CIPerspectiveCorrection`
  /// directly on the captured full-resolution still JPEG at [capturePath].
  ///
  /// Running Vision directly on the EXIF-oriented still photo eliminates any
  /// preview-vs-still aspect-ratio drift (e.g. 16:9 preview vs 4:3 still) and
  /// produces crisp, upright, undistorted full-color crops.
  Future<IosProcessedCapture?> processCapture({
    required String capturePath,
    List<Offset>? fallbackCorners,
    int maxDimension = 2400,
  }) async {
    if (_channelUnavailable) return null;
    try {
      final args = <String, dynamic>{
        'path': capturePath,
        'maxDimension': maxDimension,
      };
      if (fallbackCorners != null && fallbackCorners.length == 4) {
        args['fallbackCorners'] = <double>[
          for (final c in fallbackCorners) ...[c.dx, c.dy],
        ];
      }
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'processCapture',
        args,
      );
      if (raw == null) return null;
      final outPath = raw['path'] as String?;
      if (outPath == null || outPath.isEmpty) return null;
      return IosProcessedCapture(
        path: outPath,
        cropped: raw['cropped'] == true,
        width: (raw['width'] as num?)?.toInt() ?? 0,
        height: (raw['height'] as num?)?.toInt() ?? 0,
      );
    } on MissingPluginException {
      _channelUnavailable = true;
      return null;
    } catch (_) {
      return null;
    }
  }

  @visibleForTesting
  static IosVisionFrameResult? parseFrameResult(Map<String, dynamic>? raw) {
    if (raw == null) return null;
    double? numVal(String k) {
      final v = raw[k];
      return v is num ? v.toDouble() : null;
    }

    final tlx = numVal('topLeftX');
    final tly = numVal('topLeftY');
    final trx = numVal('topRightX');
    final tryy = numVal('topRightY');
    final brx = numVal('bottomRightX');
    final bry = numVal('bottomRightY');
    final blx = numVal('bottomLeftX');
    final bly = numVal('bottomLeftY');

    if (tlx == null ||
        tly == null ||
        trx == null ||
        tryy == null ||
        brx == null ||
        bry == null ||
        blx == null ||
        bly == null) {
      return null;
    }

    return IosVisionFrameResult(
      corners: [
        Offset(tlx.clamp(0.0, 1.0), tly.clamp(0.0, 1.0)),
        Offset(trx.clamp(0.0, 1.0), tryy.clamp(0.0, 1.0)),
        Offset(brx.clamp(0.0, 1.0), bry.clamp(0.0, 1.0)),
        Offset(blx.clamp(0.0, 1.0), bly.clamp(0.0, 1.0)),
      ],
      confidence: (numVal('confidence') ?? 0.0).clamp(0.0, 1.0),
      sharpness: numVal('sharpness') ?? 100.0,
      brightness: numVal('brightness') ?? 128.0,
      source: (raw['source'] as String?) ?? 'segmentation',
    );
  }
}
