// Regression guard for the first-run tour's spotlight alignment.
//
// The spotlight used to be a fixed-radius circle dropped on the *centre of the
// target's render box*. Both halves of that are wrong for the things the tour
// actually points at: a quick-action tile is a 72px disc plus a caption, and a
// nav tab is an icon plus a label, so the box centre sits well below the disc
// and a guessed radius (32) is smaller than the disc itself (36). The hole
// landed low and clipped the top of the very button it was highlighting.
//
// The spotlight is now derived from the target's real bounds, so these tests
// assert the property that matters: whatever the tour points at is entirely
// inside the hole.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/widgets/shell/feature_tour.dart';

TourStep _stepFor(Rect target, {String title = 'Voice Assistant'}) => TourStep(
      name: 'Target',
      title: title,
      body: 'Navigate hands-free.',
      target: () => target,
    );

/// True when [hole] fully contains [rect] - including its corners, which a
/// rounded hole can clip even when the bounding boxes agree.
bool _holeContains(RRect hole, Rect rect) {
  final path = Path()..addRRect(hole);
  for (final p in [
    rect.topLeft,
    rect.topRight,
    rect.bottomLeft,
    rect.bottomRight,
    rect.centerLeft,
    rect.centerRight,
    rect.topCenter,
    rect.bottomCenter,
  ]) {
    if (!path.contains(p)) return false;
  }
  return true;
}

/// True when the disc inscribed in [rect] is fully inside [hole] - the right
/// question for a round target, whose bounding-box corners are empty air.
bool _holeContainsDisc(RRect hole, Rect rect) {
  final path = Path()..addRRect(hole);
  final r = rect.shortestSide / 2;
  for (var i = 0; i < 16; i++) {
    final a = i * 2 * math.pi / 16;
    final p = rect.center.translate(r * math.cos(a), r * math.sin(a));
    if (!path.contains(p)) return false;
  }
  return true;
}

void main() {
  group('TourStep.hole', () {
    test('encloses a quick-action tile, disc and caption alike', () {
      // The real Voice tile: a 72px disc, 4px gap, ~13px caption, in a 78px
      // wide cell. The disc is the part the old spotlight clipped.
      const tile = Rect.fromLTWH(540, 630, 78, 89);
      const disc = Rect.fromLTWH(543, 630, 72, 72);

      final hole = _stepFor(tile).hole();

      expect(_holeContains(hole, tile), isTrue,
          reason: 'the whole tile - disc and caption - must be lit');
      expect(_holeContainsDisc(hole, disc), isTrue);
      expect(hole.outerRect.center.dx, closeTo(tile.center.dx, 0.01));
      expect(hole.outerRect.center.dy, closeTo(tile.center.dy, 0.01));
      expect(hole.outerRect.top, lessThan(disc.top),
          reason: 'the hole must start above the disc, not inside it');
    });

    test('encloses a wide nav tab, icon and label alike', () {
      const tab = Rect.fromLTWH(0, 1180, 72, 56);
      final hole = _stepFor(tab).hole();

      expect(_holeContains(hole, tab), isTrue);
      expect(hole.outerRect.center, tab.center);
    });

    test('a square target still reads as a true circle', () {
      const fab = Rect.fromLTWH(160, 1170, 64, 64);
      final hole = _stepFor(fab).hole();

      final r = hole.outerRect;
      expect(r.width, closeTo(r.height, 0.01));
      expect(hole.tlRadiusX, closeTo(r.width / 2, 0.01),
          reason: 'corner radius of half the side is exactly a circle');
      expect(r.center, fab.center);
      expect(_holeContainsDisc(hole, fab), isTrue,
          reason: 'a square target is a disc in practice - light all of it');
    });

    test('padding is breathing room, never a crop', () {
      const target = Rect.fromLTWH(100, 100, 50, 90);
      final hole = _stepFor(target).hole();

      expect(hole.outerRect.width, greaterThan(target.width));
      expect(hole.outerRect.height, greaterThan(target.height));
      expect(_holeContains(hole, target), isTrue);
    });

    test('every plausible tile shape keeps its target inside the hole', () {
      // Sweep the aspect ratios the tour actually meets, so a future layout
      // tweak cannot quietly reintroduce a clipping hole.
      for (var w = 32.0; w <= 140; w += 4) {
        for (var h = 32.0; h <= 140; h += 4) {
          final target = Rect.fromLTWH(200, 400, w, h);
          final hole = _stepFor(target).hole();
          // Read the shape off the hole itself rather than re-deriving the
          // branch: a circle only has to light the target's inscribed disc,
          // a rounded rect has to light the whole box.
          final o = hole.outerRect;
          final isCircle = (o.width - o.height).abs() < 0.01 &&
              (hole.tlRadiusX - o.width / 2).abs() < 0.01;
          final ok = isCircle
              ? _holeContainsDisc(hole, target)
              : _holeContains(hole, target);
          expect(ok, isTrue, reason: 'clipped a ${w}x$h target');
        }
      }
    });
  });

  group('FeatureTour', () {
    /// Lays the target out first, then mounts the tour over it - the same order
    /// the shell uses, where the tour only activates once the page is up.
    Future<Rect> pumpTourOver(
      WidgetTester tester, {
      required Rect placement,
      required GlobalKey targetKey,
      VoidCallback? onFinish,
    }) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      Widget tree({required bool tour}) => MaterialApp(
            home: Stack(
              children: [
                Positioned(
                  left: placement.left,
                  top: placement.top,
                  child: SizedBox(
                    key: targetKey,
                    width: placement.width,
                    height: placement.height,
                  ),
                ),
                if (tour)
                  Positioned.fill(
                    child: FeatureTour(
                      steps: [
                        TourStep(
                          name: 'Target',
                          title: 'Voice Assistant',
                          body: 'Navigate hands-free.',
                          target: () {
                            final box = targetKey.currentContext!
                                .findRenderObject()! as RenderBox;
                            return box.localToGlobal(Offset.zero) & box.size;
                          },
                        ),
                      ],
                      onFinish: onFinish ?? () {},
                    ),
                  ),
              ],
            ),
          );

      await tester.pumpWidget(tree(tour: false));
      await tester.pumpWidget(tree(tour: true));
      await tester.pump(const Duration(milliseconds: 400));
      return tester.getRect(find.byKey(targetKey));
    }

    testWidgets('the step card never covers the target it explains',
        (tester) async {
      // A quick action low on the page - the case from the bug report, where
      // the card has to flip above the spotlight.
      final key = GlobalKey();
      final target = await pumpTourOver(
        tester,
        placement: const Rect.fromLTWH(290, 520, 78, 89),
        targetKey: key,
      );

      final hole = _stepFor(target).hole();
      final card = tester.getRect(find.text('Voice Assistant'));

      expect(card.overlaps(hole.outerRect), isFalse,
          reason: 'the explanation must sit clear of the spotlight');
      expect(_holeContains(hole, target), isTrue);
    });

    testWidgets('a target near the top puts the card below it', (tester) async {
      final key = GlobalKey();
      final target = await pumpTourOver(
        tester,
        placement: const Rect.fromLTWH(24, 80, 42, 42),
        targetKey: key,
      );

      final card = tester.getRect(find.text('Voice Assistant'));
      expect(card.top, greaterThan(target.bottom));
    });

    testWidgets('Done finishes the tour on the last step', (tester) async {
      var finished = false;
      await pumpTourOver(
        tester,
        placement: const Rect.fromLTWH(290, 520, 78, 89),
        targetKey: GlobalKey(),
        onFinish: () => finished = true,
      );

      await tester.tap(find.text('Done'));
      await tester.pump();
      expect(finished, isTrue);
    });
  });
}
