import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/utils/identifier_masker.dart';

void main() {
  group('IdentifierMasker', () {
    test('masks Aadhaar 12-digit numbers as XXXX XXXX 1234', () {
      expect(IdentifierMasker.mask('123456789012', docType: 'aadhaar'), 'XXXX XXXX 9012');
      expect(IdentifierMasker.mask('9876 5432 1098', docType: 'Aadhaar Card'), 'XXXX XXXX 1098');
    });

    test('masks PAN 10-char numbers as ABCDE****F', () {
      expect(IdentifierMasker.mask('ABCDE1234F', docType: 'pan'), 'ABCDE****F');
      expect(IdentifierMasker.mask('qwert5678z', docType: 'PAN Card'), 'QWERT****Z');
    });

    test('masks Passport numbers showing prefix and last 2 digits', () {
      expect(IdentifierMasker.mask('P1234567', docType: 'passport'), 'P*****67');
      expect(IdentifierMasker.mask('Z12345678', docType: 'Passport'), 'Z******78');
    });

    test('masks Driving License and general identifiers showing last 4 characters', () {
      expect(IdentifierMasker.mask('MH0120110012345', docType: 'drivingLicense'), '***********2345');
      expect(IdentifierMasker.mask('EPIC9876543', docType: 'voterId'), '*******6543');
    });

    test('returns last 4 digits correctly', () {
      expect(IdentifierMasker.last4('123456789012'), '9012');
      expect(IdentifierMasker.last4('ABCDE1234F'), '234F');
    });
  });
}
