import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/models/ocr_result_model.dart';
import 'package:inoapp/services/aadhaar_parser.dart';
import 'package:inoapp/services/document_detector.dart';
import 'package:inoapp/services/pan_parser.dart';

/// Realistic multi-line OCR output for an Aadhaar card (as ML Kit would return).
const _aadhaarText = '''
Government of India
Unique Identification Authority of India
Rahul Kumar
DOB: 01/01/1998
Male
2345 6789 0123
''';

const _panText = '''
INCOME TAX DEPARTMENT
GOVT. OF INDIA
Permanent Account Number
ABCDE1234F
Name
RAHUL KUMAR
Father's Name
SURESH KUMAR
Date of Birth
01/01/1998
''';

List<String> _lines(String text) =>
    text.trim().split('\n').map((l) => l.trim()).toList();

void main() {
  group('DocumentDetector', () {
    test('detects Aadhaar from its keywords', () {
      final r = DocumentDetector.detect(_aadhaarText);
      expect(r.type, IdDocumentType.aadhaar);
      expect(r.confidence, greaterThan(0.3));
    });

    test('detects PAN from its keywords', () {
      final r = DocumentDetector.detect(_panText);
      expect(r.type, IdDocumentType.pan);
      expect(r.confidence, greaterThan(0.3));
    });

    test('returns unknown for unrelated text', () {
      final r = DocumentDetector.detect('a shopping receipt for groceries');
      expect(r.type, IdDocumentType.unknown);
      expect(r.confidence, 0);
    });
  });

  group('AadhaarParser', () {
    final fields = AadhaarParser.parse(_aadhaarText, _lines(_aadhaarText));

    test('extracts a clean 12-digit number (spaces removed)', () {
      expect(fields['number'], '234567890123');
      expect(AadhaarParser.isValid(fields['number']!), isTrue);
    });

    test('extracts name, dob and gender', () {
      expect(fields['name'], 'Rahul Kumar');
      expect(fields['dob'], '01/01/1998');
      expect(fields['gender'], 'Male');
    });

    test('rejects malformed numbers', () {
      expect(AadhaarParser.isValid('1234'), isFalse);
      expect(AadhaarParser.isValid('ABCD12345678'), isFalse);
      expect(AadhaarParser.isValid('1234 5678 9012'), isTrue); // spec example
    });
  });

  group('AadhaarParser accuracy', () {
    List<String> lines(String t) =>
        t.trim().split('\n').map((l) => l.trim()).toList();

    test('never picks a heading as the name', () {
      const t = '''
Government of India
Unique Identification Authority of India
UIDAI
Ramesh Kumar Gupta
DOB: 15/08/1990
Male
9876 5432 1012
''';
      final f = AadhaarParser.parse(t, lines(t));
      expect(f['name'], 'Ramesh Kumar Gupta');
      expect(f['dob'], '15/08/1990');
    });

    test('prefers the labelled DOB over an enrolment/print date above it', () {
      // A print/enrolment date sits at the top; the real DOB is labelled below.
      const t = '''
Government of India
Date: 12/03/2015
Rahul Kumar
DOB: 01/01/1998
Male
2345 6789 0123
''';
      final f = AadhaarParser.parse(t, lines(t));
      expect(f['dob'], '01/01/1998'); // not 12/03/2015
      expect(f['name'], 'Rahul Kumar');
    });

    test('reads a Year of Birth when no full date is present', () {
      const t = '''
Government of India
Sita Devi
Year of Birth: 1975
Female
3456 7890 1234
''';
      final f = AadhaarParser.parse(t, lines(t));
      expect(f['dob'], '1975');
      expect(f['name'], 'Sita Devi');
      expect(f['gender'], 'Female');
    });

    test('ignores VID and picks the 12-digit Aadhaar number', () {
      const t = '''
Rahul Kumar
DOB: 01/01/1998
Male
VID : 9123 4567 8901 2345
2345 6789 0123
''';
      final f = AadhaarParser.parse(t, lines(t));
      expect(f['number'], '234567890123');
      expect(AadhaarParser.isValid(f['number']!), isTrue);
    });

    // The exact real-world OCR output reported by the user.
    test('handles noisy real OCR (DO8 label, merged date, glued gender)', () {
      const t = '''
Government of India
Jujuri Tanishq Vijaya Sai
Dgs d6I DO8:17/1212006
DdzyaIMale
8255 4111 2736
''';
      final f = AadhaarParser.parse(t, lines(t));
      expect(f['name'], 'Jujuri Tanishq Vijaya Sai');
      expect(f['dob'], '17/12/2006');
      expect(f['gender'], 'Male');
      expect(f['number'], '825541112736');
    });

    test('rejects garbled UIDAI header via fuzzy matching', () {
      const t = '''
Government of lndia
Iniaue Ldentification Auttaaritv Of Lndia
Jujuri Tanishq Vijaya Sai
Dgs d6I DO8:17/1212006
DdzyaIMale
8255 4111 2736
''';
      final f = AadhaarParser.parse(t, lines(t));
      expect(f['name'], 'Jujuri Tanishq Vijaya Sai');
      expect(f['dob'], '17/12/2006');
    });

    test('recognises DOB / DO8 / D0B label variants', () {
      for (final label in ['DOB', 'DO8', 'D0B', 'D08']) {
        final t = 'Rahul Kumar\n$label:17/12/2006\nMale\n2345 6789 0123';
        final f = AadhaarParser.parse(t, lines(t));
        expect(f['dob'], '17/12/2006', reason: 'label "$label"');
        expect(f['name'], 'Rahul Kumar', reason: 'label "$label"');
      }
    });

    test('rejects an enrolment date as DOB', () {
      const t = '''
Rahul Kumar
DOB: 01/01/1998
Male
Enrollment No 2017/60443/25547
10/12/2014
2345 6789 0123
''';
      final f = AadhaarParser.parse(t, lines(t));
      expect(f['dob'], '01/01/1998'); // not the 10/12/2014 enrolment date
    });

    test('extracts a labelled YYYY/MM/DD date, normalised to DD/MM/YYYY', () {
      const t = '''
Government of India
Jujuri Tanishq Vijaya Sai
DOB: 2006/12/17
Male
8255 4111 2736
''';
      final f = AadhaarParser.parse(t, lines(t));
      expect(f['dob'], '17/12/2006');
      expect(f['name'], 'Jujuri Tanishq Vijaya Sai');
      expect(f['number'], '825541112736');
    });

    test('extracts a labelled YYYY-MM-DD date', () {
      const t = 'Rahul Kumar\nDOB: 2006-12-17\nMale\n2345 6789 0123';
      final f = AadhaarParser.parse(t, lines(t));
      expect(f['dob'], '17/12/2006');
      expect(f['name'], 'Rahul Kumar');
    });

    test('extracts an unlabelled YYYY/MM/DD date', () {
      const t = 'Sita Devi\n2006/12/17\nFemale\n3456 7890 1234';
      final f = AadhaarParser.parse(t, lines(t));
      expect(f['dob'], '17/12/2006');
      expect(f['name'], 'Sita Devi');
    });

    test('extracts a 12-digit Aadhaar number with no separators', () {
      const t = 'Rahul Kumar\nDOB: 01/01/1998\nMale\n825541112736';
      final f = AadhaarParser.parse(t, lines(t));
      expect(f['number'], '825541112736');
      expect(AadhaarParser.isValid(f['number']!), isTrue);
    });

    test('extracts a hyphen-separated Aadhaar number', () {
      const t = 'Rahul Kumar\nDOB: 01/01/1998\nMale\n8255-4111-2736';
      final f = AadhaarParser.parse(t, lines(t));
      expect(f['number'], '825541112736');
      expect(AadhaarParser.isValid(f['number']!), isTrue);
    });

    test('handles a scanned card with noisy spacing and uppercase', () {
      const t = '''
GOVERNMENT  OF  INDIA
UNIQUE  IDENTIFICATION  AUTHORITY  OF  INDIA
Ramesh   Kumar   Gupta
DOB :  15 / 08 / 1990
MALE
9876  5432  1012
''';
      final f = AadhaarParser.parse(t, lines(t));
      expect(f['name'], 'Ramesh Kumar Gupta');
      expect(f['dob'], '15/08/1990');
      expect(f['gender'], 'Male');
      expect(f['number'], '987654321012');
    });

    test('parses fields regardless of line order (rotated/reflowed scan)', () {
      const t = '''
8255 4111 2736
Male
DOB: 17/12/2006
Jujuri Tanishq Vijaya Sai
Government of India
''';
      final f = AadhaarParser.parse(t, lines(t));
      expect(f['number'], '825541112736');
      expect(f['dob'], '17/12/2006');
      expect(f['gender'], 'Male');
      expect(f['name'], 'Jujuri Tanishq Vijaya Sai');
    });

    test('resolves fuzzy gender spellings', () {
      String? g(String token) =>
          AadhaarParser.parse('Rahul Kumar\nDOB: 01/01/1998\n$token',
              ['Rahul Kumar', 'DOB: 01/01/1998', token])['gender'];
      expect(g('Male'), 'Male');
      expect(g('Mle'), 'Male');
      expect(g('Malee'), 'Male');
      expect(g('Female'), 'Female');
      expect(g('FemaIe'), 'Female');
    });
  });

  group('PanParser', () {
    final fields = PanParser.parse(_panText, _lines(_panText));

    test('extracts and validates the PAN number', () {
      expect(fields['number'], 'ABCDE1234F');
      expect(PanParser.isValid('ABCDE1234F'), isTrue);
      expect(PanParser.isValid('abcde1234f'), isTrue); // case-insensitive
      expect(PanParser.isValid('ABCD1234F'), isFalse); // 4 letters
      expect(PanParser.isValid('ABCDE12345'), isFalse); // wrong shape
    });

    test('extracts name, father name and dob', () {
      expect(fields['name'], 'Rahul Kumar');
      expect(fields['fatherName'], 'Suresh Kumar');
      expect(fields['dob'], '01-01-1998');
    });
  });

  group('OcrExtraction → OcrResult mapping', () {
    test('maps a PAN extraction to an Identity-wallet result', () {
      final extraction = OcrExtraction(
        type: IdDocumentType.pan,
        typeConfidence: 0.9,
        fields: PanParser.parse(_panText, _lines(_panText)),
        rawText: _panText,
      );
      final result = extraction.toOcrResult();
      expect(result.detectedType, 'PAN Card');
      expect(result.suggestedWallet, 'Identity Wallet');
      expect(result.category, 'Identity');
      expect(result.documentNumber, 'ABCDE1234F');
      expect(result.fullName, 'Rahul Kumar');
      expect(result.fatherName, 'Suresh Kumar');
      expect(result.tags, contains('pan'));
    });

    test('unknown documents fall back to the Document wallet', () {
      const extraction = OcrExtraction(
        type: IdDocumentType.unknown,
        typeConfidence: 0,
        fields: {},
        rawText: 'nothing useful',
      );
      final result = extraction.toOcrResult();
      expect(result.suggestedWallet, 'Document Wallet');
      expect(result.category, 'Other');
      expect(result.documentName, '');
    });
  });
}
