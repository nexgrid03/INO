import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/repositories/qr_code_repository.dart';

/// A 1x1 PNG - enough to prove the base64 round trip without a fixture file.
final _png = base64Encode(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
]);

void main() {
  group('mapping a stored QR row', () {
    test('a full row maps onto the model', () {
      final qr = UserQr.fromRow({
        'image_base64': _png,
        'label': 'My GPay QR',
        'payload': 'upi://pay?pa=shop@oksbi&pn=Chai%20Shop',
        'payee_vpa': 'shop@oksbi',
        'payee_name': 'Chai Shop',
        'width': 600,
        'height': 600,
        'updated_at': '2026-08-07T10:00:00.000Z',
      });

      expect(qr, isNotNull);
      expect(qr!.bytes, isNotEmpty);
      expect(qr.label, 'My GPay QR');
      expect(qr.payeeVpa, 'shop@oksbi');
      expect(qr.width, 600);
      expect(qr.updatedAt, isNotNull);
    });

    test('the payee name is preferred over the VPA for display', () {
      final qr = UserQr.fromRow({
        'image_base64': _png,
        'payee_vpa': 'shop@oksbi',
        'payee_name': 'Chai Shop',
      });
      expect(qr!.subtitle, 'Chai Shop');
    });

    test('the VPA is the fallback when there is no name', () {
      final qr = UserQr.fromRow({
        'image_base64': _png,
        'payee_vpa': 'shop@oksbi',
      });
      expect(qr!.subtitle, 'shop@oksbi');
    });

    test('a blank name does not win over the VPA', () {
      final qr = UserQr.fromRow({
        'image_base64': _png,
        'payee_vpa': 'shop@oksbi',
        'payee_name': '   ',
      });
      expect(qr!.subtitle, 'shop@oksbi');
    });

    test('an image with no decoded code still renders, with no subtitle', () {
      // Uploading a photo the scanner could not read is allowed - the image is
      // kept rather than the upload refused.
      final qr = UserQr.fromRow({'image_base64': _png});
      expect(qr, isNotNull);
      expect(qr!.payload, isNull);
      expect(qr.subtitle, isNull);
    });
  });

  group('refusing rows that cannot be rendered', () {
    test('a row with no image is not a QR', () {
      expect(UserQr.fromRow({'payee_vpa': 'shop@oksbi'}), isNull);
    });

    test('an empty image is not a QR', () {
      expect(UserQr.fromRow({'image_base64': ''}), isNull);
    });

    test('corrupt base64 degrades to "no QR" rather than throwing', () {
      // Home must render its empty state, never crash, on a bad row.
      expect(UserQr.fromRow({'image_base64': 'not!valid!base64!'}), isNull);
    });
  });
}
