import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:inoapp/l10n/app_localizations.dart';
import 'package:inoapp/screens/scan/scan_pdf_preview_screen.dart';
import 'package:inoapp/services/ios_auto_capture_controller.dart';
import 'package:inoapp/services/ios_vision_scanner_service.dart';

IosVisionFrameResult _frame({
  List<Offset>? corners,
  double confidence = 0.90,
  double sharpness = 120.0,
  double brightness = 140.0,
  String source = 'segmentation',
}) {
  return IosVisionFrameResult(
    corners: corners ??
        const [
          Offset(0.15, 0.15),
          Offset(0.85, 0.15),
          Offset(0.85, 0.85),
          Offset(0.15, 0.85),
        ],
    confidence: confidence,
    sharpness: sharpness,
    brightness: brightness,
    source: source,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('IosVisionScannerService frame orientation & parsing', () {
    test('does not blindly rotate already-upright portrait BGRA buffers', () {
      expect(
        IosVisionScannerService.computeFrameRotation(
          width: 720,
          height: 1280,
          sensorOrientation: 90,
        ),
        0,
      );
      expect(
        IosVisionScannerService.computeFrameRotation(
          width: 1080,
          height: 1920,
          sensorOrientation: 270,
        ),
        0,
      );
    });

    test('applies sensor rotation only when raw iOS buffer is landscape', () {
      expect(
        IosVisionScannerService.computeFrameRotation(
          width: 1280,
          height: 720,
          sensorOrientation: 90,
        ),
        90,
      );
      expect(
        IosVisionScannerService.computeFrameRotation(
          width: 1280,
          height: 720,
          sensorOrientation: 270,
        ),
        270,
      );
      expect(
        IosVisionScannerService.computeFrameRotation(
          width: 1280,
          height: 720,
          sensorOrientation: 0,
        ),
        0,
      );
    });

    test('parses valid native Vision payload and rejects malformed maps', () {
      final parsed = IosVisionScannerService.parseFrameResult({
        'topLeftX': 0.1,
        'topLeftY': 0.2,
        'topRightX': 0.9,
        'topRightY': 0.2,
        'bottomRightX': 0.9,
        'bottomRightY': 0.85,
        'bottomLeftX': 0.1,
        'bottomLeftY': 0.85,
        'confidence': 0.92,
        'sharpness': 145.5,
        'brightness': 160.0,
        'source': 'segmentation',
      });

      expect(parsed, isNotNull);
      expect(parsed!.corners, hasLength(4));
      expect(parsed.confidence, closeTo(0.92, 1e-6));
      expect(parsed.sharpness, closeTo(145.5, 1e-6));
      expect(parsed.brightness, closeTo(160.0, 1e-6));
      expect(parsed.source, 'segmentation');

      expect(IosVisionScannerService.parseFrameResult(null), isNull);
      expect(
        IosVisionScannerService.parseFrameResult({'topLeftX': 0.1}),
        isNull,
      );
    });
  });

  group('IosAutoCaptureController stability & auto-capture parity', () {
    test('rejects background clutter, keyboards, tiny quads, and low confidence', () {
      var now = DateTime(2026, 11, 27, 12, 0, 0);
      final ctrl = IosAutoCaptureController(clock: () => now);

      // Tiny clutter quad (area ~0.04 < 0.11)
      final tiny = ctrl.addFrame(
        _frame(corners: const [
          Offset(0.4, 0.4),
          Offset(0.6, 0.4),
          Offset(0.6, 0.6),
          Offset(0.4, 0.6),
        ]),
        autoCaptureEnabled: true,
      );
      expect(tiny.corners, isNull);
      expect(tiny.shouldAutoCapture, isFalse);

      // Wide keyboard sliver (aspect ~4.5 > 2.9)
      final keyboard = ctrl.addFrame(
        _frame(corners: const [
          Offset(0.05, 0.40),
          Offset(0.95, 0.40),
          Offset(0.95, 0.60),
          Offset(0.05, 0.60),
        ]),
        autoCaptureEnabled: true,
      );
      expect(keyboard.corners, isNull);

      // Low confidence
      final lowConf = ctrl.addFrame(
        _frame(confidence: 0.25),
        autoCaptureEnabled: true,
      );
      expect(lowConf.corners, isNull);
    });

    test('requires sustained steady hold before auto-capturing (never immediate)', () {
      var now = DateTime(2026, 11, 27, 12, 0, 0);
      final ctrl = IosAutoCaptureController(
        holdDuration: const Duration(milliseconds: 600),
        minSteadyFrames: 4,
        clock: () => now,
      );

      // First 3 frames (0ms, 150ms, 300ms): stabilizing, NOT capturing yet.
      for (int i = 0; i < 3; i++) {
        final d = ctrl.addFrame(_frame(), autoCaptureEnabled: true);
        expect(d.phase, IosCapturePhase.stabilizing);
        expect(d.shouldAutoCapture, isFalse);
        expect(d.corners, hasLength(4));
        now = now.add(const Duration(milliseconds: 150));
      }

      // Frame 4 at 450ms: still < 600ms holdDuration.
      final d4 = ctrl.addFrame(_frame(), autoCaptureEnabled: true);
      expect(d4.shouldAutoCapture, isFalse);

      // Frame 5 at 650ms: sustained steady hold satisfied -> auto-capture fires!
      now = now.add(const Duration(milliseconds: 200));
      final d5 = ctrl.addFrame(_frame(), autoCaptureEnabled: true);
      expect(d5.phase, IosCapturePhase.readyToCapture);
      expect(d5.shouldAutoCapture, isTrue);
    });

    test('rejects blurry and poorly lit frames from triggering auto-capture', () {
      var now = DateTime(2026, 11, 27, 12, 0, 0);
      final ctrl = IosAutoCaptureController(
        holdDuration: const Duration(milliseconds: 300),
        minSteadyFrames: 2,
        clock: () => now,
      );

      for (int i = 0; i < 6; i++) {
        final d = ctrl.addFrame(_frame(sharpness: 10.0), autoCaptureEnabled: true);
        expect(d.isBlurry, isTrue);
        expect(d.shouldAutoCapture, isFalse);
        now = now.add(const Duration(milliseconds: 120));
      }

      for (int i = 0; i < 6; i++) {
        final d = ctrl.addFrame(_frame(brightness: 8.0), autoCaptureEnabled: true);
        expect(d.isPoorLighting, isTrue);
        expect(d.shouldAutoCapture, isFalse);
        now = now.add(const Duration(milliseconds: 120));
      }
    });

    test('prevents duplicate capture of the same stationary page until reframed or removed', () {
      var now = DateTime(2026, 11, 27, 12, 0, 0);
      final ctrl = IosAutoCaptureController(
        holdDuration: const Duration(milliseconds: 300),
        minSteadyFrames: 2,
        minCaptureInterval: const Duration(milliseconds: 1000),
        absentFramesToUnlatch: 3,
        clock: () => now,
      );

      // First capture succeeds.
      ctrl.addFrame(_frame(), autoCaptureEnabled: true);
      now = now.add(const Duration(milliseconds: 350));
      final first = ctrl.addFrame(_frame(), autoCaptureEnabled: true);
      expect(first.shouldAutoCapture, isTrue);

      // Resuming live detection after capture preserves the duplicate latch.
      ctrl.reset(preserveCaptureLatch: true);

      // Even well after minCaptureInterval, holding the exact same stationary
      // page must NOT fire a duplicate capture.
      now = now.add(const Duration(seconds: 3));
      for (int i = 0; i < 5; i++) {
        final dup = ctrl.addFrame(_frame(), autoCaptureEnabled: true);
        expect(dup.phase, IosCapturePhase.cooldown);
        expect(dup.shouldAutoCapture, isFalse);
        now = now.add(const Duration(milliseconds: 200));
      }

      // Remove document for 3 frames -> unlatches cleanly.
      for (int i = 0; i < 3; i++) {
        ctrl.addFrame(null, autoCaptureEnabled: true);
        now = now.add(const Duration(milliseconds: 100));
      }

      // Present next page -> captures again cleanly.
      ctrl.addFrame(_frame(), autoCaptureEnabled: true);
      now = now.add(const Duration(milliseconds: 350));
      final second = ctrl.addFrame(_frame(), autoCaptureEnabled: true);
      expect(second.shouldAutoCapture, isTrue);
    });

    test('manual mode never triggers auto-capture while still reporting ready state', () {
      var now = DateTime(2026, 11, 27, 12, 0, 0);
      final ctrl = IosAutoCaptureController(
        holdDuration: const Duration(milliseconds: 250),
        minSteadyFrames: 2,
        clock: () => now,
      );

      ctrl.addFrame(_frame(), autoCaptureEnabled: false);
      now = now.add(const Duration(milliseconds: 300));
      final d = ctrl.addFrame(_frame(), autoCaptureEnabled: false);
      expect(d.phase, IosCapturePhase.readyToCapture);
      expect(d.shouldAutoCapture, isFalse);
    });
  });

  group('ScanPdfPreviewScreen Android feature parity controls', () {
    testWidgets('renders Crop, Rotate, Discard, and all 4 filters', (tester) async {
      final tempDir = Directory.systemTemp.createTempSync('ino_ios_parity_');
      try {
        final pageFile = File('${tempDir.path}/p1.jpg');
        final im = img.Image(width: 400, height: 600);
        pageFile.writeAsBytesSync(img.encodeJpg(im));
        final pdfFile = File('${tempDir.path}/doc.pdf');
        pdfFile.writeAsBytesSync(Uint8List.fromList([1, 2, 3, 4]));

        var discarded = false;
        await tester.pumpWidget(
          MaterialApp(
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [AppLocalizations.delegate],
            home: ScanPdfPreviewScreen(
              pdfPath: pdfFile.path,
              pages: [pageFile.path],
              onContinue: (_) {},
              onAddMorePages: () {},
              onDiscardScans: () => discarded = true,
            ),
          ),
        );
        await tester.pump();

        expect(find.text('Crop'), findsOneWidget);
        expect(find.text('Rotate'), findsOneWidget);
        expect(find.text('Discard'), findsOneWidget);
        expect(find.text('Original'), findsOneWidget);
        expect(find.text('Enhance'), findsOneWidget);
        expect(find.text('B&W'), findsOneWidget);
        expect(find.text('Grayscale'), findsOneWidget);
        expect(find.text('Add Page'), findsOneWidget);
        expect(find.text('Continue'), findsOneWidget);

        await tester.tap(find.text('Discard'));
        await tester.pump();
        expect(discarded, isTrue);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });
}
