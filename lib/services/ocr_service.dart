import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../data/scan_repository.dart' show OcrException;
import '../models/ocr_result_model.dart';
import 'aadhaar_parser.dart';
import 'document_detector.dart';
import 'image_enhancer.dart';
import 'pan_parser.dart';

/// The real, on-device OCR pipeline built on Google ML Kit Text Recognition.
///
/// Recognition quality on phone captures is noisy — the recognizer routinely
/// drops or mangles characters (e.g. `Jujjuri` → `Jujuri`). To fight that we run
/// OCR on *several* preprocessed versions of the same capture and keep the best
/// read, rather than trusting a single pass:
///
///   1. **probe** — OCR the upright original; this also tells us where the text
///      sits (for cropping) and how tilted it is (for deskewing);
///   2. **enhanced** — crop to the text region, deskew, upscale, sharpen;
///   3. **binarized** — an adaptive-threshold pass, tried only when the first two
///      still read poorly (rescues low-contrast / unevenly-lit scans).
///
/// Each pass is scored by how confidently ML Kit recognised it *and* how
/// complete a document it parses into; the highest-scoring pass wins. It never
/// fabricates data: when nothing readable is found it throws [OcrException] so
/// the flow can offer manual entry. The parser logic itself is untouched — this
/// only improves the pixels and picks the best recognition.
class OcrService {
  OcrService._();
  static final OcrService instance = OcrService._();

  final TextRecognizer _recognizer =
      TextRecognizer(script: TextRecognitionScript.latin);

  /// Runs the multi-pass OCR pipeline on the image at [imagePath] and returns
  /// the best structured extraction.
  ///
  /// Every heavy image step happens in a background isolate (see [ImageEnhancer])
  /// and is bracketed with START/END logs (dimensions, file size, elapsed time),
  /// so a failure is fully diagnosable. Intermediate files are deleted in a
  /// `finally` block. Any unexpected error is logged with its stack and converted
  /// to an [OcrException] so the flow degrades to manual entry instead of
  /// crashing — the pipeline never suppresses a failure silently.
  Future<OcrExtraction> extract(String imagePath) async {
    final sw = Stopwatch()..start();
    final temps = <String>{};
    _step('START extract | ${_fileKB(imagePath)}KB | $imagePath', sw: sw);

    try {
      // 0. Bake orientation + cap resolution → canonical upright base.
      _step('START bakeBase', sw: sw);
      ProcessedImage base;
      try {
        base = await ImageEnhancer.bakeBase(imagePath);
      } catch (e, st) {
        // Isolate failed (e.g. OOM contained to the worker) — fall back to the
        // original capture rather than aborting the whole extraction.
        _error('bakeBase', e, st, sw);
        base = ProcessedImage(
            path: imagePath,
            width: 0,
            height: 0,
            fileBytes: _fileBytes(imagePath));
      }
      if (base.path != imagePath) temps.add(base.path);
      _step('END bakeBase', img: base, sw: sw);

      // 1. Probe pass — baseline read + text region (crop) + skew (deskew).
      _step('START OCR original', sw: sw);
      final probe = await _recognize(base.path, 'original');
      _step('END OCR original', sw: sw);
      if (probe == null) {
        throw const OcrException(
            'Could not read the image. Please try a clearer, well-lit photo.');
      }

      final region = _textRegion(probe.result);
      final skew = _medianSkew(probe.result);

      // 2. Enhanced pass: crop to the text region, deskew, upscale, sharpen.
      _step('START buildCandidate enhanced', sw: sw);
      final enhancedImg = await _buildCandidateSafe(
        base.path,
        skew: skew,
        region: region,
        binarize: false,
        sw: sw,
      );
      if (enhancedImg != null && enhancedImg.path != base.path) {
        temps.add(enhancedImg.path);
      }
      _step('END buildCandidate enhanced', img: enhancedImg, sw: sw);

      _Recognized? enhanced;
      if (enhancedImg != null) {
        _step('START OCR enhanced', sw: sw);
        enhanced = await _recognize(enhancedImg.path, 'enhanced');
        _step('END OCR enhanced', sw: sw);
      }

      final passes = <_Pass>[
        _score(probe),
        if (enhanced != null) _score(enhanced),
      ];

      // 3. Only if we still lack a confident, well-structured read do we pay for
      //    a binarized (adaptive-threshold) pass.
      var best = _best(passes);
      if (best.structure < 5) {
        _step('START buildCandidate binarized', sw: sw);
        final binImg = await _buildCandidateSafe(
          base.path,
          skew: skew,
          region: region,
          binarize: true,
          sw: sw,
        );
        if (binImg != null && binImg.path != base.path) temps.add(binImg.path);
        _step('END buildCandidate binarized', img: binImg, sw: sw);

        if (binImg != null) {
          _step('START OCR binarized', sw: sw);
          final binary = await _recognize(binImg.path, 'binarized');
          _step('END OCR binarized', sw: sw);
          if (binary != null) {
            passes.add(_score(binary));
            best = _best(passes);
          }
        }
      }

      _logPasses(passes, best);
      _step('END parsing | chosen=${best.label} type=${best.detection.type.label}',
          sw: sw);

      if (best.text.trim().isEmpty) {
        throw const OcrException('No readable text found in the capture.');
      }

      _step('END extract OK', sw: sw);
      return OcrExtraction(
        type: best.detection.type,
        typeConfidence: best.detection.confidence,
        fields: best.fields,
        rawText: best.text,
      );
    } on OcrException {
      rethrow; // expected outcome — the screen shows manual entry.
    } catch (e, st) {
      // Unexpected failure: log EVERYTHING, then degrade to manual entry. This
      // is the safety net that turns a would-be crash into a recoverable state.
      developer.log(
        'OCR PIPELINE FAILED at t=${sw.elapsedMilliseconds}ms: $e',
        name: 'ocr',
        error: e,
        stackTrace: st,
      );
      throw const OcrException(
          'Something went wrong reading the document. You can enter the details manually.');
    } finally {
      // Dispose intermediate temp files (never the original capture).
      var deleted = 0;
      for (final p in temps) {
        if (p == imagePath) continue;
        try {
          final f = File(p);
          if (f.existsSync()) {
            f.deleteSync();
            deleted++;
          }
        } catch (_) {
          // Best-effort cleanup; a leftover temp file is harmless.
        }
      }
      _step('cleanup: deleted $deleted temp file(s)', sw: sw);
    }
  }

  /// Builds a candidate, logging + swallowing (with a full stack trace) only its
  /// own failure so a bad candidate skips itself instead of aborting the whole
  /// extraction. Returns null when the candidate could not be produced.
  Future<ProcessedImage?> _buildCandidateSafe(
    String basePath, {
    required double? skew,
    required _Region? region,
    required bool binarize,
    required Stopwatch sw,
  }) async {
    try {
      return await ImageEnhancer.buildCandidate(
        basePath,
        deskewDegrees: skew,
        cropX: region?.x,
        cropY: region?.y,
        cropW: region?.w,
        cropH: region?.h,
        binarize: binarize,
      );
    } catch (e, st) {
      _error('buildCandidate(binarize=$binarize)', e, st, sw);
      return null;
    }
  }

  // ─────────────────────────── recognition ───────────────────────────

  Future<_Recognized?> _recognize(String path, String label) async {
    try {
      final input = InputImage.fromFilePath(path);
      final result = await _recognizer.processImage(input);
      return _Recognized(label, result);
    } catch (e) {
      developer.log('recognize [$label] failed: $e', name: 'ocr');
      return null;
    }
  }

  // ─────────────────────────── scoring ───────────────────────────

  /// Scores a recognition pass by parsing it and measuring completeness. The
  /// structure score (how much of a valid document we got) dominates, then
  /// average word confidence, then raw recognised-character count as a
  /// tiebreaker — this directly rewards the pass that yields the best fields.
  _Pass _score(_Recognized r) {
    final text = r.result.text;
    final lines = <String>[
      for (final b in r.result.blocks)
        for (final l in b.lines) l.text,
    ];

    final detection = DocumentDetector.detect(text);
    final fields = switch (detection.type) {
      IdDocumentType.aadhaar => AadhaarParser.parse(text, lines),
      IdDocumentType.pan => PanParser.parse(text, lines),
      _ => <String, String?>{},
    };

    // Per-word confidences (Android reports these; iOS returns null).
    final words = <MapEntry<String, double?>>[];
    final confs = <double>[];
    for (final b in r.result.blocks) {
      for (final l in b.lines) {
        for (final e in l.elements) {
          words.add(MapEntry(e.text, e.confidence));
          if (e.confidence != null) confs.add(e.confidence!);
        }
      }
    }
    final avgConfidence =
        confs.isEmpty ? -1.0 : confs.reduce((a, b) => a + b) / confs.length;

    // Structure: how complete/valid a document did this pass parse into?
    var structure = 0;
    final name = _clean(fields['name']);
    if (name != null) {
      structure += name.split(RegExp(r'\s+')).length >= 2 ? 3 : 1;
    }
    if (_clean(fields['dob']) != null) structure += 2;
    final number = _clean(fields['number']);
    if (detection.type == IdDocumentType.aadhaar &&
        AadhaarParser.isValid(number ?? '')) {
      structure += 2;
    } else if (detection.type == IdDocumentType.pan &&
        PanParser.isValid(number ?? '')) {
      structure += 2;
    } else if (number != null) {
      structure += 1;
    }
    if (_clean(fields['gender']) != null) structure += 1;

    final chars = text.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').length;

    return _Pass(
      label: r.label,
      text: text,
      detection: detection,
      fields: fields,
      avgConfidence: avgConfidence,
      wordConfidences: words,
      structure: structure,
      chars: chars,
    );
  }

  _Pass _best(List<_Pass> passes) =>
      passes.reduce((a, b) => b.score > a.score ? b : a);

  // ─────────────────────────── geometry from the probe ───────────────────────────

  /// The padded union bounding box of all recognised lines, used to crop the
  /// enhanced passes down to just the card/text. Returns null when the probe
  /// found too little to trust a crop.
  _Region? _textRegion(RecognizedText r) {
    double? left, top, right, bottom;
    var lineCount = 0;
    for (final b in r.blocks) {
      for (final line in b.lines) {
        final box = line.boundingBox;
        if (left == null || box.left < left) left = box.left;
        if (top == null || box.top < top) top = box.top;
        if (right == null || box.right > right) right = box.right;
        if (bottom == null || box.bottom > bottom) bottom = box.bottom;
        lineCount++;
      }
    }
    if (left == null || top == null || right == null || bottom == null) {
      return null;
    }
    if (lineCount < 2) return null; // too little to safely crop

    final w = right - left;
    final h = bottom - top;
    if (w < 48 || h < 48) return null;

    // Pad generously so we never clip text the probe under-boxed. copyCrop
    // clamps to the image bounds, so slightly-large values are safe.
    final padX = w * 0.08;
    final padY = h * 0.10;
    final x = math.max(0.0, left - padX);
    final y = math.max(0.0, top - padY);
    return _Region(
      x: x.round(),
      y: y.round(),
      w: (w + padX * 2).round(),
      h: (h + padY * 2).round(),
    );
  }

  /// Median tilt (degrees) across recognised lines, for deskewing. Returns null
  /// when the page is effectively straight or no angles were reported.
  double? _medianSkew(RecognizedText r) {
    final angles = <double>[];
    for (final b in r.blocks) {
      for (final line in b.lines) {
        final a = line.angle;
        if (a != null && a.abs() <= 45) angles.add(a);
      }
    }
    if (angles.isEmpty) return null;
    angles.sort();
    final mid = angles[angles.length ~/ 2];
    return mid.abs() < 1.0 ? null : mid;
  }

  // ─────────────────────────── logging ───────────────────────────

  void _logPasses(List<_Pass> passes, _Pass best) {
    if (!kDebugMode) return;
    for (final p in passes) {
      final conf =
          p.avgConfidence >= 0 ? p.avgConfidence.toStringAsFixed(2) : 'n/a';
      developer.log(
        '── OCR TEXT (${p.label}) '
        '[score=${p.score.toStringAsFixed(1)} conf=$conf '
        'struct=${p.structure} chars=${p.chars}] ──\n${p.text}',
        name: 'ocr',
      );
      final wordConf = p.wordConfidences
          .map((e) => '${e.key}=${e.value?.toStringAsFixed(2) ?? '?'}')
          .join('  ');
      developer.log('── WORD CONFIDENCE (${p.label}) ──\n$wordConf',
          name: 'ocr');
    }
    developer.log(
      'CHOSEN=${best.label}  detected=${best.detection.type.label} '
      'confidence=${best.detection.confidence.toStringAsFixed(2)} '
      'fields=${best.fields}',
      name: 'ocr',
    );
  }

  static String? _clean(String? v) {
    if (v == null) return null;
    final t = v.trim();
    return t.isEmpty ? null : t;
  }

  // ─────────────────────────── step logging ───────────────────────────

  /// Logs a pipeline step with optional produced-image details and elapsed time.
  void _step(String message, {ProcessedImage? img, Stopwatch? sw}) {
    if (!kDebugMode) return;
    final b = StringBuffer(message);
    if (img != null) {
      final name = img.path.split(RegExp(r'[\\/]')).last;
      b.write(' | ${img.width}x${img.height} '
          '${(img.fileBytes / 1024).round()}KB $name');
    }
    if (sw != null) b.write(' | t=${sw.elapsedMilliseconds}ms');
    developer.log(b.toString(), name: 'ocr');
  }

  /// Logs a step failure with its full exception + stack (never swallowed).
  void _error(String step, Object e, StackTrace st, Stopwatch sw) {
    developer.log(
      'STEP "$step" FAILED at t=${sw.elapsedMilliseconds}ms: $e',
      name: 'ocr',
      error: e,
      stackTrace: st,
    );
  }

  int _fileBytes(String path) {
    try {
      return File(path).lengthSync();
    } catch (_) {
      return 0;
    }
  }

  String _fileKB(String path) => (_fileBytes(path) / 1024).round().toString();

  /// Releases the native recognizer. Call on app shutdown if desired.
  Future<void> dispose() => _recognizer.close();
}

/// A single recognition pass with its label (original / enhanced / binarized).
class _Recognized {
  _Recognized(this.label, this.result);
  final String label;
  final RecognizedText result;
}

/// A scored recognition pass: the recognised text, what it parsed into, and the
/// metrics used to pick the winner.
class _Pass {
  _Pass({
    required this.label,
    required this.text,
    required this.detection,
    required this.fields,
    required this.avgConfidence,
    required this.wordConfidences,
    required this.structure,
    required this.chars,
  });

  final String label;
  final String text;
  final DetectionResult detection;
  final Map<String, String?> fields;
  final double avgConfidence; // -1 when the platform reports no confidences
  final List<MapEntry<String, double?>> wordConfidences;
  final int structure;
  final int chars;

  double get score =>
      structure * 1000 +
      (avgConfidence >= 0 ? avgConfidence * 100 : 0) +
      chars * 0.01;
}

/// A crop rectangle in the base image's pixel coordinates.
class _Region {
  const _Region({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  });
  final int x, y, w, h;
}
