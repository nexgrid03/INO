import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/models/payment_qr.dart';

/// A realistic static merchant BharatQR (EMVCo TLV), built field by field:
///   000201                      payload format indicator "01"
///   010211                      point of initiation "11" (static)
///   2626 0003upi 0115merchant@okaxis   merchant account template → UPI VPA
///   52045411                    merchant category code
///   5303356                     currency 356 = INR
///   540525.00                   amount
///   5802IN                      country
///   5908TestShop                merchant name
const _bharatQr = '000201'
    '010211'
    '26260003upi0115merchant@okaxis'
    '52045411'
    '5303356'
    '540525.00'
    '5802IN'
    '5908TestShop';

void main() {
  group('UPI deep links', () {
    test('a standard upi:// QR parses into a payment request', () {
      final p = PaymentQrParser.parse(
          'upi://pay?pa=shop@okhdfcbank&pn=Chai%20Shop&am=120.50&cu=INR&tn=Tea');
      expect(p, isNotNull);
      expect(p!.payeeAddress, 'shop@okhdfcbank');
      expect(p.payeeName, 'Chai Shop');
      expect(p.amount, '120.50');
      expect(p.amountValue, 120.50);
      expect(p.currency, 'INR');
      expect(p.note, 'Tea');
      expect(p.isOpenAmount, isFalse);
    });

    test('a QR with no amount leaves the amount open for the payer', () {
      final p = PaymentQrParser.parse('upi://pay?pa=friend@okicici&pn=Asha');
      expect(p, isNotNull);
      expect(p!.isOpenAmount, isTrue);
      expect(p.amountValue, isNull);
      expect(p.displayName, 'Asha');
    });

    test('the payee falls back to the VPA when the QR carries no name', () {
      final p = PaymentQrParser.parse('upi://pay?pa=friend@okicici');
      expect(p!.displayName, 'friend@okicici');
    });

    test('an app-specific QR is rewritten so ANY app can pay it', () {
      // The whole point: a Google Pay QR must still be payable with PhonePe.
      final p = PaymentQrParser.parse('gpay://upi/pay?pa=shop@oksbi&am=40');
      expect(p, isNotNull);
      expect(p!.uri, startsWith('upi://pay?'));
      expect(p.uri, contains('pa=shop%40oksbi'));
      expect(p.payeeAddress, 'shop@oksbi');
    });

    test('unknown query keys are dropped from the rebuilt URI', () {
      final p = PaymentQrParser.parse(
          'upi://pay?pa=shop@oksbi&am=10&evil=1&redirect=http://x');
      expect(p!.uri, isNot(contains('evil')));
      expect(p.uri, isNot(contains('redirect')));
    });

    test('merchant QRs are told apart from person-to-person ones', () {
      final merchant =
          PaymentQrParser.parse('upi://pay?pa=shop@oksbi&mc=5411&tr=INV77');
      final person = PaymentQrParser.parse('upi://pay?pa=asha@okaxis');
      expect(merchant!.isMerchant, isTrue);
      expect(person!.isMerchant, isFalse);
    });
  });

  group('rejecting things that are not payments', () {
    test('a upi:// URI with no payee address is not a payment', () {
      expect(PaymentQrParser.parse('upi://pay?pn=NoAddress'), isNull);
    });

    test('a malformed VPA is rejected rather than guessed at', () {
      for (final bad in [
        'upi://pay?pa=nohandle',
        'upi://pay?pa=@okaxis',
        'upi://pay?pa=two@at@signs',
        'upi://pay?pa=trailing@',
      ]) {
        expect(PaymentQrParser.parse(bad), isNull, reason: bad);
      }
    });

    test('ordinary links and text are not payments', () {
      expect(PaymentQrParser.parse('https://example.com'), isNull);
      expect(PaymentQrParser.parse('just some text'), isNull);
      expect(PaymentQrParser.parse(''), isNull);
    });
  });

  group('EMVCo / BharatQR merchant codes', () {
    test('the VPA is pulled out of the nested merchant template', () {
      final p = PaymentQrParser.parse(_bharatQr);
      expect(p, isNotNull);
      expect(p!.payeeAddress, 'merchant@okaxis');
      expect(p.payeeName, 'TestShop');
      expect(p.amount, '25.00');
      expect(p.currency, 'INR');
      expect(p.merchantCode, '5411');
    });

    test('it is normalised to a upi:// URI a payment app can open', () {
      final p = PaymentQrParser.parse(_bharatQr);
      expect(p!.uri, startsWith('upi://pay?'));
      expect(p.uri, contains('pa=merchant%40okaxis'));
    });

    test('a truncated TLV blob is refused, not half-parsed', () {
      // Length byte claims 15 chars but only 4 remain.
      expect(PaymentQrParser.parse('00020126260003upi0115merc'), isNull);
    });

    test('an EMVCo blob with no UPI template is not a payment', () {
      expect(PaymentQrParser.parse('000201010211530335654045.005802IN'), isNull);
    });
  });

  group('classifying a scanned QR', () {
    test('a payment QR routes to the payment picker', () {
      final s = ScannedQr.classify('upi://pay?pa=shop@oksbi&am=10');
      expect(s.kind, ScannedQrKind.payment);
      expect(s.isPayment, isTrue);
      expect(s.payment, isNotNull);
    });

    test('a BharatQR blob routes to the payment picker too', () {
      expect(ScannedQr.classify(_bharatQr).kind, ScannedQrKind.payment);
    });

    test('INO share links route in-app, not to a browser', () {
      expect(ScannedQr.classify('https://ino-share-web.vercel.app/s/abc123').kind,
          ScannedQrKind.inoShare);
      expect(ScannedQr.classify('https://ino-share-web.vercel.app/v/abc123').kind,
          ScannedQrKind.inoShare);
      expect(ScannedQr.classify('ino://viewonce/abc123').kind,
          ScannedQrKind.inoShare);
    });

    test('an ordinary link is a link', () {
      expect(ScannedQr.classify('https://example.com/page').kind,
          ScannedQrKind.link);
    });

    test('anything else is plain text', () {
      expect(ScannedQr.classify('hello world').kind, ScannedQrKind.text);
      expect(ScannedQr.classify('   ').kind, ScannedQrKind.text);
    });

    test('the raw payload is preserved verbatim for display/copy', () {
      const raw = 'hello world';
      expect(ScannedQr.classify(raw).raw, raw);
    });
  });
}
