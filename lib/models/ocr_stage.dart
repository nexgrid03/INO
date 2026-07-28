/// The stages of the document-extraction pipeline, reported live by
/// `OcrService.extract` so the processing screen can show what is *actually*
/// happening instead of animating a timer.
///
/// This exists because the previous processing screen drove its progress ring
/// from a fixed 2200 ms animation that had no connection to the pipeline. On a
/// clean capture it finished long before the ring did; on a difficult one the
/// ring sat at 100% for another ten seconds. Both read as "stuck".
///
/// [weight] is the share of a typical worst-case run each stage occupies,
/// derived from the measured stage costs (see test/ocr_substep_bench_test.dart
/// and the in-app `TIMINGS` log line). Progress is the cumulative weight of
/// completed stages, so the bar advances in proportion to real work.
enum OcrStage {
  /// Reading the capture off disk and checking the result cache.
  uploading,

  /// Baking EXIF orientation and capping resolution (`bakeBase`).
  preparing,

  /// The first ML Kit recognition pass over the upright base.
  extractingText,

  /// Deciding which kind of document this is.
  identifyingType,

  /// Pulling the individual fields out of the recognised text.
  readingFields,

  /// Building and recognising an enhanced/binarized candidate. Only reached
  /// when the first pass did not produce a confident, well-structured read -
  /// on a clean capture the pipeline skips straight past it.
  refining,

  /// Persisting the extraction to the result cache.
  saving,

  /// Done.
  finishing,
}

extension OcrStageX on OcrStage {
  /// Localization key for the stage's user-facing label.
  String get labelKey => switch (this) {
        OcrStage.uploading => 'ocrStageUploading',
        OcrStage.preparing => 'ocrStagePreparing',
        OcrStage.extractingText => 'ocrStageExtracting',
        OcrStage.identifyingType => 'ocrStageIdentifying',
        OcrStage.readingFields => 'ocrStageReadingFields',
        OcrStage.refining => 'ocrStageRefining',
        OcrStage.saving => 'ocrStageSaving',
        OcrStage.finishing => 'ocrStageFinishing',
      };

  /// English fallback, used when a translation is missing.
  String get fallbackLabel => switch (this) {
        OcrStage.uploading => 'Uploading document',
        OcrStage.preparing => 'Preparing image',
        OcrStage.extractingText => 'Extracting text',
        OcrStage.identifyingType => 'Identifying document type',
        OcrStage.readingFields => 'Reading fields',
        OcrStage.refining => 'Improving readability',
        OcrStage.saving => 'Saving information',
        OcrStage.finishing => 'Finishing',
      };

  /// Share of a typical worst-case run, from the measured stage costs.
  /// The refining stage dominates because it is where the image work happens.
  double get weight => switch (this) {
        OcrStage.uploading => 0.04,
        OcrStage.preparing => 0.16,
        OcrStage.extractingText => 0.22,
        OcrStage.identifyingType => 0.04,
        OcrStage.readingFields => 0.06,
        OcrStage.refining => 0.36,
        OcrStage.saving => 0.06,
        OcrStage.finishing => 0.06,
      };

  /// Cumulative progress once this stage COMPLETES, in 0..1.
  double get completedProgress {
    var sum = 0.0;
    for (final s in OcrStage.values) {
      sum += s.weight;
      if (s == this) break;
    }
    return sum.clamp(0.0, 1.0);
  }
}
