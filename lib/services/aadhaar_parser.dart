import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kDebugMode;

import 'ocr_text_utils.dart';

/// Extracts and validates Aadhaar-card fields from raw OCR text — built for
/// accuracy on *real, noisy* OCR (spelling errors, merged separators, missing
/// word boundaries), not clean text.
///
/// Design:
///   • **Fuzzy rejection** — header lines ("Government of India", "Unique
///     Identification Authority of India", "UIDAI") are rejected even when OCR
///     garbles them ("Iniaue Ldentification Auttaaritv Of Lndia"), via a
///     Levenshtein-based similarity check.
///   • **Name = line above DOB** — the primary name is the nearest valid,
///     non-header line immediately above the DOB / DO8 / D0B line.
///   • **Fuzzy DOB label** — `DOB`, `DO8`, `D0B`, `D08` all count; the date is
///     reconstructed even when OCR merges separators ("17/1212006" → 17/12/2006).
///   • **Enrolment dates rejected** — dates on/next to "Enrolment/Enrollment"
///     lines are never used as DOB.
///   • **Fuzzy gender** — `Male`, `Mle`, `Malee`, and `Male` glued inside a
///     token ("DdzyaIMale") all resolve to Male; likewise Female.
class AadhaarParser {
  AadhaarParser._();

  // Exactly 12 digits in 4-4-4 groups — look-arounds reject a slice of a
  // 16-digit VID.
  static final RegExp _numberRe =
      RegExp(r'(?<!\d)(\d{4})\s?(\d{4})\s?(\d{4})(?!\s?\d)');
  // A DOB label token allowing common OCR confusions: O↔0, B↔8.
  static final RegExp _dobToken = RegExp(r'd[o0][b8]', caseSensitive: false);
  static final RegExp _strictDate =
      RegExp(r'(\d{1,2})\s*[/\-.]\s*(\d{1,2})\s*[/\-.]\s*(\d{4})');
  static final RegExp _yearRe = RegExp(r'\b(19|20)\d{2}\b');
  static final RegExp _letters = RegExp(r'[A-Za-z]+');

  // Distinctive header words: any fuzzy hit rejects the line as a name.
  static const List<String> _strongHeaders = [
    'government', 'unique', 'identification', 'authority', 'uidai', 'aadhaar',
    'aadhar', 'enrollment', 'enrolment', 'republic', 'signature', 'permanent',
    'department',
  ];
  // Weaker words: only reject when two or more appear together.
  static const List<String> _weakHeaders = ['india', 'bharat', 'sarkar'];

  /// Returns `{name, dob, gender, number}`; values are null when not found.
  static Map<String, String?> parse(String text, List<String> lines) {
    final clean = [
      for (final l in lines) l.trim(),
    ].where((l) => l.isNotEmpty).toList();

    final log = _Debug();
    final number = extractNumber(clean, text);
    final dob = _extractDob(clean, log);
    final gender = _extractGender(text, log);
    final name = _extractName(clean, log);

    log
      ..finalName = name
      ..finalDob = dob
      ..finalGender = gender
      ..number = number
      ..emit(text);

    return {'name': name, 'dob': dob, 'gender': gender, 'number': number};
  }

  // ---- Number --------------------------------------------------------------

  /// The cleaned 12-digit Aadhaar number, or null. Skips VID / mobile /
  /// enrolment lines, and never returns a 12-digit slice of a 16-digit VID.
  static String? extractNumber(List<String> lines, String fullText) {
    for (final line in lines) {
      final low = line.toLowerCase();
      if (low.contains('vid') ||
          low.contains('mobile') ||
          low.contains('phone') ||
          low.contains('enrol')) {
        continue;
      }
      final m = _numberRe.firstMatch(line);
      if (m != null) {
        final digits = '${m[1]}${m[2]}${m[3]}';
        if (isValid(digits)) return digits;
      }
    }
    final m = _numberRe.firstMatch(fullText);
    if (m != null) {
      final digits = '${m[1]}${m[2]}${m[3]}';
      if (isValid(digits)) return digits;
    }
    return null;
  }

  /// Validates the Aadhaar number format: exactly 12 digits (spaces stripped).
  static bool isValid(String number) {
    final digits = number.replaceAll(RegExp(r'\D'), '');
    return RegExp(r'^\d{12}$').hasMatch(digits);
  }

  // ---- DOB -----------------------------------------------------------------

  static String? _extractDob(List<String> lines, _Debug log) {
    // 1. A date on a line labelled DOB / DO8 / D0B / "Date of Birth" / "Birth".
    for (final line in lines) {
      if (_isEnrolmentLine(line)) {
        log.rejectedDates.add('$line (enrolment)');
        continue;
      }
      final labelled =
          _dobToken.hasMatch(line) || _fuzzyContains(line, 'birth');
      if (labelled) {
        final d = _dateFromLabelledLine(line);
        if (d != null) {
          log.candidateDobs.add('$d (labelled)');
          return d;
        }
      }
    }
    // 2. A labelled Year of Birth.
    for (final line in lines) {
      if (_isEnrolmentLine(line)) continue;
      final low = line.toLowerCase();
      if (_fuzzyContains(line, 'year of birth') || low.contains('yob')) {
        final y = _yearRe.firstMatch(line);
        if (y != null) {
          log.candidateDobs.add('${y[0]} (year of birth)');
          return y[0];
        }
      }
    }
    // 3. Any date (not on/after an enrolment line) — last resort.
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final nearEnrol =
          _isEnrolmentLine(line) || (i > 0 && _isEnrolmentLine(lines[i - 1]));
      if (nearEnrol) {
        log.rejectedDates.add('$line (near enrolment)');
        continue;
      }
      final m = _strictDate.firstMatch(line);
      if (m != null) {
        final d = _fmt(m[1]!, m[2]!, m[3]!);
        if (_validDate(d)) {
          log.candidateDobs.add('$d (unlabelled)');
          return d;
        }
      }
    }
    return null;
  }

  /// Extracts the date from a DOB-labelled line, tolerating merged/duplicated
  /// separators ("17/1212006" → 17/12/2006).
  static String? _dateFromLabelledLine(String line) {
    // Only look after the DOB token, so stray digits before it are ignored.
    var region = line;
    final t = _dobToken.firstMatch(line);
    if (t != null) region = line.substring(t.end);

    final strict = _strictDate.firstMatch(region);
    if (strict != null) {
      final d = _fmt(strict[1]!, strict[2]!, strict[3]!);
      if (_validDate(d)) return d;
    }
    // Digit reconstruction: DD, MM, then the trailing 4-digit year.
    final digits = region.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 8) {
      final d = _fmt(
        digits.substring(0, 2),
        digits.substring(2, 4),
        digits.substring(digits.length - 4),
      );
      if (_validDate(d)) return d;
    }
    return null;
  }

  static String _fmt(String d, String m, String y) =>
      '${d.padLeft(2, '0')}/${m.padLeft(2, '0')}/$y';

  static bool _validDate(String ddmmyyyy) {
    final m = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(ddmmyyyy);
    if (m == null) return false;
    final day = int.parse(m[1]!);
    final month = int.parse(m[2]!);
    final year = int.parse(m[3]!);
    if (day < 1 || day > 31 || month < 1 || month > 12) return false;
    return year >= 1900 && year <= DateTime.now().year;
  }

  static bool _isEnrolmentLine(String line) {
    final low = line.toLowerCase();
    if (low.contains('enrol')) return true;
    for (final w in _wordTokens(line)) {
      if (_closeEnough(w, 'enrollment') || _closeEnough(w, 'enrolment')) {
        return true;
      }
    }
    return false;
  }

  // ---- Gender --------------------------------------------------------------

  static String? _extractGender(String text, _Debug log) {
    final tokens = _letters.allMatches(text).map((m) => m[0]!.toLowerCase());
    for (final t in tokens) {
      if (t.contains('female') || _closeEnough(t, 'female')) {
        log.candidateGender.add('$t → Female');
        return 'Female';
      }
    }
    for (final t in _letters.allMatches(text).map((m) => m[0]!.toLowerCase())) {
      if (t.contains('male') || _closeEnough(t, 'male')) {
        log.candidateGender.add('$t → Male');
        return 'Male';
      }
    }
    return null;
  }

  // ---- Name ----------------------------------------------------------------

  static String? _extractName(List<String> lines, _Debug log) {
    // Anchor on the DOB / DO8 / D0B / birth / gender line.
    var anchor = -1;
    for (var i = 0; i < lines.length; i++) {
      if (_dobToken.hasMatch(lines[i]) ||
          _fuzzyContains(lines[i], 'birth') ||
          _isGenderLine(lines[i])) {
        anchor = i;
        break;
      }
    }

    // Nearest valid, non-header name directly above the anchor (primary rule).
    if (anchor > 0) {
      for (var i = anchor - 1; i >= 0; i--) {
        final r = _classifyName(lines[i], log);
        if (r == _NameVerdict.strong) return titleCase(lines[i]);
      }
      for (var i = anchor - 1; i >= 0; i--) {
        final r = _classifyName(lines[i], log);
        if (r == _NameVerdict.weak) return titleCase(lines[i]);
      }
    }

    // Fallback: first valid name anywhere (headers already rejected).
    for (final l in lines) {
      if (_classifyName(l, log) == _NameVerdict.strong) return titleCase(l);
    }
    for (final l in lines) {
      if (_classifyName(l, log) == _NameVerdict.weak) return titleCase(l);
    }
    return null;
  }

  static _NameVerdict _classifyName(String line, _Debug log) {
    if (!_validNameChars(line)) return _NameVerdict.reject;
    if (_isHeaderLine(line)) {
      log.rejectedNames.add(line);
      return _NameVerdict.reject;
    }
    final words = line.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    log.candidateNames.add(line);
    return words.length >= 2 ? _NameVerdict.strong : _NameVerdict.weak;
  }

  /// Letters, spaces, dots and apostrophes only; length 3–50; no digits.
  static bool _validNameChars(String s) {
    final t = s.trim();
    if (t.length < 3 || t.length > 50) return false;
    if (RegExp(r'[0-9]').hasMatch(t)) return false;
    return RegExp(r"^[A-Za-z][A-Za-z .']*[A-Za-z.]$").hasMatch(t);
  }

  /// True when a line is a card heading / gender line (fuzzy, OCR-tolerant).
  static bool _isHeaderLine(String line) {
    final words = _wordTokens(line);
    if (words.isEmpty) return true;
    var strong = 0;
    var weak = 0;
    var gender = 0;
    for (final w in words) {
      if (_fuzzyAny(w, _strongHeaders)) strong++;
      if (_fuzzyAny(w, _weakHeaders)) weak++;
      if (w.contains('male') ||
          w.contains('female') ||
          _closeEnough(w, 'male') ||
          _closeEnough(w, 'female')) {
        gender++;
      }
    }
    if (strong >= 1) return true;
    if (weak >= 2) return true;
    if (gender >= 1 && words.length <= 2) return true;
    return false;
  }

  static bool _isGenderLine(String line) {
    for (final w in _wordTokens(line)) {
      if (w.contains('male') ||
          w.contains('female') ||
          _closeEnough(w, 'male') ||
          _closeEnough(w, 'female')) {
        return true;
      }
    }
    return false;
  }

  // ---- Fuzzy helpers -------------------------------------------------------

  /// Alphabetic tokens (length ≥ 2), lower-cased.
  static List<String> _wordTokens(String line) => _letters
      .allMatches(line)
      .map((m) => m[0]!.toLowerCase())
      .where((w) => w.length >= 2)
      .toList();

  static bool _fuzzyAny(String word, List<String> keys) {
    for (final k in keys) {
      if (_closeEnough(word, k)) return true;
    }
    return false;
  }

  /// Does any token in [line] fuzzy-match [phrase]'s words (all of them)?
  static bool _fuzzyContains(String line, String phrase) {
    final low = line.toLowerCase();
    if (low.contains(phrase)) return true;
    final tokens = _wordTokens(line);
    final target = phrase.split(' ');
    return target.every((t) => tokens.any((w) => _closeEnough(w, t)));
  }

  /// Levenshtein-based similarity: closer-together strings for longer words.
  static bool _closeEnough(String a, String b) {
    if (a == b) return true;
    final maxLen = math.max(a.length, b.length);
    if (maxLen < 4) return a == b; // too short to fuzzy-match safely
    final allowed = maxLen <= 6 ? 1 : (maxLen <= 10 ? 2 : 3);
    return _levenshtein(a, b) <= allowed;
  }

  static int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    var prev = List<int>.generate(b.length + 1, (i) => i);
    var curr = List<int>.filled(b.length + 1, 0);
    for (var i = 0; i < a.length; i++) {
      curr[0] = i + 1;
      for (var j = 0; j < b.length; j++) {
        final cost = a[i] == b[j] ? 0 : 1;
        curr[j + 1] = math.min(
          math.min(curr[j] + 1, prev[j + 1] + 1),
          prev[j] + cost,
        );
      }
      final tmp = prev;
      prev = curr;
      curr = tmp;
    }
    return prev[b.length];
  }
}

enum _NameVerdict { strong, weak, reject }

/// Collects candidates / rejections during a parse for debug logging.
class _Debug {
  final List<String> candidateNames = [];
  final List<String> rejectedNames = [];
  final List<String> candidateDobs = [];
  final List<String> rejectedDates = [];
  final List<String> candidateGender = [];
  String? finalName;
  String? finalDob;
  String? finalGender;
  String? number;

  void emit(String rawText) {
    if (!kDebugMode) return;
    developer.log(
      '── AADHAAR PARSE ──\n'
      'Raw OCR Text:\n$rawText\n'
      '-------------------\n'
      'Candidate Names : $candidateNames\n'
      'Rejected Names  : $rejectedNames\n'
      'Candidate DOBs  : $candidateDobs\n'
      'Rejected Dates  : $rejectedDates\n'
      'Candidate Gender: $candidateGender\n'
      '-------------------\n'
      'FINAL → name=$finalName | dob=$finalDob | gender=$finalGender '
      '| aadhaar=$number\n'
      '───────────────────',
      name: 'aadhaar',
    );
  }
}
