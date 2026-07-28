@Tags(['bench'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Breaks `ImageEnhancer.buildCandidate` down into its individual image
/// operations and times each one, so the optimisation targets the operation
/// that actually costs the time rather than the one that looks expensive.
///
/// The parent benchmark (ocr_perf_benchmark_test.dart) reports the stage totals;
/// this reports where those totals go. Desktop VM numbers are a lower bound - a
/// phone is several times slower - but the RELATIVE cost is what matters.
///
/// Run: flutter test test/ocr_substep_bench_test.dart
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late img.Image base;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('ocr_substep');
    // A 2000×1500 base - what bakeBase produces from a phone capture, i.e.
    // exactly what buildCandidate receives.
    base = img.Image(width: 2000, height: 1500);
    img.fill(base, color: img.ColorRgb8(238, 238, 236));
    for (var y = 60; y < 1450; y += 34) {
      img.fillRect(base,
          x1: 120,
          y1: y,
          x2: 120 + 1500 + (y % 300),
          y2: y + 11,
          color: img.ColorRgb8(28, 28, 28));
    }
  });

  tearDownAll(() async {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  int time(String label, void Function() body) {
    final sw = Stopwatch()..start();
    body();
    sw.stop();
    // ignore: avoid_print
    print('  [$label] ${sw.elapsedMilliseconds} ms');
    return sw.elapsedMilliseconds;
  }

  test('buildCandidate sub-step costs', timeout: const Timeout(Duration(minutes: 5)), () {
    // ignore: avoid_print
    print('\n=== buildCandidate sub-step breakdown (2000x1500 base) ===');

    final encoded = img.encodeJpg(base, quality: 90);
    time('decodeJpg', () => img.decodeJpg(encoded));

    time('copyCrop', () =>
        img.copyCrop(base, x: 100, y: 100, width: 1700, height: 1300));

    time('copyRotate 3deg cubic', () => img.copyRotate(base,
        angle: -3.0, interpolation: img.Interpolation.cubic));

    final gray = time('grayscale', () => img.grayscale(img.Image.from(base)));
    expect(gray, greaterThanOrEqualTo(0));

    final g = img.grayscale(img.Image.from(base));
    time('adjustColor', () => img.adjustColor(img.Image.from(g),
        contrast: 1.3, brightness: 1.03));
    time('gaussianBlur r=1', () => img.gaussianBlur(img.Image.from(g), radius: 1));
    time('convolution 3x3 unsharp', () => img.convolution(img.Image.from(g),
        filter: const [0, -1, 0, -1, 5, -1, 0, -1, 0], div: 1));

    time('encodeJpg q90', () => img.encodeJpg(g, quality: 90));

    // The two pixel-iteration passes inside the adaptive threshold, isolated.
    // `for (final p in image)` allocates/updates a Pixel accessor per pixel and
    // is the suspected dominant cost in the binarize path.
    time('pixel-iterate READ (luminance)', () {
      var acc = 0;
      for (final p in g) {
        acc += p.luminance.round();
      }
      expect(acc, greaterThan(0));
    });

    time('pixel-iterate WRITE (set rgb)', () {
      for (final p in g) {
        p
          ..r = 128
          ..g = 128
          ..b = 128;
      }
    });

    // Direct byte access over the same buffer, for comparison.
    final g2 = img.grayscale(img.Image.from(base));
    time('getBytes + Uint8List read', () {
      final bytes = g2.getBytes(order: img.ChannelOrder.rgb);
      var acc = 0;
      for (var i = 0; i < bytes.length; i += 3) {
        acc += bytes[i];
      }
      expect(acc, greaterThan(0));
    });

    // ── The two candidates for the biggest win ──────────────────────────────

    // Rotation interpolation: cubic samples 16 taps per pixel, linear 4, and
    // nearest 1. Deskew angles here are 1-30 degrees on text, where ML Kit is
    // insensitive to the difference.
    // ignore: avoid_print
    print('\n  -- copyRotate interpolation --');
    time('  rotate cubic', () => img.copyRotate(base,
        angle: -3.0, interpolation: img.Interpolation.cubic));
    time('  rotate linear', () => img.copyRotate(base,
        angle: -3.0, interpolation: img.Interpolation.linear));
    time('  rotate nearest', () => img.copyRotate(base,
        angle: -3.0, interpolation: img.Interpolation.nearest));

    // The full Bradley-Roth adaptive threshold, as currently implemented.
    // ignore: avoid_print
    print('\n  -- adaptive threshold --');
    final t1 = img.grayscale(img.Image.from(base));
    time('  adaptiveThreshold (pixel-iterator)', () => _thresholdIterator(t1));
    final t2 = img.grayscale(img.Image.from(base));
    time('  adaptiveThreshold (byte-access)', () => _thresholdBytes(t2));

    // Equivalence check: the byte-access version must produce identical output.
    final a = img.grayscale(img.Image.from(base));
    final b = img.grayscale(img.Image.from(base));
    _thresholdIterator(a);
    _thresholdBytes(b);
    var diffs = 0;
    for (var y = 0; y < a.height; y += 7) {
      for (var x = 0; x < a.width; x += 7) {
        if (a.getPixel(x, y).r != b.getPixel(x, y).r) diffs++;
      }
    }
    // ignore: avoid_print
    print('  byte-access output differences: $diffs (must be 0)');
    expect(diffs, 0, reason: 'the faster threshold must be pixel-identical');

    // After grayscale, all three channels hold the SAME value, so every filter
    // below does 3x the necessary work. A single-channel image should cut them
    // proportionally while producing identical luminance.
    // ignore: avoid_print
    print('\n  -- single-channel (luminance only) filters --');
    final gray1 = img.Image(width: base.width, height: base.height, numChannels: 1);
    final src3 = img.grayscale(img.Image.from(base));
    final sb = src3.getBytes(order: img.ChannelOrder.rgb);
    final db = gray1.getBytes();
    for (var i = 0, j = 0; i < db.length; i++, j += 3) {
      db[i] = sb[j];
    }
    time('  adjustColor  (1ch)', () => img.adjustColor(img.Image.from(gray1),
        contrast: 1.3, brightness: 1.03));
    time('  gaussianBlur (1ch)',
        () => img.gaussianBlur(img.Image.from(gray1), radius: 1));
    time('  convolution  (1ch)', () => img.convolution(img.Image.from(gray1),
        filter: const [0, -1, 0, -1, 5, -1, 0, -1, 0], div: 1));
    time('  encodeJpg    (1ch)', () => img.encodeJpg(gray1, quality: 90));

    // The upscale step. buildCandidate upscales any candidate narrower than
    // 1600px to 1600 with cubic interpolation - and a 1500x2000 base (what a
    // portrait phone capture bakes down to) trips that on EVERY run, deskew or
    // not. This was the unaccounted-for bulk of the stage total.
    // ignore: avoid_print
    print('\n  -- copyResize upscale 1500x2000 -> 1600 wide --');
    final portrait = img.Image(width: 1500, height: 2000);
    img.fill(portrait, color: img.ColorRgb8(240, 240, 238));
    time('  resize cubic', () => img.copyResize(portrait,
        width: 1600, interpolation: img.Interpolation.cubic));
    time('  resize linear', () => img.copyResize(portrait,
        width: 1600, interpolation: img.Interpolation.linear));
    time('  resize average', () => img.copyResize(portrait,
        width: 1600, interpolation: img.Interpolation.average));
  });
}

/// The current implementation: two `for (final p in src)` passes.
void _thresholdIterator(img.Image src, {int window = 25, double t = 0.15}) {
  final w = src.width, h = src.height;
  final n = w * h;
  final lum = List<int>.filled(n, 0);
  for (final p in src) {
    lum[p.y * w + p.x] = p.luminance.round().clamp(0, 255);
  }
  final integral = List<int>.filled(n, 0);
  for (var x = 0; x < w; x++) {
    var colSum = 0;
    for (var y = 0; y < h; y++) {
      colSum += lum[y * w + x];
      integral[y * w + x] = (x == 0 ? 0 : integral[y * w + x - 1]) + colSum;
    }
  }
  final half = window ~/ 2;
  for (final p in src) {
    final x = p.x, y = p.y;
    final x1 = x - half < 0 ? 0 : x - half;
    final y1 = y - half < 0 ? 0 : y - half;
    final x2 = x + half > w - 1 ? w - 1 : x + half;
    final y2 = y + half > h - 1 ? h - 1 : y + half;
    final count = (x2 - x1 + 1) * (y2 - y1 + 1);
    final sum = integral[y2 * w + x2] -
        (x1 > 0 ? integral[y2 * w + x1 - 1] : 0) -
        (y1 > 0 ? integral[(y1 - 1) * w + x2] : 0) +
        (x1 > 0 && y1 > 0 ? integral[(y1 - 1) * w + x1 - 1] : 0);
    final threshold = (sum / count) * (1.0 - t);
    final v = lum[y * w + x] < threshold ? 0 : 255;
    p
      ..r = v
      ..g = v
      ..b = v;
  }
}

/// The same maths over a flat byte buffer instead of the Pixel accessor.
void _thresholdBytes(img.Image src, {int window = 25, double t = 0.15}) {
  final w = src.width, h = src.height;
  final n = w * h;
  final bytes = src.getBytes(order: img.ChannelOrder.rgb);
  final lum = List<int>.filled(n, 0);
  for (var i = 0, j = 0; i < n; i++, j += 3) {
    // Same luminance weights the image package uses.
    final v = (bytes[j] * 0.299 + bytes[j + 1] * 0.587 + bytes[j + 2] * 0.114)
        .round();
    lum[i] = v < 0 ? 0 : (v > 255 ? 255 : v);
  }
  final integral = List<int>.filled(n, 0);
  for (var x = 0; x < w; x++) {
    var colSum = 0;
    for (var y = 0; y < h; y++) {
      colSum += lum[y * w + x];
      integral[y * w + x] = (x == 0 ? 0 : integral[y * w + x - 1]) + colSum;
    }
  }
  final half = window ~/ 2;
  for (var y = 0; y < h; y++) {
    final y1 = y - half < 0 ? 0 : y - half;
    final y2 = y + half > h - 1 ? h - 1 : y + half;
    final rowY2 = y2 * w;
    final rowY1 = (y1 - 1) * w;
    for (var x = 0; x < w; x++) {
      final x1 = x - half < 0 ? 0 : x - half;
      final x2 = x + half > w - 1 ? w - 1 : x + half;
      final count = (x2 - x1 + 1) * (y2 - y1 + 1);
      final sum = integral[rowY2 + x2] -
          (x1 > 0 ? integral[rowY2 + x1 - 1] : 0) -
          (y1 > 0 ? integral[rowY1 + x2] : 0) +
          (x1 > 0 && y1 > 0 ? integral[rowY1 + x1 - 1] : 0);
      final threshold = (sum / count) * (1.0 - t);
      final v = lum[y * w + x] < threshold ? 0 : 255;
      final j = (y * w + x) * 3;
      bytes[j] = v;
      bytes[j + 1] = v;
      bytes[j + 2] = v;
    }
  }
  // Write the buffer back through the pixel accessor once.
  var k = 0;
  for (final p in src) {
    final v = bytes[k];
    k += 3;
    p
      ..r = v
      ..g = v
      ..b = v;
  }
}
