// Shared, pure text helpers used by the document parsers. Kept dependency-free
// so they're trivial to unit-test.

final RegExp _dateRe =
    RegExp(r'(\d{2})\s*[/\-.]\s*(\d{2})\s*[/\-.]\s*(\d{4})');
final RegExp _yobRe =
    RegExp(r'(?:year of birth|yob)\s*[:\-]?\s*(\d{4})', caseSensitive: false);

/// Words that never form part of a person's name (headings, labels, …).
const Set<String> _stopWords = {
  'government', 'india', 'govt', 'republic', 'income', 'tax', 'department',
  'permanent', 'account', 'number', 'aadhaar', 'aadhar', 'uidai', 'unique',
  'identification', 'authority', 'male', 'female', 'transgender', 'dob', 'date',
  'birth', 'year', 'father', 'name', 'signature', 'address', 'vid', 'help',
  'www', 'gov', 'mobile', 'issue', 'issued', 'valid', 'till', 'licence',
  'license', 'driving', 'passport', 'election', 'commission', 'elector', 'card',
  'enrolment', 'no', 'of', 'to', 'the', 'and',
};

/// Extracts a date of birth as `DD-MM-YYYY`, or a bare year when only a
/// year-of-birth is present. Returns null when nothing date-like is found.
String? extractDob(String text) {
  final m = _dateRe.firstMatch(text);
  if (m != null) return '${m[1]}-${m[2]}-${m[3]}';
  final y = _yobRe.firstMatch(text);
  if (y != null) return y[1];
  return null;
}

/// Parses a `DD-MM-YYYY` (or `DD/MM/YYYY`) string into a [DateTime], or null.
DateTime? parseDob(String? dob) {
  if (dob == null) return null;
  final m = _dateRe.firstMatch(dob);
  if (m == null) return null;
  final day = int.tryParse(m[1]!);
  final month = int.tryParse(m[2]!);
  final year = int.tryParse(m[3]!);
  if (day == null || month == null || year == null) return null;
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  return DateTime(year, month, day);
}

/// Heuristic: does [raw] look like a human name line (letters/spaces, no digits,
/// not purely made of heading/label stop-words)?
bool looksLikeName(String raw) {
  final line = raw.trim();
  if (line.length < 3 || line.length > 40) return false;
  if (RegExp(r'[0-9]').hasMatch(line)) return false;
  if (!RegExp(r'^[A-Za-z][A-Za-z .]+$').hasMatch(line)) return false;
  final words = line.toLowerCase().split(RegExp(r'\s+'));
  final meaningful = words.where((w) => !_stopWords.contains(w));
  return meaningful.isNotEmpty;
}

/// Title-cases a name line: "RAHUL KUMAR" → "Rahul Kumar".
String titleCase(String raw) {
  return raw
      .trim()
      .split(RegExp(r'\s+'))
      .map((w) => w.isEmpty
          ? w
          : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
      .join(' ');
}
