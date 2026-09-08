import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/core/perf/image_decode.dart';

/// Builds a context with a given logical size and device pixel ratio, so the
/// cap can be checked on the screens people actually own.
Future<int> _capFor(
  WidgetTester tester, {
  required double width,
  required double devicePixelRatio,
}) async {
  late int cap;
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(
        size: Size(width, width * 2),
        devicePixelRatio: devicePixelRatio,
      ),
      child: Builder(
        builder: (context) {
          cap = zoomableDecodeCap(context);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return cap;
}

void main() {
  group('zoomableDecodeCap — the limit that decides if the image appears', () {
    testWidgets('never exceeds the GPU texture floor', (tester) async {
      // The bug: an 8160x6120 gallery photo cannot become a texture, so Flutter
      // paints nothing — no exception, no errorBuilder — and a full-screen
      // viewer shows its chrome over an empty black canvas. Whatever the
      // screen, the decode has to stay inside this bound.
      for (final (width, dpr) in const [
        (360.0, 2.0), // budget phone
        (390.0, 3.0), // iPhone-class
        (412.0, 3.5), // large Android, DPR clamped to 3 internally
        (800.0, 2.0), // tablet
        (1280.0, 3.0), // desktop window / foldable open
      ]) {
        final cap = await _capFor(tester, width: width, devicePixelRatio: dpr);
        expect(cap, lessThanOrEqualTo(kMaxTextureDimension),
            reason: 'width=$width dpr=$dpr must stay within the texture limit');
        expect(cap, greaterThan(0));
      }
    });

    testWidgets('stays sharp under zoom on a normal phone', (tester) async {
      // 390 logical x 3 DPR = 1170 physical; 2x that is 2340, comfortably under
      // the limit — so the common case is bounded by sharpness, not by the cap.
      final cap = await _capFor(tester, width: 390, devicePixelRatio: 3);
      expect(cap, 2340);
    });

    testWidgets('a very wide screen is clamped rather than scaled up',
        (tester) async {
      final cap = await _capFor(tester, width: 1280, devicePixelRatio: 3);
      expect(cap, kMaxTextureDimension);
    });
  });
}
