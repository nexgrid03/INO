import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/models/document_extraction.dart';
import 'package:inoapp/models/ocr_result_model.dart';
import 'package:inoapp/services/driving_license_parser.dart';
import 'package:inoapp/services/passport_parser.dart';
import 'package:inoapp/services/voter_id_parser.dart';

List<String> _lines(String s) =>
    s.trim().split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

void main() {
  group('PassportParser', () {
    const text = '''
REPUBLIC OF INDIA
PASSPORT
Type P Country Code IND Passport No A1234567
Surname SHARMA
Given Name(s) RAHUL
Nationality INDIAN
Date of Birth 17/12/1990
Sex M
Place of Issue DELHI
Date of Issue 05/06/2018
Date of Expiry 04/06/2028
''';

    test('extracts number, name, dob, expiry and nationality', () {
      final f = PassportParser.parse(text, _lines(text));
      expect(f['number'], 'A1234567');
      expect(f['name'], 'Rahul Sharma');
      expect(f['dob'], '17/12/1990');
      expect(f['expiryDate'], '04/06/2028');
      expect(f['nationality'], 'Indian');
    });

    test('does not confuse issue date with date of birth', () {
      final f = PassportParser.parse(text, _lines(text));
      expect(f['dob'], isNot('05/06/2018'));
    });
  });

  group('DrivingLicenseParser', () {
    const text = '''
INDIA UNION DRIVING LICENCE
DL No MH12 20110012345
Name RAHUL SHARMA
Son/Daughter/Wife of SURESH SHARMA
Date of Birth 17/12/1990
Blood Group B+
Valid Till 16/12/2040
COV LMV MCWG
''';

    test('extracts number, name, dob, validity and vehicle class', () {
      final f = DrivingLicenseParser.parse(text, _lines(text));
      expect(f['number'], 'MH12 20110012345');
      expect(f['name'], 'Rahul Sharma');
      expect(f['dob'], '17/12/1990');
      expect(f['validity'], '16/12/2040');
      expect(f['vehicleClass'], 'LMV, MCWG');
    });
  });

  group('VoterIdParser', () {
    const text = '''
ELECTION COMMISSION OF INDIA
ELECTOR PHOTO IDENTITY CARD
EPIC No ABC1234567
Elector's Name RAHUL SHARMA
Father's Name SURESH SHARMA
Sex Male
Date of Birth 17/12/1990
''';

    test('extracts EPIC number, name, gender and dob', () {
      final f = VoterIdParser.parse(text, _lines(text));
      expect(f['number'], 'ABC1234567');
      expect(f['name'], 'Rahul Sharma');
      expect(f['gender'], 'Male');
      expect(f['dob'], '17/12/1990');
    });

    test('does not treat the card heading as the name', () {
      final f = VoterIdParser.parse(text, _lines(text));
      expect(f['name'], isNot(contains('Identity')));
    });
  });
}
