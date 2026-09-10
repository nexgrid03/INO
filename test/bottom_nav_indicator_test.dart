// Regression guard for the bottom-nav selection capsule's alignment.
//
// The indicator this replaced was placed with `Alignment(slotFraction, 1)`,
// which looks right but isn't: Alignment distributes a child across the *free*
// space (parent − child), so a slot fraction lands short of the slot centre. It
// sat ~9px inward of the Home and Profile icons and was only ever exact on the
// middle slot — the kind of drift that's easy to miss by eye and easy to
// reintroduce.
//
// The capsule is now painted rather than positioned, so the same drift would
// come back as an off-by-a-slot in [InoNavPillPainter]'s own geometry instead.
// This drives the painter exactly as the dock does and measures where it would
// actually put the capsule.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/theme/app_theme.dart';
import 'package:inoapp/widgets/shell/ino_bottom_nav.dart';

/// Where [painter] would centre the capsule, in the paint box's local space.
double _pillCentreX(InoNavPillPainter painter, Size size) =>
    (painter.slot + 0.5) * (size.width / painter.slotCount);

void main() {
  // Small phone → large phone → small tablet: the bug scaled with bar width, so
  // a single width wouldn't have caught it.
  for (final width in const [360.0, 393.0, 430.0, 600.0]) {
    testWidgets('selection capsule centres on its icon at ${width.toInt()}dp',
        (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 300));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // Index 2 is the centre "+" button and never a resting tab.
      for (final index in const [0, 1, 3, 4]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: InoBottomNav(index: index, onSelect: (_) {}),
              ),
            ),
          ),
        );
        // Let the capsule's travel finish before measuring.
        await tester.pump(const Duration(milliseconds: 600));

        final paintFinder = find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is InoNavPillPainter,
        );
        expect(paintFinder, findsOneWidget);

        final paint = tester.widget<CustomPaint>(paintFinder);
        final painter = paint.painter! as InoNavPillPainter;
        final box = tester.getRect(paintFinder);

        // The capsule must have settled on this tab's slot, not somewhere
        // between two of them.
        expect(painter.slot, closeTo(index.toDouble(), 0.001));

        final capsuleCentre =
            box.left + _pillCentreX(painter, box.size);
        final iconCentre =
            tester.getCenter(find.byIcon(InoBottomNav.tabs[index].active)).dx;

        final offset = capsuleCentre - iconCentre;
        expect(
          offset.abs(),
          lessThan(0.5),
          reason: 'tab $index capsule is ${offset.toStringAsFixed(1)}px off '
              'its icon at ${width.toInt()}dp',
        );
      }
    });
  }

  testWidgets('capsule travels rather than cutting between tabs',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 300));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    Widget dock(int index) => MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: InoBottomNav(index: index, onSelect: (_) {}),
            ),
          ),
        );

    InoNavPillPainter painter() => tester
        .widget<CustomPaint>(
          find.byWidgetPredicate(
            (w) => w is CustomPaint && w.painter is InoNavPillPainter,
          ),
        )
        .painter! as InoNavPillPainter;

    await tester.pumpWidget(dock(0));
    await tester.pump(const Duration(milliseconds: 600));
    expect(painter().slot, closeTo(0, 0.001));

    // Same widget, new index — the capsule must animate across, so mid-flight
    // it sits strictly between the two slots and is stretched.
    await tester.pumpWidget(dock(4));
    await tester.pump(const Duration(milliseconds: 120));

    final midFlight = painter();
    expect(midFlight.slot, greaterThan(0.0));
    expect(midFlight.slot, lessThan(4.0));
    expect(midFlight.travel, greaterThan(0.0));

    await tester.pump(const Duration(milliseconds: 600));
    final settled = painter();
    expect(settled.slot, closeTo(4, 0.001));
    // At rest the stretch must be fully released, or the capsule stays wide.
    expect(settled.travel, 0.0);
  });
}
