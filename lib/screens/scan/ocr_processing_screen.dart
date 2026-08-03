import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/scan_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../models/ocr_stage.dart';
import '../../models/scan_models.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/ino_back_button.dart';
import '../../widgets/common/ino_background.dart';
import '../../widgets/divine_glass/divine_glass.dart';

/// Screen 3 - OCR processing.
///
/// Shows a stage checklist driven by the **real** pipeline: [ScanRepository]
/// reports each [OcrStage] as it enters it, and the ring advances by that
/// stage's measured share of the work.
///
/// This replaced a progress ring animated from a fixed 2200 ms controller with
/// no connection to the pipeline at all. That version reached 100% after 2.2
/// seconds regardless of what was happening - so a clean capture finished while
/// the ring was still climbing, and a slow one left the ring pinned at 100%
/// and "Almost done…" for another ten seconds. Both read as a frozen app, which
/// is why extraction *felt* far slower than it measured.
///
/// It also handles the two states the previous screen had no answer for:
/// a run that is taking unusually long (reassure, keep working) and a run that
/// failed (explain, offer Retry) - so the user is never stranded on an
/// indeterminate spinner.
class OcrProcessingScreen extends StatefulWidget {
  const OcrProcessingScreen({
    super.key,
    required this.imagePath,
    this.assumeClean = false,
    required this.onResult,
    required this.onFailed,
  });

  /// The captured/imported image to run OCR against (null in manual contexts).
  final String? imagePath;

  /// True when the capture is already upright/cropped/rectified (ML Kit
  /// scanner output) so OCR can skip its normalization bake - see
  /// [ScanRepository.extract].
  final bool assumeClean;

  final ValueChanged<OcrResult> onResult;

  /// Invoked when the user gives up on extraction and chooses manual entry.
  final VoidCallback onFailed;

  @override
  State<OcrProcessingScreen> createState() => _OcrProcessingScreenState();
}

class _OcrProcessingScreenState extends State<OcrProcessingScreen>
    with SingleTickerProviderStateMixin {
  /// How long before we tell the user it is taking unusually long. Chosen from
  /// the measured worst case: a clean capture finishes in ~2 s and even a
  /// difficult one lands well inside this, so crossing it is genuinely unusual.
  static const Duration _slowAfter = Duration(seconds: 12);

  /// Eases the ring between stage targets, so progress glides instead of
  /// jumping - the animation smooths *real* progress rather than inventing it.
  late final AnimationController _ease = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  )..addListener(() {
      if (mounted) setState(() {});
    });

  double _shownProgress = 0;
  double _targetProgress = 0;
  double _easeFrom = 0;

  OcrStage? _stage;
  final Set<OcrStage> _done = {};

  bool _slow = false;
  bool _failed = false;
  int _attempt = 0;
  Timer? _slowTimer;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    _slowTimer?.cancel();
    _ease.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    setState(() {
      _failed = false;
      _slow = false;
      _stage = null;
      _done.clear();
      _shownProgress = 0;
      _targetProgress = 0;
      _easeFrom = 0;
      _attempt++;
    });

    _slowTimer?.cancel();
    // A soft timeout: it never cancels the work, because the extraction is
    // nearly always still progressing and killing it would throw away several
    // seconds of completed image processing. It only changes what we say.
    _slowTimer = Timer(_slowAfter, () {
      if (mounted) setState(() => _slow = true);
    });

    final attempt = _attempt;
    try {
      final result = await ScanRepository.instance.extract(
        imagePath: widget.imagePath,
        assumeClean: widget.assumeClean,
        onStage: _onStage,
      );
      // A late result from a superseded attempt must not resolve the screen.
      if (!mounted || attempt != _attempt) return;
      _slowTimer?.cancel();
      widget.onResult(result);
    } on OcrException catch (e) {
      developer.log('extraction failed (OcrException): $e', name: 'ocr');
      if (!mounted || attempt != _attempt) return;
      _slowTimer?.cancel();
      setState(() => _failed = true);
    } catch (e, st) {
      // Any *unexpected* throwable (platform/native/isolate error) must never
      // hang or crash the flow - log it fully and offer retry / manual entry.
      developer.log('extraction failed (unexpected): $e',
          name: 'ocr', error: e, stackTrace: st);
      if (!mounted || attempt != _attempt) return;
      _slowTimer?.cancel();
      setState(() => _failed = true);
    }
  }

  void _onStage(OcrStage stage) {
    if (!mounted) return;
    setState(() {
      // Everything up to and including the previous stage is complete. Marking
      // by ordinal (rather than only the stages we were told about) keeps the
      // checklist honest when the pipeline SKIPS work - a clean capture never
      // enters `refining`, and that step should read as done, not pending.
      for (final s in OcrStage.values) {
        if (s.index < stage.index) _done.add(s);
      }
      _stage = stage;
      _easeFrom = _shownProgress;
      _targetProgress = stage.completedProgress;
    });
    _ease
      ..reset()
      ..forward();
  }

  double get _progress {
    final v = _easeFrom + (_targetProgress - _easeFrom) * _ease.value;
    _shownProgress = v;
    return v.clamp(0.0, 1.0);
  }

  /// Resolves a stage label, preferring the translation and falling back to the
  /// built-in English so a missing key can never render as `ocrStageSaving`.
  String _label(AppLocalizations l10n, OcrStage s) {
    final t = l10n.t(s.labelKey);
    return t == s.labelKey ? s.fallbackLabel : t;
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);

    if (_failed) {
      return _FailureView(
        onRetry: _run,
        onManual: widget.onFailed,
      );
    }

    final progress = _progress;
    return Scaffold(
      backgroundColor: palette.bg,
      body: InoBackground(
        child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.screen),
          child: Column(
            children: [
              // Back returns to the review stage (the flow's PopScope maps the
              // pop request to the previous stage rather than exiting).
              const Align(
                alignment: Alignment.centerLeft,
                child: InoBackButton(),
              ),
              const Spacer(),
              _ProgressRing(progress: progress),
              const SizedBox(height: AppSpacing.xl),
              Text(l10n.t('extractingInformation'),
                  style:
                      AppText.headline.copyWith(color: palette.textPrimary)),
              const SizedBox(height: AppSpacing.xs),
              Text(
                _slow ? l10n.t('ocrStillWorking') : l10n.t('ocrPleaseWait'),
                textAlign: TextAlign.center,
                style: AppText.body
                    .copyWith(color: palette.textSecondary, height: 1.5),
              ),
              const SizedBox(height: AppSpacing.lg),
              // Divine Glass card housing the live stage checklist.
              AdaptiveGlassCard(
                padding: const EdgeInsets.all(AppSpacing.md),
                radius: AppRadius.card,
                child: _StageChecklist(
                  stages: OcrStage.values,
                  current: _stage,
                  done: _done,
                  labelOf: (s) => _label(l10n, s),
                ),
              ),
              const Spacer(),
              // The "taking longer" notice replaces the old fake countdown,
              // which claimed a remaining time the pipeline never knew.
              AnimatedOpacity(
                opacity: _slow ? 1 : 0,
                duration: const Duration(milliseconds: 300),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.hourglass_bottom_rounded,
                        size: 15, color: palette.textFaint),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        l10n.t('ocrTakingLonger'),
                        textAlign: TextAlign.center,
                        style:
                            AppText.caption.copyWith(color: palette.textFaint),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        ),
        ),
      ),
    );
  }
}

/// The stage checklist: completed steps show a tick, the active step a spinner,
/// pending steps stay dimmed.
class _StageChecklist extends StatelessWidget {
  const _StageChecklist({
    required this.stages,
    required this.current,
    required this.done,
    required this.labelOf,
  });

  final List<OcrStage> stages;
  final OcrStage? current;
  final Set<OcrStage> done;
  final String Function(OcrStage) labelOf;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final s in stages)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: done.contains(s)
                      ? Icon(Icons.check_circle_rounded,
                          size: 17, color: AppColors.primaryGreen)
                      : s == current
                          ?  CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primaryGreen,
                            )
                          : Icon(Icons.circle_outlined,
                              size: 15, color: palette.textFaint),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 220),
                    style: AppText.subtitle.copyWith(
                      fontSize: 13,
                      color: done.contains(s) || s == current
                          ? palette.textSecondary
                          : palette.textFaint,
                      fontWeight:
                          s == current ? FontWeight.w600 : FontWeight.w400,
                    ),
                    child: Text(labelOf(s)),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Shown when extraction fails: says what happened in plain language and offers
/// a real way forward. The user is never left on an indeterminate spinner.
class _FailureView extends StatelessWidget {
  const _FailureView({required this.onRetry, required this.onManual});

  final VoidCallback onRetry;
  final VoidCallback onManual;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: palette.bg,
      body: InoBackground(
        child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.screen),
          child: Column(
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: InoBackButton(),
              ),
              const Spacer(),
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.image_not_supported_rounded,
                    size: 34, color: AppColors.warning),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                l10n.t('ocrFailedTitle'),
                textAlign: TextAlign.center,
                style: AppText.headline.copyWith(color: palette.textPrimary),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                l10n.t('ocrFailedBody'),
                textAlign: TextAlign.center,
                style: AppText.body
                    .copyWith(color: palette.textSecondary, height: 1.5),
              ),
              const SizedBox(height: AppSpacing.xl),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  label: Text(l10n.t('tryAgain')),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton(
                  onPressed: onManual,
                  child: Text(l10n.t('manualEntry')),
                ),
              ),
              const Spacer(),
            ],
          ),
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
    // Scale the ring to the screen (phones → ~132, small screens shrink,
    // tablets don't balloon) instead of a hard-coded box.
    final side =
        (MediaQuery.sizeOf(context).shortestSide * 0.36).clamp(104.0, 150.0);
    return SizedBox(
      width: side,
      height: side,
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
      ..shader =  SweepGradient(
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
