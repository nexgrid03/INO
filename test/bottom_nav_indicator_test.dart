// Regression guard for the bottom-nav crest's alignment.
//
// The crest used to be placed with `Alignment(slotFraction, 1)`, which looks
// right but isn't: Alignment distributes a child across the *free* space
// (parent − child), so a slot fraction lands short of the slot centre. It sat
// ~9px inward of the Home and Profile icons and was only ever exact on the
// middle slot — the kind of drift that's easy to miss by eye and easy to
// reintroduce.
//
// The crest is now painted rather than positioned, so the same drift would come
// back as an off-by-a-slot in [InoNavMountainPainter]'s own geometry instead.
// These drive the painter exactly as the dock does and measure where it would
// actually put the crest.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/theme/app_theme.dart';
import 'package:inoapp/widgets/shell/ino_bottom_nav.dart';

/// Where [painter] would centre the crest, in the paint box's local space.
double _crestCentreX(InoNavMountainPainter painter, Size size) =>
    (painter.slot + 0.5) * (size.width / painter.slotCount);

final _crestFinder = find.byWidgetPredicate(
  (w) => w is CustomPaint && w.painter is InoNavMountainPainter,
);

InoNavMountainPainter _crestPainter(WidgetTester tester) =>
    tester.widget<CustomPaint>(_crestFinder).painter! as InoNavMountainPainter;

Widget _dock(int index) => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: InoBottomNav(index: index, onSelect: (_) {}),
        ),
      ),
    );

void main() {
  // Small phone → large phone → small tablet: the bug scaled with bar width, so
  // a single width wouldn't have caught it.
  for (final width in const [360.0, 393.0, 430.0, 600.0]) {
    testWidgets('crest centres on its icon at ${width.toInt()}dp',
        (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 300));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // Index 2 is the centre "+" button and never a resting tab.
      for (final index in const [0, 1, 3, 4]) {
        await tester.pumpWidget(_dock(index));
        // Let the crest's travel finish before measuring.
        await tester.pump(const Duration(milliseconds: 600));

        expect(_crestFinder, findsOneWidget);
        final painter = _crestPainter(tester);
        final box = tester.getRect(_crestFinder);

        // The crest must have settled on this tab's slot, not somewhere between
        // two of them.
        expect(painter.slot, closeTo(index.toDouble(), 0.001));

        final crestCentre = box.left + _crestCentreX(painter, box.size);
        final iconCentre =
            tester.getCenter(find.byIcon(InoBottomNav.tabs[index].active)).dx;

        final offset = crestCentre - iconCentre;
        expect(
          offset.abs(),
          lessThan(0.5),
          reason: 'tab $index crest is ${offset.toStringAsFixed(1)}px off '
              'its icon at ${width.toInt()}dp',
        );
      }
    });
  }

  testWidgets('crest flows between tabs instead of cutting', (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 300));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_dock(0));
    await tester.pump(const Duration(milliseconds: 600));
    expect(_crestPainter(tester).slot, closeTo(0, 0.001));

    // Same widget, new index — the crest must animate across, so mid-flight it
    // sits strictly between the two slots and its dome is flattened.
    await tester.pumpWidget(_dock(4));
    await tester.pump(const Duration(milliseconds: 120));

    final midFlight = _crestPainter(tester);
    expect(midFlight.slot, greaterThan(0.0));
    expect(midFlight.slot, lessThan(4.0));
    expect(midFlight.travel, greaterThan(0.0));

    await tester.pump(const Duration(milliseconds: 600));
    final settled = _crestPainter(tester);
    expect(settled.slot, closeTo(4, 0.001));
    // At rest the dome must be fully risen again, or the crest stays sunken.
    expect(settled.travel, 0.0);
  });
}
