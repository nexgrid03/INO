import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/data/scan_repository.dart';
import 'package:inoapp/models/scan_models.dart';
import 'package:inoapp/screens/scan/ocr_processing_screen.dart';
import 'package:inoapp/screens/scan/ocr_result_screen.dart';
import 'package:inoapp/screens/scan/scan_flow_screen.dart';
import 'package:inoapp/theme/app_theme.dart';

void main() {
  // Production uses the real ML Kit OCR repository, which needs a device. In the
  // test host we swap in the deterministic sample repository.
  setUp(() => ScanRepository.instance = SampleScanRepository());

  // In the test host there is no camera/permission plugin, so the scanner must
  // degrade gracefully to its "camera unavailable" recovery state — never throw.
  testWidgets('Scanner handles a missing camera gracefully', (tester) async {
    tester.view.physicalSize = const Size(1400, 2800);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const ScanFlowScreen()),
    );
    // Let the async permission/camera bootstrap resolve (and fail) cleanly.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    // Mounts and survives the failed bootstrap without throwing, and never
    // shows a live preview / capture control when no camera is available.
    expect(tester.takeException(), isNull);
    expect(find.text('Scan Document'), findsOneWidget); // header still present
    expect(find.byIcon(Icons.camera_alt_rounded), findsNothing);
  });

  testWidgets('OCR processing resolves to a structured result', (tester) async {
    OcrResult? captured;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: OcrProcessingScreen(
          imagePath: null,
          onResult: (r) => captured = r,
          onFailed: () {},
        ),
      ),
    );
    expect(find.text('Extracting Information'), findsOneWidget);

    // Let the mock OCR (2.2s) resolve.
    await tester.pump(const Duration(milliseconds: 2400));
    expect(tester.takeException(), isNull);
    expect(captured, isNotNull);
    expect(captured!.documentName, 'PAN Card');
    expect(captured!.suggestedWallet, 'Identity Wallet');
  });

  testWidgets('OCR failure invokes the failure callback', (tester) async {
    (ScanRepository.instance as SampleScanRepository).failNext = true;
    var failed = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: OcrProcessingScreen(
          imagePath: null,
          onResult: (_) {},
          onFailed: () => failed = true,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 2400));
    expect(tester.takeException(), isNull);
    expect(failed, isTrue);
  });

  testWidgets('OCR results screen renders editable, confirmable fields',
      (tester) async {
    tester.view.physicalSize = const Size(2400, 9000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    OcrResult? confirmed;
    const sample = OcrResult(
      documentName: 'PAN Card',
      documentNumber: 'ABCDE1234F',
      detectedType: 'PAN Card',
      suggestedWallet: 'Identity Wallet',
      category: 'Identity',
      confidence: DetectionConfidence.high,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: OcrResultScreen(
          result: sample,
          onClose: () {},
          onRetake: () {},
          onContinue: (r) => confirmed = r,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Confirm Details'), findsOneWidget);
    expect(find.textContaining('Detected as'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'PAN Card'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(confirmed, isNotNull);
    expect(confirmed!.documentName, 'PAN Card');
  });
}
