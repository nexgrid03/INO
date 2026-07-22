import 'ocr_text_utils.dart';

/// Extracts fields from an Indian Voter ID (EPIC) card's OCR text.
///
/// Layout cues: an EPIC number of 3 letters + 7 digits (e.g. `ABC1234567`);
/// an "Elector's Name" label; gender; and a date of birth (or "Age as on").
class VoterIdParser {
  VoterIdParser._();

  static final RegExp _numberRe = RegExp(r'\b([A-Z]{3}[0-9]{7})\b');

  /// Returns `{number, name, gender, dob}` (values may be null).
  static Map<String, String?> parse(String text, List<String> lines) {
    final clean = [
      for (final l in lines) l.trim().replaceAll(RegExp(r'\s+'), ' '),
    ].where((l) => l.isNotEmpty).toList();

    return {
      'number': _numberRe.firstMatch(text.toUpperCase())?[1],
      'name': nameAfterLabel(clean, ["elector's name", 'name']) ??
          firstNameLine(clean),
      'gender': detectGender(text),
      'dob': dateNear(clean, ['birth', 'dob']),
    };
  }
}
