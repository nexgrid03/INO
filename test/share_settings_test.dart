import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/models/share_settings.dart';

void main() {
  group('ShareSettings', () {
    test('defaults require no processing (plain copy of the original)', () {
      const s = ShareSettings();
      expect(s.colorMode, ShareColorMode.original);
      expect(s.requiresImageProcessing, isFalse);
      expect(s.wrapsInPdf, isFalse);
      expect(s.duration, ShareDuration.twentyFourHours);
    });

    test('black & white requires processing but is not a PDF', () {
      const s = ShareSettings(colorMode: ShareColorMode.blackWhite);
      expect(s.requiresImageProcessing, isTrue);
      expect(s.wrapsInPdf, isFalse);
    });

    test('grayscale requires processing but is not a PDF', () {
      const s = ShareSettings(colorMode: ShareColorMode.grayscale);
      expect(s.requiresImageProcessing, isTrue);
      expect(s.wrapsInPdf, isFalse);
    });

    test('compressed PDF wraps in a PDF and requires processing', () {
      const s = ShareSettings(colorMode: ShareColorMode.compressedPdf);
      expect(s.wrapsInPdf, isTrue);
      expect(s.requiresImageProcessing, isTrue);
    });

    test('copyWith updates only the given fields', () {
      const s = ShareSettings();
      final updated = s.copyWith(
        colorMode: ShareColorMode.blackWhite,
        duration: ShareDuration.sevenDays,
      );
      expect(updated.colorMode, ShareColorMode.blackWhite);
      expect(updated.duration, ShareDuration.sevenDays);
      // original is unchanged (immutable value object)
      expect(s.colorMode, ShareColorMode.original);
      expect(s.duration, ShareDuration.twentyFourHours);
    });

    test('copy-style labels are the user-facing option names', () {
      expect(ShareColorMode.original.label, 'Original Color');
      expect(ShareColorMode.blackWhite.label, 'Black & White');
      expect(ShareColorMode.grayscale.label, 'Grayscale');
      expect(ShareColorMode.compressedPdf.label, 'Compressed PDF');
    });
  });
}
