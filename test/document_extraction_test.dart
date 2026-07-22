import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/models/document_extraction.dart';

void main() {
  group('DocumentExtraction', () {
    test('encodes and decodes a full envelope round-trip', () {
      const original = DocumentExtraction(
        documentType: 'aadhaar',
        data: {
          'name': 'Tanishq',
          'number': 'XXXX XXXX 1234',
          'dob': '17/12/2006',
          'gender': 'Male',
        },
        userNotes: 'Primary ID',
      );

      final decoded = DocumentExtraction.decode(original.encode());

      expect(decoded.documentType, 'aadhaar');
      expect(decoded.data['name'], 'Tanishq');
      expect(decoded.data['number'], 'XXXX XXXX 1234');
      expect(decoded.data['dob'], '17/12/2006');
      expect(decoded.data['gender'], 'Male');
      expect(decoded.userNotes, 'Primary ID');
      expect(decoded.hasData, isTrue);
    });

    test('decode(null) and decode("") are empty', () {
      expect(DocumentExtraction.decode(null).isEmpty, isTrue);
      expect(DocumentExtraction.decode('').isEmpty, isTrue);
      expect(DocumentExtraction.decode('   ').hasData, isFalse);
    });

    test('recovers legacy "Label: value" OCR notes into structured fields', () {
      const legacy = 'Name: Tanishq\nDOB: 17/12/2006\nGender: Male';
      final decoded = DocumentExtraction.decode(legacy);

      expect(decoded.data['name'], 'Tanishq');
      expect(decoded.data['dob'], '17/12/2006');
      expect(decoded.data['gender'], 'Male');
    });

    test('plain free text becomes userNotes, not fields', () {
      final decoded = DocumentExtraction.decode('Remember to renew this soon');
      expect(decoded.hasData, isFalse);
      expect(decoded.userNotes, 'Remember to renew this soon');
    });

    test('label resolves the number field by document type', () {
      expect(DocumentExtraction.labelFor('aadhaar', 'number'), 'Aadhaar Number');
      expect(DocumentExtraction.labelFor('pan', 'number'), 'PAN Number');
      expect(DocumentExtraction.labelFor('passport', 'number'), 'Passport Number');
      expect(DocumentExtraction.labelFor('drivingLicense', 'number'),
          'License Number');
      expect(DocumentExtraction.labelFor('voterId', 'number'), 'EPIC Number');
      expect(DocumentExtraction.labelFor(null, 'number'), 'Document Number');
      expect(DocumentExtraction.labelFor('aadhaar', 'name'), 'Full Name');
    });

    test('typeKeyFromLabel maps detected labels to semantic keys', () {
      expect(DocumentExtraction.typeKeyFromLabel('Aadhaar Card'), 'aadhaar');
      expect(DocumentExtraction.typeKeyFromLabel('PAN Card'), 'pan');
      expect(DocumentExtraction.typeKeyFromLabel('Passport'), 'passport');
      expect(DocumentExtraction.typeKeyFromLabel('Driving License'),
          'drivingLicense');
      expect(DocumentExtraction.typeKeyFromLabel('Voter ID'), 'voterId');
      expect(DocumentExtraction.typeKeyFromLabel('Document'), isNull);
    });

    test('searchableText includes every value and the notes', () {
      const ext = DocumentExtraction(
        documentType: 'pan',
        data: {'name': 'Tanishq', 'number': 'ABCDE1234F'},
        userNotes: 'tax file',
      );
      final text = ext.searchableText.toLowerCase();
      expect(text.contains('tanishq'), isTrue);
      expect(text.contains('abcde1234f'), isTrue);
      expect(text.contains('tax file'), isTrue);
    });

    test('displayFields orders name → number → dob and labels them', () {
      const ext = DocumentExtraction(
        documentType: 'aadhaar',
        data: {'gender': 'Male', 'number': '1234', 'name': 'Tanishq'},
      );
      final fields = ext.displayFields();
      expect(fields.first.label, 'Full Name');
      expect(fields[1].label, 'Aadhaar Number');
      expect(fields.map((f) => f.value), contains('Male'));
    });
  });
}
