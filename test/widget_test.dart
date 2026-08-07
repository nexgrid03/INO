// Basic smoke test for the INO app launch flow.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/main.dart';
import 'package:inoapp/screens/splash/splash_screen.dart';
import 'package:inoapp/services/app_settings.dart';

void main() {
  testWidgets('Splash shows branding then moves to onboarding',
      (WidgetTester tester) async {
    AppSettings.instance.onboardingSeen.value = false;
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const InoApp());

    // Entrance animation
    await tester.pump(const Duration(milliseconds: 1500));
    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.text('I'), findsOneWidget);
    expect(find.text('N'), findsOneWidget);
    expect(find.text('O'), findsOneWidget);

    // Complete the 5.2s splash animation, 0.8s hold, and 0.6s transition.
    await tester.pump(const Duration(milliseconds: 4000));
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pump(const Duration(milliseconds: 1500));

    // Onboarding is now visible: Skip + floating arrow button.
    expect(find.text('Skip', skipOffstage: false), findsOneWidget);
    expect(find.byIcon(Icons.arrow_forward_rounded, skipOffstage: false), findsOneWidget);
  });
}
