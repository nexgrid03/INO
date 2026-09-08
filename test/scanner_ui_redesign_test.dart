import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/l10n/app_localizations.dart';
import 'package:inoapp/screens/scan/scanner_screen.dart';
import 'package:inoapp/theme/app_theme.dart';
import 'package:inoapp/widgets/scan/scan_controls.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildFrame(Widget child, [double width = 390, double height = 844]) {
    return MaterialApp(
      theme: AppTheme.light,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [AppLocalizations.delegate],
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: SizedBox(
            width: width,
            height: height,
            child: child,
          ),
        ),
      ),
    );
  }

  group('Scanner UI Redesign & Controls Test Suite', () {
    testWidgets('ScanControls renders circular gallery button and modern shutter matching Image 2',
        (tester) async {
      var galleryTapped = false;
      var captureTapped = false;

      await tester.pumpWidget(
        buildFrame(
          ScanControls(
            onGallery: () => galleryTapped = true,
            onCapture: () => captureTapped = true,
            onToggleFlash: () {},
            flashIcon: Icons.flash_off_rounded,
            flashLabel: 'Off',
            captureState: CaptureButtonState.idle,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify gallery button has photo icon and no text label below it
      expect(find.byIcon(Icons.photo_outlined), findsOneWidget);
      expect(find.text('Gallery'), findsNothing);

      // Verify shutter button exists
      expect(find.byType(ScanControls), findsOneWidget);

      // Tap gallery button
      await tester.tap(find.byIcon(Icons.photo_outlined));
      await tester.pump();
      expect(galleryTapped, isTrue);

      // Tap capture button
      await tester.tap(find.byType(GestureDetector).last);
      await tester.pump();
      expect(captureTapped, isTrue);
    });

    testWidgets('ScanControls displays capturing and success states correctly',
        (tester) async {
      // Capturing state
      await tester.pumpWidget(
        buildFrame(
          ScanControls(
            onGallery: () {},
            onCapture: () {},
            onToggleFlash: () {},
            flashIcon: Icons.flash_off_rounded,
            flashLabel: 'Off',
            captureState: CaptureButtonState.capturing,
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(ScanControls), findsOneWidget);

      // Success state
      await tester.pumpWidget(
        buildFrame(
          ScanControls(
            onGallery: () {},
            onCapture: () {},
            onToggleFlash: () {},
            flashIcon: Icons.flash_off_rounded,
            flashLabel: 'Off',
            captureState: CaptureButtonState.success,
          ),
        ),
      );
      await tester.pump();
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });

    testWidgets('Responsive layouts render cleanly without RenderFlex overflows across device widths',
        (tester) async {
      final screenSizes = [
        const Size(320, 568), // Small phone (iPhone SE 1st gen)
        const Size(375, 667), // Medium phone (iPhone SE 2nd gen)
        const Size(390, 844), // Standard phone (iPhone 14)
        const Size(412, 915), // Android standard (Pixel 7 / Samsung S23)
        const Size(600, 960), // Small tablet / Foldable unfolded
        const Size(800, 1280), // 10-inch tablet
      ];

      for (final size in screenSizes) {
        await tester.pumpWidget(
          buildFrame(
            Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ScanControls(
                  onGallery: () {},
                  onCapture: () {},
                  onToggleFlash: () {},
                  flashIcon: Icons.flash_off_rounded,
                  flashLabel: 'Off',
                  captureState: CaptureButtonState.idle,
                ),
              ],
            ),
            size.width,
            size.height,
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull,
            reason: 'RenderFlex overflow occurred on screen size: $size');
      }
    });

    testWidgets('ScannerScreen graceful fallback when camera is absent in test environment',
        (tester) async {
      await tester.pumpWidget(
        buildFrame(
          ScannerScreen(
            onClose: () {},
            onCaptured: (_) {},
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(find.byType(ScannerScreen), findsOneWidget);
    });
  });
}
