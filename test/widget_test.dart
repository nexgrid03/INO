// Basic smoke test for the INO app launch flow.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/main.dart';
import 'package:inoapp/screens/splash/splash_screen.dart';

void main() {
  testWidgets('Splash shows branding then moves to onboarding',
      (WidgetTester tester) async {
    await tester.pumpWidget(const InoApp());

    // Entrance animation
    await tester.pump(const Duration(milliseconds: 1500));
    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.text('YOUR ASSISTANT. SIMPLE LIFE.'), findsOneWidget);

    // Complete the 5.2s splash animation, 0.8s hold, and 0.6s transition.
    await tester.pump(const Duration(milliseconds: 4000));
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pump(const Duration(milliseconds: 800));

    // Onboarding is now visible: Skip + floating arrow button.
    expect(find.text('Skip'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_forward_rounded), findsOneWidget);
  });
}
