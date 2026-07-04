import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/utils/date_normalizer.dart';

void main() {
  group('DateNormalizer.normalizeDob', () {
    test('all supported formats normalize to DD/MM/YYYY', () {
      expect(DateNormalizer.normalizeDob('2006/12/17'), '17/12/2006'); // YYYY/MM/DD
      expect(DateNormalizer.normalizeDob('2006-12-17'), '17/12/2006'); // YYYY-MM-DD
      expect(DateNormalizer.normalizeDob('17/12/2006'), '17/12/2006'); // DD/MM/YYYY
      expect(DateNormalizer.normalizeDob('17-12-2006'), '17/12/2006'); // DD-MM-YYYY
      expect(DateNormalizer.normalizeDob('17.12.2006'), '17/12/2006'); // DD.MM.YYYY
    });

    test('single-digit day/month are zero-padded', () {
      expect(DateNormalizer.normalizeDob('2006/1/7'), '07/01/2006');
      expect(DateNormalizer.normalizeDob('1/2/2006'), '01/02/2006');
    });

    test('Aadhaar label variants (DOB / DO8 / D0B) are stripped', () {
      expect(DateNormalizer.normalizeDob('DOB: 2006/12/17'), '17/12/2006');
      expect(DateNormalizer.normalizeDob('DOB: 17/12/2006'), '17/12/2006');
      expect(DateNormalizer.normalizeDob('DO8: 2006-12-17'), '17/12/2006');
      expect(DateNormalizer.normalizeDob('D0B: 17-12-2006'), '17/12/2006');
    });

    test('a bare Year of Birth is preserved', () {
      expect(DateNormalizer.normalizeDob('1975'), '1975');
      expect(DateNormalizer.normalizeDob('Year of Birth: 1975'), '1975');
    });

    test('null / empty pass through', () {
      expect(DateNormalizer.normalizeDob(null), isNull);
      expect(DateNormalizer.normalizeDob('   '), isNull);
    });

    test('unparseable values are returned unchanged (never fabricated)', () {
      expect(DateNormalizer.normalizeDob('not a date'), 'not a date');
      // Impossible month → not silently "corrected"; kept as-is.
      expect(DateNormalizer.normalizeDob('2006/13/40'), '2006/13/40');
    });

    test('idempotent — normalizing an already-normalized value is stable', () {
      expect(DateNormalizer.normalizeDob('17/12/2006'), '17/12/2006');
    });
  });
}
