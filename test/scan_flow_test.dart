import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/data/scan_repository.dart';
import 'package:inoapp/models/scan_models.dart';
import 'package:inoapp/screens/scan/ocr_processing_screen.dart';
import 'package:inoapp/screens/scan/ocr_result_screen.dart';
import 'package:inoapp/screens/scan/scan_flow_screen.dart';
import 'package:inoapp/screens/scan/scan_wallet_screen.dart';
import 'package:inoapp/theme/app_theme.dart';

void main() {
  // Production uses the real ML Kit OCR repository, which needs a device. In the
  // test host we swap in the deterministic sample repository.
  setUp(() => ScanRepository.instance = SampleScanRepository());

  // In the test host there is no camera/permission plugin, so the scanner must
  // degrade gracefully to its "camera unavailable" recovery state - never throw.
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

  testWidgets('OCR failure shows a recoverable error, not an endless spinner',
      (tester) async {
    // Failure no longer jumps silently to manual entry: it explains what
    // happened and offers Retry, so a transient bad read costs a tap instead of
    // the whole extraction. `onFailed` now means "the user chose manual entry".
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
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    // The failure state is reached - the user is never left loading forever.
    expect(find.text('Try Again'), findsOneWidget);
    expect(find.text('Manual Entry'), findsOneWidget);
    // …and it has NOT silently fallen through to manual entry.
    expect(failed, isFalse);

    // Choosing manual entry is what invokes the callback.
    await tester.tap(find.text('Manual Entry'));
    await tester.pump();
    expect(failed, isTrue);
  });

  testWidgets('Retry re-runs extraction and can succeed', (tester) async {
    // The point of the retry path: `failNext` clears itself after firing, so
    // the second attempt takes the normal route and resolves.
    (ScanRepository.instance as SampleScanRepository).failNext = true;
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
    await tester.pump(const Duration(milliseconds: 2400));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Try Again'), findsOneWidget);
    expect(captured, isNull);

    await tester.tap(find.text('Try Again'));
    await tester.pump();
    // Back to processing, with the stage checklist visible.
    expect(find.text('Extracting Information'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 2600));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(captured, isNotNull);
    expect(captured!.documentName, 'PAN Card');
  });

  testWidgets('Processing screen reports real pipeline stages', (tester) async {
    // Progress is driven by OcrStage callbacks from the pipeline, not by a
    // fixed animation. The first stage must be visible immediately, before any
    // work could plausibly have finished.
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: OcrProcessingScreen(
          imagePath: null,
          onResult: (_) {},
          onFailed: () {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Uploading document'), findsOneWidget);
    expect(find.text('Extracting text'), findsOneWidget);
    expect(find.text('Identifying document type'), findsOneWidget);
    expect(find.text('Reading fields'), findsOneWidget);
    expect(find.text('Saving information'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Drain the mock run so the timer doesn't outlive the test.
    await tester.pump(const Duration(milliseconds: 2600));
    await tester.pump(const Duration(milliseconds: 300));
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
    // The wallet is NOT asked for here - the Choose Wallet step owns it, so the
    // question is never asked twice in one flow.
    expect(find.text('Wallet'), findsNothing);
  });

  testWidgets('Choose Wallet pre-selects the suggestion and returns the pick',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 3600);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    String? chosen;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ScanWalletScreen(
          suggestedWallet: 'Identity Wallet',
          onBack: () {},
          onSelected: (w) => chosen = w,
        ),
      ),
    );
    // Let the staggered row entrances settle.
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Choose Wallet'), findsOneWidget);
    // The OCR suggestion is badged and pre-selected, so the CTA already names it.
    expect(find.text('Suggested'), findsOneWidget);
    expect(find.text('Save to Identity Wallet'), findsOneWidget);
    // Every wallet is offered, plus a way to make a new one.
    expect(find.text('Health Wallet'), findsOneWidget);
    expect(find.text('Create new wallet'), findsOneWidget);

    // Choosing another wallet moves the selection and the CTA follows.
    await tester.tap(find.text('Health Wallet'));
    await tester.pump();
    expect(find.text('Save to Health Wallet'), findsOneWidget);
    expect(chosen, isNull); // selecting is not committing

    await tester.tap(find.text('Save to Health Wallet'));
    await tester.pump();
    expect(chosen, 'Health Wallet');
  });
}
