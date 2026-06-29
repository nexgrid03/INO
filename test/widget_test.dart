// Basic smoke test for the INO app launch flow.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inoapp/main.dart';

void main() {
  testWidgets('Splash shows branding then moves to onboarding',
      (WidgetTester tester) async {
    await tester.pumpWidget(const InoApp());

    // Let the entrance animation play out.
    await tester.pump(const Duration(milliseconds: 2300));

    // "INO" appears twice on the splash: the logo monogram and the title.
    expect(find.text('INO'), findsNWidgets(2));
    expect(find.text('Simple Life, Secure Future'), findsOneWidget);

    // Advance past the splash controller (3.5s) and the 0.5s fade to
    // onboarding. We pump fixed durations rather than pumpAndSettle because
    // the onboarding screen has a perpetual particle animation.
    await tester.pump(const Duration(milliseconds: 1500)); // -> ~3.8s
    await tester.pump(const Duration(milliseconds: 600)); // transition done

    // Onboarding is now visible: Skip + the floating arrow button.
    expect(find.text('Skip'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_forward_rounded), findsOneWidget);
  });
}
