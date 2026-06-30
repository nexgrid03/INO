import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/data/scan_repository.dart';
import 'package:inoapp/screens/scan/scan_flow_screen.dart';
import 'package:inoapp/theme/app_theme.dart';

void main() {
  testWidgets('Scan flow: scan → review → process → confirm OCR results',
      (tester) async {
    tester.view.physicalSize = const Size(2400, 9000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const ScanFlowScreen(),
      ),
    );
    await tester.pump();

    // Screen 1 — scanner. ("Position…" shows as both the subtitle and the
    // initial guidance pill, hence findsWidgets.)
    expect(find.text('Scan Document'), findsOneWidget);
    expect(find.text('Position your document inside the frame'), findsWidgets);

    // Capture → Screen 2 (review).
    await tester.tap(find.byIcon(Icons.camera_alt_rounded));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Review Capture'), findsOneWidget);
    expect(find.text('Extract Text'), findsOneWidget);

    // Continue → Screen 3 (processing).
    await tester.tap(find.text('Extract Text'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Extracting Information'), findsOneWidget);

    // Let the mock OCR (2.2s) resolve → Screen 4 (results).
    await tester.pump(const Duration(milliseconds: 2400));
    await tester.pump(const Duration(milliseconds: 350));

    expect(tester.takeException(), isNull);
    expect(find.text('Confirm Details'), findsOneWidget);
    expect(find.textContaining('Detected as'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Retake'), findsOneWidget);
    // The detected PAN sample prefilled the editable name field.
    expect(find.widgetWithText(TextFormField, 'PAN Card'), findsOneWidget);
  });

  testWidgets('Scan flow: OCR failure shows the manual-entry fallback',
      (tester) async {
    tester.view.physicalSize = const Size(2400, 9000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    // Force the next extraction to fail.
    (ScanRepository.instance as SampleScanRepository).failNext = true;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const ScanFlowScreen(),
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.camera_alt_rounded));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.text('Extract Text'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 2400));
    await tester.pump(const Duration(milliseconds: 350));

    expect(tester.takeException(), isNull);
    expect(find.text('Unable to extract information'), findsOneWidget);
    expect(find.text('Try Again'), findsOneWidget);
    expect(find.text('Manual Entry'), findsOneWidget);
  });
}
