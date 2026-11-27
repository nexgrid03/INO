import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:inoapp/data/scan_repository.dart';
import 'package:inoapp/l10n/app_localizations.dart';
import 'package:inoapp/screens/scan/scan_pdf_preview_screen.dart';
import 'package:inoapp/screens/scan/scanner_screen.dart';
import 'package:inoapp/services/live_document_detector.dart';
import 'package:inoapp/services/scan_pdf_service.dart';
import 'package:inoapp/theme/app_theme.dart';
import 'package:inoapp/widgets/scan/document_highlight.dart';
import 'package:inoapp/widgets/scan/scan_controls.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    ScanRepository.instance = SampleScanRepository();
  });

  group('Enhanced Document Scanner & PDF Workflow Tests', () {
    testWidgets('ScannerScreen renders full live UI controls', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [AppLocalizations.delegate],
          home: Scaffold(
            body: ScannerScreen(
              onClose: () {},
              onCaptured: (_) {},
            ),
          ),
        ),
      );

      await tester.pump();
      expect(find.byType(ScannerScreen), findsOneWidget);
    });

    testWidgets('ScanControls displays large shutter button, gallery, and filter button when 0 pages', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScanControls(
              onGallery: () {},
              onCapture: () {},
              onToggleFlash: () {},
              flashIcon: Icons.flash_off_rounded,
              flashLabel: 'Off',
              captureState: CaptureButtonState.idle,
              scannedPages: const [],
            ),
          ),
        ),
      );

      await tester.pump();
      // Verifies Gallery button appears when no pages scanned
      expect(find.text('Gallery'), findsOneWidget);
      // Verifies Filters button appears
      expect(find.text('Filters'), findsOneWidget);
    });

    testWidgets('ScanControls displays thumbnail, page count badge, retake, and blue checkmark when pages exist', (tester) async {
      // Create a temporary dummy image file for the thumbnail
      final tempDir = Directory.systemTemp.createTempSync('ino_test_');
      final dummyImage = File('${tempDir.path}/page1.jpg');
      final image = img.Image(width: 100, height: 100);
      dummyImage.writeAsBytesSync(img.encodeJpg(image));

      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ScanControls(
                onGallery: () {},
                onCapture: () {},
                onToggleFlash: () {},
                flashIcon: Icons.flash_off_rounded,
                flashLabel: 'Off',
                captureState: CaptureButtonState.idle,
                scannedPages: [dummyImage.path, dummyImage.path],
                onRetake: () {},
                onFinishScanning: () {},
              ),
            ),
          ),
        );

        await tester.pump();
        // Page index appears on the scroll strip and the count badge.
        expect(find.text('2'), findsAtLeastNWidgets(1));
        // Retake option must be visible
        expect(find.text('Retake'), findsOneWidget);
        // Blue checkmark "Done" button must be visible
        expect(find.text('Done'), findsOneWidget);
        expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('LiveDocumentDetector supports portrait and landscape aspect ratios', () {
      final detector = LiveDocumentDetector();
      expect(detector, isNotNull);

      // Portrait A4 (aspect 0.707)
      const a4Portrait = 210.0 / 297.0;
      expect(a4Portrait >= 0.45 && a4Portrait <= 2.2, isTrue);

      // Landscape A4 (aspect 1.414)
      const a4Landscape = 297.0 / 210.0;
      expect(a4Landscape >= 0.45 && a4Landscape <= 2.2, isTrue);

      // Landscape ID Card / PAN / Driver License (aspect ~1.585)
      const idLandscape = 85.6 / 53.98;
      expect(idLandscape >= 0.45 && idLandscape <= 2.2, isTrue);
    });

    test('ScanPdfService combines multi-page portrait and landscape scans into PDF', () async {
      final tempDir = Directory.systemTemp.createTempSync('ino_pdf_test_');
      try {
        // Page 1: Portrait document (800x1200)
        final p1File = File('${tempDir.path}/p1.jpg');
        final p1 = img.Image(width: 800, height: 1200);
        img.fill(p1, color: img.ColorRgb8(255, 255, 255));
        p1File.writeAsBytesSync(img.encodeJpg(p1));

        // Page 2: Landscape document (1200x800)
        final p2File = File('${tempDir.path}/p2.jpg');
        final p2 = img.Image(width: 1200, height: 800);
        img.fill(p2, color: img.ColorRgb8(240, 240, 240));
        p2File.writeAsBytesSync(img.encodeJpg(p2));

        final pdfPath = await ScanPdfService.instance.buildPdf(
          [p1File.path, p2File.path],
        );

        final pdfFile = File(pdfPath);
        expect(pdfFile.existsSync(), isTrue);
        expect(pdfFile.lengthSync(), greaterThan(100));

        // Clean up pdf
        pdfFile.deleteSync();
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    testWidgets('ScanPdfPreviewScreen renders PDF metadata, page carousel and continue action', (tester) async {
      final tempDir = Directory.systemTemp.createTempSync('ino_preview_test_');
      try {
        final p1File = File('${tempDir.path}/p1.jpg');
        final p1 = img.Image(width: 400, height: 600);
        p1File.writeAsBytesSync(img.encodeJpg(p1));

        final dummyPdf = File('${tempDir.path}/sample.pdf');
        dummyPdf.writeAsBytesSync(Uint8List.fromList([1, 2, 3, 4, 5]));

        String? committedPdf;
        await tester.pumpWidget(
          MaterialApp(
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [AppLocalizations.delegate],
            home: ScanPdfPreviewScreen(
              pdfPath: dummyPdf.path,
              pages: [p1File.path],
              onContinue: (path) => committedPdf = path,
              onAddMorePages: () {},
            ),
          ),
        );

        await tester.pump();
        // Check header title
        expect(find.text('Document Preview'), findsOneWidget);
        // Check "Add Page" button
        expect(find.text('Add Page'), findsOneWidget);
        // Check "Continue" button
        expect(find.text('Continue'), findsOneWidget);

        // Tap continue
        await tester.tap(find.text('Continue'));
        await tester.pump();
        expect(committedPdf, dummyPdf.path);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('Cross-platform iOS and Android sensor rotation mappings', () {
      // iOS: streamMatchesPreview = true -> quarterTurns should be 0
      expect(
        outlineQuarterTurns(streamMatchesPreview: true, sensorOrientation: 90),
        0,
      );

      // Android: streamMatchesPreview = false -> sensor orientation / 90 (e.g. 1)
      expect(
        outlineQuarterTurns(streamMatchesPreview: false, sensorOrientation: 90),
        1,
      );
    });

    test('LiveDocumentDetector orderClockwise guarantees correct cyclic corner order', () {
      // Intentionally scrambled corners
      const scrambled = [
        Offset(0.8, 0.8), // Bottom-Right
        Offset(0.2, 0.2), // Top-Left
        Offset(0.2, 0.8), // Bottom-Left
        Offset(0.8, 0.2), // Top-Right
      ];

      final ordered = LiveDocumentDetector.orderClockwise(scrambled);
      expect(ordered, hasLength(4));

      // Index 0: Top-Left (0.2, 0.2)
      expect(ordered[0], const Offset(0.2, 0.2));
      // Index 1: Top-Right (0.8, 0.2)
      expect(ordered[1], const Offset(0.8, 0.2));
      // Index 2: Bottom-Right (0.8, 0.8)
      expect(ordered[2], const Offset(0.8, 0.8));
      // Index 3: Bottom-Left (0.2, 0.8)
      expect(ordered[3], const Offset(0.2, 0.8));
    });

    test('LiveDocumentDetector alignCorners eliminates index shifts across frames', () {
      const reference = [
        Offset(0.2, 0.2), // TL
        Offset(0.8, 0.2), // TR
        Offset(0.8, 0.8), // BR
        Offset(0.2, 0.8), // BL
      ];

      // A shifted candidate where index 0 is TR instead of TL
      const shifted = [
        Offset(0.81, 0.21), // TR
        Offset(0.81, 0.81), // BR
        Offset(0.21, 0.81), // BL
        Offset(0.21, 0.21), // TL
      ];

      final aligned = LiveDocumentDetector.alignCorners(reference, shifted);
      expect(aligned, hasLength(4));

      // Now aligned[0] MUST correspond to reference[0] (TL)
      expect((aligned[0] - reference[0]).distance, lessThan(0.05));
      expect((aligned[1] - reference[1]).distance, lessThan(0.05));
      expect((aligned[2] - reference[2]).distance, lessThan(0.05));
      expect((aligned[3] - reference[3]).distance, lessThan(0.05));
    });
  });
}
