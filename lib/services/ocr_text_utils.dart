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

// A date with 1–2 digit day/month and a 2- or 4-digit year (tolerant of the
// spacing OCR leaves around the separators).
final RegExp _flexDateRe =
    RegExp(r'(\d{1,2})\s*[/\-.]\s*(\d{1,2})\s*[/\-.]\s*(\d{2,4})');

/// The first valid date on [s], normalised to `DD/MM/YYYY`, or null.
String? dateOnLine(String s) {
  final m = _flexDateRe.firstMatch(s);
  if (m == null) return null;
  final d = int.parse(m[1]!);
  final mo = int.parse(m[2]!);
  var y = int.parse(m[3]!);
  if (y < 100) y = y <= 30 ? 2000 + y : 1900 + y;
  if (d < 1 || d > 31 || mo < 1 || mo > 12) return null;
  if (y < 1900 || y > DateTime.now().year + 20) return null;
  return '${d.toString().padLeft(2, '0')}/${mo.toString().padLeft(2, '0')}/$y';
}

/// A date (`DD/MM/YYYY`) found on the first line containing any of [keywords]
/// (or on the immediately following line). Anchoring on the label avoids
/// confusing e.g. a passport's issue date with its date of birth.
String? dateNear(List<String> lines, List<String> keywords) {
  for (var i = 0; i < lines.length; i++) {
    final low = lines[i].toLowerCase();
    if (keywords.any(low.contains)) {
      final onLine = dateOnLine(lines[i]);
      if (onLine != null) return onLine;
      if (i + 1 < lines.length) {
        final next = dateOnLine(lines[i + 1]);
        if (next != null) return next;
      }
    }
  }
  return null;
}

/// The name value near a [labels] line: the text after the label on the SAME
/// line (tolerating ':' and "(s)" artifacts), else the following line, when it
/// looks like a person's name. Null when not found.
///
/// Labels are tried in order across ALL lines — so a specific label ("elector's
/// name") wins over a broad one ("name") that a heading might also contain.
String? nameAfterLabel(List<String> lines, List<String> labels) {
  for (final label in labels) {
    for (var i = 0; i < lines.length; i++) {
      final low = lines[i].toLowerCase();
      final idx = low.indexOf(label);
      if (idx == -1) continue;
      // 1) Value on the same line, after the label + any ':' / '(s)' junk.
      var after = lines[i].substring(idx + label.length);
      after =
          after.replaceFirst(RegExp(r'^[^A-Za-z]*(?:s\)[^A-Za-z]*)?'), '').trim();
      if (looksLikeName(after)) return titleCase(after);
      // 2) Value on the following line.
      if (i + 1 < lines.length && looksLikeName(lines[i + 1])) {
        return titleCase(lines[i + 1]);
      }
    }
  }
  return null;
}

/// The first plausible name line (headings are rejected by [looksLikeName]).
String? firstNameLine(List<String> lines) {
  for (final l in lines) {
    if (looksLikeName(l)) return titleCase(l);
  }
  return null;
}

/// Detects gender ('Male' / 'Female') from free text, or null. Checks female
/// first since "female" contains "male".
String? detectGender(String text) {
  final low = text.toLowerCase();
  if (RegExp(r'\bfe\s*male\b').hasMatch(low)) return 'Female';
  if (RegExp(r'\bmale\b').hasMatch(low)) return 'Male';
  return null;
}
