import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'ios_vision_scanner_service.dart';
import 'live_document_detector.dart';

/// Current stage of the iOS document detection & auto-capture state machine.
enum IosCapturePhase {
  /// No valid document detected in the frame.
  searching,

  /// Document detected, but moving, blurry, or still stabilizing.
  stabilizing,

  /// Document is sharp, well-framed, and held steady for the required duration.
  /// Auto-capture should fire once (unless manual mode is selected).
  readyToCapture,

  /// Post-capture latch: waiting for cooldown + document change/reframe so the
  /// exact same stationary page is never captured twice in a row.
  cooldown,
}

/// Output of feeding one frame into [IosAutoCaptureController].
class IosAutoCaptureDecision {
  const IosAutoCaptureDecision({
    required this.phase,
    required this.corners,
    required this.shouldAutoCapture,
    this.stabilityProgress = 0.0,
    this.isBlurry = false,
    this.isPoorLighting = false,
  });

  final IosCapturePhase phase;

  /// Stabilized upright normalized corners (TL, TR, BR, BL) to paint in the
  /// blue overlay, or `null` when no document is present.
  final List<Offset>? corners;

  /// True on the exact edge frame where auto-capture should trigger.
  final bool shouldAutoCapture;

  /// 0..1 progress through the steady hold duration.
  final double stabilityProgress;

  /// True if the frame was rejected for blur (motion / out of focus).
  final bool isBlurry;

  /// True if lighting is too dark or overexposed.
  final bool isPoorLighting;
}

/// Pure-Dart stability, corner-smoothing, and duplicate-prevention state machine
/// for the iOS Vision scanner.
///
/// Enforces:
/// - Convex document geometry (area + aspect ratio gates rejecting background clutter)
/// - Adaptive corner EMA + deadband (rock-steady blue overlay without shimmer)
/// - Corner-coordinate movement gating (rejects shaky hands)
/// - Detection confidence gating
/// - Blur detection (Laplacian variance threshold)
/// - Exposure / lighting gating
/// - Sustained hold duration (`holdDuration`) before auto-capture triggers
/// - Minimum inter-capture interval (`minCaptureInterval`)
/// - Duplicate-capture prevention (latches until document leaves or reframes)
class IosAutoCaptureController {
  IosAutoCaptureController({
    this.minConfidence = 0.48,
    this.minArea = 0.11,
    this.maxArea = 0.96,
    this.minAspectRatio = 0.34,
    this.maxAspectRatio = 2.90,
    this.minSharpness = 32.0,
    this.minBrightness = 22.0,
    this.maxBrightness = 248.0,
    this.maxFrameJitter = 0.024,
    this.deadbandDistance = 0.014,
    this.snapJumpDistance = 0.16,
    this.holdDuration = const Duration(milliseconds: 620),
    this.minSteadyFrames = 4,
    this.maxMissedFrames = 5,
    this.minCaptureInterval = const Duration(milliseconds: 1800),
    this.reframeResetDistance = 0.11,
    this.absentFramesToUnlatch = 4,
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  final double minConfidence;
  final double minArea;
  final double maxArea;
  final double minAspectRatio;
  final double maxAspectRatio;
  final double minSharpness;
  final double minBrightness;
  final double maxBrightness;
  final double maxFrameJitter;
  final double deadbandDistance;
  final double snapJumpDistance;
  final Duration holdDuration;
  final int minSteadyFrames;
  final int maxMissedFrames;
  final Duration minCaptureInterval;
  final double reframeResetDistance;
  final int absentFramesToUnlatch;
  final DateTime Function() _now;

  List<Offset>? _smoothedCorners;
  List<Offset>? _prevRawCorners;
  List<Offset>? _lastCapturedCorners;
  DateTime? _steadySince;
  DateTime? _lastCaptureAt;
  int _steadyFrames = 0;
  int _missedFrames = 0;
  int _absentSinceCapture = 0;
  bool _duplicateLatched = false;

  /// Clears tracking state.
  ///
  /// When [preserveCaptureLatch] is true (resuming live detection immediately
  /// after a successful capture), the post-capture cooldown and duplicate-page
  /// latch remain active so the exact same stationary page is not captured
  /// twice in a row.
  void reset({bool preserveCaptureLatch = false}) {
    _smoothedCorners = null;
    _prevRawCorners = null;
    _steadySince = null;
    _steadyFrames = 0;
    _missedFrames = 0;
    if (!preserveCaptureLatch) {
      _absentSinceCapture = 0;
      _duplicateLatched = false;
      _lastCapturedCorners = null;
    }
  }

  /// Call immediately after a page is captured (auto OR manual) to arm
  /// duplicate-capture prevention and the minimum capture cooldown.
  void markCaptured(List<Offset>? capturedCorners) {
    _lastCaptureAt = _now();
    _lastCapturedCorners =
        capturedCorners == null ? null : List<Offset>.from(capturedCorners);
    _duplicateLatched = true;
    _absentSinceCapture = 0;
    _steadySince = null;
    _steadyFrames = 0;
  }

  /// Feeds one native Vision frame result (or `null` when Vision found no doc).
  IosAutoCaptureDecision addFrame(
    IosVisionFrameResult? result, {
    required bool autoCaptureEnabled,
  }) {
    final now = _now();

    if (result == null || !_isValidDocument(result)) {
      _missedFrames++;
      _steadySince = null;
      _steadyFrames = 0;
      _prevRawCorners = null;

      if (_duplicateLatched) {
        _absentSinceCapture++;
        if (_absentSinceCapture >= absentFramesToUnlatch) {
          _duplicateLatched = false;
          _lastCapturedCorners = null;
        }
      }

      if (_missedFrames >= maxMissedFrames) {
        _smoothedCorners = null;
        return const IosAutoCaptureDecision(
          phase: IosCapturePhase.searching,
          corners: null,
          shouldAutoCapture: false,
        );
      }

      // Hold the last smoothed quad briefly across transient AF dips.
      return IosAutoCaptureDecision(
        phase: _smoothedCorners == null
            ? IosCapturePhase.searching
            : IosCapturePhase.stabilizing,
        corners: _smoothedCorners,
        shouldAutoCapture: false,
      );
    }

    _missedFrames = 0;
    _absentSinceCapture = 0;

    final ordered = LiveDocumentDetector.orderClockwise(result.corners);

    // Unlatch duplicate guard if the user moved to a meaningfully different
    // page position / framing.
    if (_duplicateLatched && _lastCapturedCorners != null) {
      final alignedToCapture =
          LiveDocumentDetector.alignCorners(_lastCapturedCorners!, ordered);
      if (_meanDistance(_lastCapturedCorners!, alignedToCapture) >=
          reframeResetDistance) {
        _duplicateLatched = false;
        _lastCapturedCorners = null;
      }
    }

    // Compute raw frame-to-frame corner movement.
    double rawMovement = 0.0;
    double maxCornerJump = 0.0;
    List<Offset> alignedRaw = ordered;
    if (_prevRawCorners != null) {
      alignedRaw = LiveDocumentDetector.alignCorners(_prevRawCorners!, ordered);
      rawMovement = _meanDistance(_prevRawCorners!, alignedRaw);
      maxCornerJump = _maxDistance(_prevRawCorners!, alignedRaw);
    }
    _prevRawCorners = alignedRaw;

    // Update smoothed display corners with deadband + adaptive EMA.
    if (_smoothedCorners == null || maxCornerJump > snapJumpDistance) {
      _smoothedCorners = alignedRaw;
    } else {
      final alignedToSmooth =
          LiveDocumentDetector.alignCorners(_smoothedCorners!, alignedRaw);
      final smoothDist = _meanDistance(_smoothedCorners!, alignedToSmooth);
      if (smoothDist >= deadbandDistance) {
        final alpha = rawMovement <= maxFrameJitter ? 0.26 : 0.46;
        _smoothedCorners = [
          for (int i = 0; i < 4; i++)
            Offset.lerp(_smoothedCorners![i], alignedToSmooth[i], alpha)!,
        ];
      }
    }

    // Quality gates: blur & exposure.
    final isBlurry = result.sharpness < minSharpness;
    final isPoorLighting =
        result.brightness < minBrightness || result.brightness > maxBrightness;

    // Cooldown or duplicate latch active -> show blue border, do NOT auto-shoot.
    final inCooldown = _lastCaptureAt != null &&
        now.difference(_lastCaptureAt!) < minCaptureInterval;
    if (_duplicateLatched || inCooldown) {
      _steadySince = null;
      _steadyFrames = 0;
      return IosAutoCaptureDecision(
        phase: IosCapturePhase.cooldown,
        corners: _smoothedCorners,
        shouldAutoCapture: false,
        isBlurry: isBlurry,
        isPoorLighting: isPoorLighting,
      );
    }

    final isSteadyFrame =
        !isBlurry && !isPoorLighting && rawMovement <= maxFrameJitter;

    if (isSteadyFrame) {
      _steadyFrames++;
      _steadySince ??= now;
    } else {
      _steadyFrames = 0;
      _steadySince = null;
    }

    final elapsedMs =
        _steadySince == null ? 0 : now.difference(_steadySince!).inMilliseconds;
    final holdMs = math.max(1, holdDuration.inMilliseconds);
    final progress = (elapsedMs / holdMs).clamp(0.0, 1.0);

    final ready = _steadyFrames >= minSteadyFrames &&
        _steadySince != null &&
        now.difference(_steadySince!) >= holdDuration;

    if (ready) {
      final fireAuto = autoCaptureEnabled;
      if (fireAuto) {
        markCaptured(_smoothedCorners);
      }
      return IosAutoCaptureDecision(
        phase: IosCapturePhase.readyToCapture,
        corners: _smoothedCorners,
        shouldAutoCapture: fireAuto,
        stabilityProgress: 1.0,
      );
    }

    return IosAutoCaptureDecision(
      phase: IosCapturePhase.stabilizing,
      corners: _smoothedCorners,
      shouldAutoCapture: false,
      stabilityProgress: progress,
      isBlurry: isBlurry,
      isPoorLighting: isPoorLighting,
    );
  }

  bool _isValidDocument(IosVisionFrameResult result) {
    if (result.corners.length != 4) return false;
    if (result.confidence < minConfidence) return false;

    final ordered = LiveDocumentDetector.orderClockwise(result.corners);
    if (!_isConvex(ordered)) return false;

    final area = _polygonArea(ordered);
    if (area < minArea || area > maxArea) return false;

    final topW = (ordered[1] - ordered[0]).distance;
    final bottomW = (ordered[2] - ordered[3]).distance;
    final leftH = (ordered[3] - ordered[0]).distance;
    final rightH = (ordered[2] - ordered[1]).distance;
    final avgW = (topW + bottomW) / 2.0;
    final avgH = (leftH + rightH) / 2.0;
    if (avgW < 0.12 || avgH < 0.12) return false;

    final aspect = avgW / avgH;
    if (aspect < minAspectRatio || aspect > maxAspectRatio) return false;

    return true;
  }

  static double _meanDistance(List<Offset> a, List<Offset> b) {
    double sum = 0;
    for (int i = 0; i < 4; i++) {
      sum += (a[i] - b[i]).distance;
    }
    return sum / 4.0;
  }

  static double _maxDistance(List<Offset> a, List<Offset> b) {
    double m = 0;
    for (int i = 0; i < 4; i++) {
      final d = (a[i] - b[i]).distance;
      if (d > m) m = d;
    }
    return m;
  }

  static double _polygonArea(List<Offset> q) {
    double a = 0;
    for (int i = 0; i < q.length; i++) {
      final p = q[i];
      final n = q[(i + 1) % q.length];
      a += p.dx * n.dy - n.dx * p.dy;
    }
    return a.abs() / 2.0;
  }

  static bool _isConvex(List<Offset> q) {
    if (q.length != 4) return false;
    bool? prevPos;
    for (int i = 0; i < 4; i++) {
      final a = q[i];
      final b = q[(i + 1) % 4];
      final c = q[(i + 2) % 4];
      final cross =
          (b.dx - a.dx) * (c.dy - b.dy) - (b.dy - a.dy) * (c.dx - b.dx);
      if (cross.abs() < 1e-8) return false;
      final pos = cross > 0;
      if (prevPos != null && pos != prevPos) return false;
      prevPos = pos;
    }
    return prevPos != null;
  }
}
