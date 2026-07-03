import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/scan_repository.dart';
import '../../models/scan_models.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';

/// Screen 3 — OCR processing.
///
/// A calm, premium loading state while [ScanRepository.extract] runs: a gradient
/// progress ring with a live percentage, a stepped status line, and an estimate.
/// Resolves to [onResult] on success or [onFailed] if extraction throws.
class OcrProcessingScreen extends StatefulWidget {
  const OcrProcessingScreen({
    super.key,
    required this.imagePath,
    required this.onResult,
    required this.onFailed,
  });

  /// The captured/imported image to run OCR against (null in manual contexts).
  final String? imagePath;
  final ValueChanged<OcrResult> onResult;
  final VoidCallback onFailed;

  @override
  State<OcrProcessingScreen> createState() => _OcrProcessingScreenState();
}

class _OcrProcessingScreenState extends State<OcrProcessingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  static const _steps = <(double, String)>[
    (0.0, 'Reading the document…'),
    (0.35, 'Detecting text regions…'),
    (0.65, 'Extracting information…'),
    (0.9, 'Matching to a wallet…'),
  ];

  @override
  void initState() {
    super.initState();
    _c.forward();
    _run();
  }

  Future<void> _run() async {
    try {
      final result =
          await ScanRepository.instance.extract(imagePath: widget.imagePath);
      if (!mounted) return;
      widget.onResult(result);
    } on OcrException catch (e) {
      // Expected "couldn't read it" outcome → offer manual entry.
      developer.log('extraction failed (OcrException): $e', name: 'ocr');
      if (!mounted) return;
      widget.onFailed();
    } catch (e, st) {
      // Any *unexpected* throwable (platform/native/isolate error) must never
      // hang or crash the flow — log it fully and fall back to manual entry.
      developer.log('extraction failed (unexpected): $e',
          name: 'ocr', error: e, stackTrace: st);
      if (!mounted) return;
      widget.onFailed();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  String _statusFor(double t) {
    var label = _steps.first.$2;
    for (final s in _steps) {
      if (t >= s.$1) label = s.$2;
    }
    return label;
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.screen),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              AnimatedBuilder(
                animation: _c,
                builder: (context, _) {
                  final t = _c.value;
                  return Column(
                    children: [
                      _ProgressRing(progress: t),
                      const SizedBox(height: AppSpacing.xl),
                      Text('Extracting Information',
                          style: AppText.headline
                              .copyWith(color: palette.textPrimary)),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Please wait while INO analyzes your document.',
                        textAlign: TextAlign.center,
                        style: AppText.body.copyWith(
                            color: palette.textSecondary, height: 1.5),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _StatusLine(text: _statusFor(t)),
                    ],
                  );
                },
              ),
              const Spacer(),
              AnimatedBuilder(
                animation: _c,
                builder: (context, _) {
                  final remaining =
                      ((1 - _c.value) * 2.2).clamp(0.0, 9.9);
                  return Text(
                    remaining < 0.15
                        ? 'Almost done…'
                        : 'Estimated ${remaining.toStringAsFixed(0)}s remaining',
                    style:
                        AppText.caption.copyWith(color: palette.textFaint),
                  );
                },
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        ),
      ),
    );
  }
}

/// A gradient progress ring with the live percentage in the centre.
class _ProgressRing extends StatelessWidget {
  const _ProgressRing({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SizedBox(
      width: 132,
      height: 132,
      child: CustomPaint(
        painter: _RingPainter(
          progress: progress,
          track: palette.surfaceVariant,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${(progress * 100).round()}%',
                style: AppText.headline
                    .copyWith(color: palette.textPrimary, fontSize: 26),
              ),
              const SizedBox(height: 2),
              Icon(Icons.document_scanner_rounded,
                  size: 18, color: AppColors.primaryGreen),
            ],
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress, required this.track});

  final double progress;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.width - 12) / 2;
    const stroke = 10.0;

    final trackPaint = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, trackPaint);

    final rect = Rect.fromCircle(center: center, radius: radius);
    final sweep = 2 * math.pi * progress.clamp(0.0, 1.0);
    final arcPaint = Paint()
      ..shader = const SweepGradient(
        startAngle: 0,
        endAngle: 2 * math.pi,
        colors: [AppColors.primaryGreen, AppColors.lightBlue],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, -math.pi / 2, sweep, false, arcPaint);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress;
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.primaryGreen,
          ),
        ),
        const SizedBox(width: 10),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 240),
          child: Text(
            text,
            key: ValueKey(text),
            style: AppText.subtitle
                .copyWith(color: palette.textSecondary, fontSize: 13),
          ),
        ),
      ],
    );
  }
}
