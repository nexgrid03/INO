import 'ocr_text_utils.dart';

/// Extracts fields from an Indian passport's OCR text.
///
/// Layout cues: a passport number of one letter + 7 digits (e.g. `A1234567`);
/// separate "Date of Birth" and "Date of Expiry" labels; a "Nationality" line
/// that is almost always INDIAN.
class PassportParser {
  PassportParser._();

  static final RegExp _numberRe = RegExp(r'\b([A-Z][0-9]{7})\b');

  /// Returns `{number, name, dob, expiryDate, nationality}` (values may be null).
  static Map<String, String?> parse(String text, List<String> lines) {
    final clean = [
      for (final l in lines) l.trim().replaceAll(RegExp(r'\s+'), ' '),
    ].where((l) => l.isNotEmpty).toList();

    return {
      'number': _numberRe.firstMatch(text.toUpperCase())?[1],
      'name': _name(clean),
      // Anchor DOB on its own label so the issue/expiry dates aren't picked.
      'dob': dateNear(clean, ['birth', 'dob']),
      'expiryDate': dateNear(clean, ['expiry', 'expire']),
      'nationality': _nationality(text, clean),
    };
  }

  /// Prefers "Given Name" + "Surname" combined; falls back to either alone or
  /// the first plausible name line.
  static String? _name(List<String> lines) {
    final given = nameAfterLabel(lines, ['given name', 'given']);
    final surname = nameAfterLabel(lines, ['surname']);
    if (given != null && surname != null) return '$given $surname';
    return given ?? surname ?? firstNameLine(lines);
  }

  static String? _nationality(String text, List<String> lines) {
    for (final l in lines) {
      final low = l.toLowerCase();
      if (low.contains('nationality')) {
        final after = l.contains(':') ? l.split(':').last : l;
        final m = RegExp(r'[A-Za-z]{4,}').allMatches(after).toList();
        for (final tok in m) {
          final w = tok[0]!;
          if (w.toLowerCase() != 'nationality') return titleCase(w);
        }
      }
    }
    if (text.toLowerCase().contains('indian')) return 'Indian';
    return null;
  }
}
