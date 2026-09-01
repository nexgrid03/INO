// Regression guard for the bottom-nav active indicator's alignment.
//
// The indicator used to be placed with `Alignment(slotFraction, 1)`, which
// looks right but isn't: Alignment distributes a child across the *free* space
// (parent − child), so a slot fraction lands short of the slot centre. The line
// sat ~9px inward of the Home and Profile icons and was only ever exact on the
// middle slot - the kind of drift that's easy to miss by eye and easy to
// reintroduce, hence this test.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/theme/app_theme.dart';
import 'package:inoapp/widgets/shell/ino_bottom_nav.dart';

void main() {
  // Small phone → large phone → small tablet: the bug scaled with bar width, so
  // a single width wouldn't have caught it.
  for (final width in const [360.0, 393.0, 430.0, 600.0]) {
    testWidgets('active indicator centres on its icon at ${width.toInt()}dp',
        (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 300));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // Index 2 is the centre Scan button and never a resting tab.
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
        // Let the 320ms slide finish before measuring.
        await tester.pump(const Duration(milliseconds: 400));

        final iconCentre =
            tester.getCenter(find.byIcon(InoBottomNav.tabs[index].active));

        // The mountain indicator sits behind the active tab.
        final indicator = find.byKey(const ValueKey('mountain_indicator'));
        expect(indicator, findsOneWidget);

        final offset = tester.getCenter(indicator).dx - iconCentre.dx;
        expect(
          offset.abs(),
          lessThan(0.5),
          reason: 'tab $index indicator is ${offset.toStringAsFixed(1)}px off '
              'its icon at ${width.toInt()}dp',
        );
      }
    });
  }
}
