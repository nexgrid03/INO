import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:inoapp/services/image_enhancer.dart';

/// A measurement harness for the OCR image-processing stages (STEP 1 - MEASURE).
///
/// These are the pure-Dart, CPU-bound stages that run in background isolates:
/// [ImageEnhancer.bakeBase] (decode → orientation → downscale → re-encode) and
/// [ImageEnhancer.buildCandidate] (crop/deskew/upscale/grayscale/denoise/sharpen
/// [+ adaptive threshold]). They run on the Dart VM here, so the absolute ms are
/// a DESKTOP lower bound - a phone is slower - but the RELATIVE cost between
/// stages is what identifies the bottleneck, and it's a real measurement rather
/// than a guess.
///
/// The on-device ML Kit recognition passes need the native plugin (a device), so
/// they can't be timed here - they're measured by the in-app `TIMINGS` log line
/// (see OcrService.extract) on a real run.
///
/// Run just this file:
///   flutter test test/ocr_perf_benchmark_test.dart
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late String bigPhoto;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('ocr_bench');
    // A realistic ~12 MP portrait phone capture (3024×4032) with text-like
    // horizontal bars on a light background - representative of a receipt photo
    // for decode/downscale/convolution cost (content doesn't change timing).
    final im = img.Image(width: 3024, height: 4032);
    img.fill(im, color: img.ColorRgb8(238, 238, 236));
    for (var y = 200; y < 3900; y += 46) {
      final w = 1400 + (y % 500);
      img.fillRect(im,
          x1: 300,
          y1: y,
          x2: 300 + w,
          y2: y + 14,
          color: img.ColorRgb8(30, 30, 30));
    }
    bigPhoto = '${dir.path}/receipt_12mp.jpg';
    await File(bigPhoto).writeAsBytes(img.encodeJpg(im, quality: 92));
  });

  tearDownAll(() async {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  Future<int> time(String label, Future<void> Function() body) async {
    final sw = Stopwatch()..start();
    await body();
    sw.stop();
    // ignore: avoid_print
    print('  [$label] ${sw.elapsedMilliseconds} ms');
    return sw.elapsedMilliseconds;
  }

  test('image-stage cost breakdown (bake vs enhanced vs binarized)', () async {
    final srcKB = (File(bigPhoto).lengthSync() / 1024).round();
    // ignore: avoid_print
    print('\n=== OCR image-stage benchmark (source $srcKB KB, 3024×4032) ===');

    // ID-document bake (current default: 2000 px, q90).
    late String baseId;
    await time('bakeBase  id  (2000px/q90)', () async {
      final r = await ImageEnhancer.bakeBase(bigPhoto);
      baseId = r.path;
    });

    // Receipt/text bake (new: 1600 px, q70) - the receipt path's downscale.
    await time('bakeBase  text(1600px/q70)', () async {
      await ImageEnhancer.bakeBase(bigPhoto,
          maxDim: ImageEnhancer.kTextMaxDim, quality: ImageEnhancer.kTextQuality);
    });

    // Enhanced candidate: crop + deskew + upscale + grayscale + denoise + sharpen.
    await time('buildCandidate enhanced', () async {
      await ImageEnhancer.buildCandidate(baseId, binarize: false);
    });

    // Binarized candidate: the above + Bradley–Roth adaptive threshold.
    await time('buildCandidate binarized', () async {
      await ImageEnhancer.buildCandidate(baseId, binarize: true);
    });

    // ignore: avoid_print
    print('--- Receipt path image work: BEFORE vs AFTER ---');
    // BEFORE (old receipt path == full ID pipeline): bake(id) + enhanced + binarized.
    // AFTER  (textOnly): bake(text) only, then ONE ML Kit pass, no candidates.
    // (ML Kit passes aren't timed here - device only - but the image work below
    //  is what the optimization removes.)
    // ignore: avoid_print
    print('  BEFORE ≈ bakeBase(id) + enhanced + binarized image passes');
    // ignore: avoid_print
    print('  AFTER  ≈ bakeBase(text) only  → the two multi-second '
        'buildCandidate passes are skipped\n');

    // No assertion - this is a measurement harness; it must always pass.
    expect(true, isTrue);
  });
}
