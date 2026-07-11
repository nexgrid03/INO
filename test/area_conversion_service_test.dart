import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/models/area_unit.dart';
import 'package:inoapp/services/area_conversion_service.dart';

void main() {
  const svc = AreaConversionService.instance;

  double conv(double v, AreaUnit from, AreaUnit to) => svc.convert(v, from, to);

  group('required conversions', () {
    test('312 Sq.M -> Sq.Yards ~= 373.15', () {
      final r = conv(312, AreaUnit.squareMetres, AreaUnit.squareYards);
      expect(r, closeTo(373.1489, 0.001));
      expect(svc.format(r), '373.15');
    });

    test('1 Acre -> Guntas == 40', () {
      expect(conv(1, AreaUnit.acres, AreaUnit.guntas), closeTo(40, 1e-9));
    });

    test('1 Acre -> Cents == 100', () {
      expect(conv(1, AreaUnit.acres, AreaUnit.cents), closeTo(100, 1e-9));
    });

    test('1000 Sq.Ft -> Sq.Yards ~= 111.11', () {
      final r = conv(1000, AreaUnit.squareFeet, AreaUnit.squareYards);
      expect(r, closeTo(111.1111, 0.001));
      expect(svc.format(r), '111.11');
    });

    test('1 Gunta -> Sq.Ft == 1089', () {
      expect(conv(1, AreaUnit.guntas, AreaUnit.squareFeet), closeTo(1089, 1e-9));
    });
  });

  group('spec reference table (1 Acre)', () {
    test('43560 Sq.Ft, 4840 Sq.Yd, 4046.8564224 Sq.M, 100 Cents, 40 Guntas', () {
      expect(conv(1, AreaUnit.acres, AreaUnit.squareFeet), closeTo(43560, 1e-6));
      expect(conv(1, AreaUnit.acres, AreaUnit.squareYards), closeTo(4840, 1e-6));
      expect(conv(1, AreaUnit.acres, AreaUnit.squareMetres),
          closeTo(4046.8564224, 1e-6));
      expect(conv(1, AreaUnit.acres, AreaUnit.cents), closeTo(100, 1e-9));
      expect(conv(1, AreaUnit.acres, AreaUnit.guntas), closeTo(40, 1e-9));
    });

    test('1 Gunta = 121 Sq.Yd = 0.025 Acre', () {
      expect(conv(1, AreaUnit.guntas, AreaUnit.squareYards), closeTo(121, 1e-9));
      expect(conv(1, AreaUnit.guntas, AreaUnit.acres), closeTo(0.025, 1e-12));
    });

    test('1 Cent = 48.4 Sq.Yd = 435.6 Sq.Ft', () {
      expect(conv(1, AreaUnit.cents, AreaUnit.squareYards), closeTo(48.4, 1e-9));
      expect(conv(1, AreaUnit.cents, AreaUnit.squareFeet), closeTo(435.6, 1e-9));
    });

    test('1 Ankanam = 72 Sq.Ft', () {
      expect(
          conv(1, AreaUnit.ankanam, AreaUnit.squareFeet), closeTo(72, 1e-9));
    });
  });

  group('round-trip stability', () {
    test('converting there and back is lossless', () {
      for (final from in AreaUnit.values) {
        for (final to in AreaUnit.values) {
          final there = conv(123.456, from, to);
          final back = conv(there, to, from);
          expect(back, closeTo(123.456, 1e-9),
              reason: '$from <-> $to round-trip');
        }
      }
    });

    test('same unit is identity', () {
      expect(conv(999.99, AreaUnit.cents, AreaUnit.cents), 999.99);
    });
  });

  group('formatting', () {
    test('2 decimals for values >= 1, trailing zeros stripped', () {
      expect(svc.format(3358.34006), '3358.34');
      expect(svc.format(4840), '4840');
      expect(svc.format(100), '100');
      expect(svc.format(3.0839), '3.08');
      expect(svc.format(7.70), '7.7'); // trailing zero removed
    });

    test('keeps significant figures for small values', () {
      expect(svc.format(0.077097), '0.077');
      expect(svc.format(0.0312), '0.031');
      expect(svc.format(0.025), '0.025');
    });

    test('zero and non-finite are "0"', () {
      expect(svc.format(0), '0');
      expect(svc.format(double.nan), '0');
      expect(svc.format(double.infinity), '0');
    });
  });

  group('summary + copy text', () {
    test('summary excludes the source unit and covers the rest', () {
      final s = svc.summary(312, AreaUnit.squareMetres);
      expect(s.any((c) => c.unit == AreaUnit.squareMetres), isFalse);
      expect(s.length, AreaUnit.values.length - 1);
      final yd = s.firstWhere((c) => c.unit == AreaUnit.squareYards);
      expect(yd.display, '373.15');
    });

    test('asCopyText renders a readable block', () {
      final text = svc.asCopyText(312, AreaUnit.squareMetres);
      expect(text, startsWith('312 Sq.M ='));
      expect(text, contains('373.15 Sq.Yards'));
      expect(text, contains('3358.34 Sq.Ft'));
    });
  });
}
