import 'dart:developer' as developer;

import 'package:flutter/foundation.dart' show kDebugMode;

/// A small, reusable layer that normalizes a detected Date-of-Birth string into
/// a single canonical **DD/MM/YYYY** format, regardless of how OCR reported it.
///
/// It sits *after* the OCR engine and parsers (which are untouched) and *before*
/// the value is displayed or saved, so mixed formats never reach the review
/// screen or the database.
///
/// Handled inputs (with `/`, `-` or `.` separators, and any leading label such
/// as `DOB:` / `DO8:` / `D0B:`):
///   • `YYYY/MM/DD`  → `2006/12/17` → `17/12/2006`
///   • `YYYY-MM-DD`  → `2006-12-17` → `17/12/2006`
///   • `DD/MM/YYYY`  → `17/12/2006` → `17/12/2006`
///   • `DD-MM-YYYY`  → `17-12-2006` → `17/12/2006`
///   • `DD.MM.YYYY`  → `17.12.2006` → `17/12/2006`
///   • a bare year (Aadhaar "Year of Birth", e.g. `1975`) is preserved as-is.
///
/// If a value can't be confidently parsed it is returned unchanged (trimmed) so
/// nothing is ever lost or fabricated.
class DateNormalizer {
  DateNormalizer._();

  /// Matches a `d[sep]m[sep]y` date anywhere in the string. The first and last
  /// groups accept 1–4 digits so it works whether the year is first or last.
  static final RegExp _dateRe =
      RegExp(r'(\d{1,4})\s*[/\-.]\s*(\d{1,2})\s*[/\-.]\s*(\d{1,4})');

  /// A standalone 4-digit year (1900–2099), for the "Year of Birth" case.
  static final RegExp _yearOnlyRe = RegExp(r'(?<!\d)(?:19|20)\d{2}(?!\d)');

  /// Normalizes [raw] to `DD/MM/YYYY`. Returns null for null/empty input, and
  /// the original (trimmed) value when it can't be parsed. Logs the raw and
  /// normalized values in debug builds.
  static String? normalizeDob(String? raw) {
    if (raw == null) return null;
    final input = raw.trim();
    if (input.isEmpty) return null;

    final normalized = _normalize(input);
    if (kDebugMode) {
      developer.log(
        'Raw DOB: $input\nNormalized DOB: ${normalized ?? input}',
        name: 'dob',
      );
    }
    return normalized ?? input;
  }

  static String? _normalize(String input) {
    final m = _dateRe.firstMatch(input);
    if (m != null) {
      final g1 = m.group(1)!;
      final g3 = m.group(3)!;
      final a = int.parse(g1);
      final b = int.parse(m.group(2)!);
      final c = int.parse(g3);

      int day;
      int month;
      int year;
      if (g1.length == 4 || a > 31) {
        // Year first: YYYY / MM / DD
        year = a;
        month = b;
        day = c;
      } else if (g3.length == 4 || c > 31) {
        // Year last: DD / MM / YYYY
        day = a;
        month = b;
        year = c;
      } else {
        // Two-digit year → assume DD / MM / YY.
        day = a;
        month = b;
        year = _expandYear(c);
      }

      if (_isValid(day, month, year)) {
        return '${_pad2(day)}/${_pad2(month)}/$year';
      }
      // Don't fabricate a date we can't validate.
      return null;
    }

    // No full date — keep a bare "Year of Birth" if present.
    return _yearOnlyRe.firstMatch(input)?.group(0);
  }

  static int _expandYear(int y) {
    if (y >= 100) return y;
    // 00–30 → 2000s, 31–99 → 1900s (a reasonable DOB heuristic).
    return y <= 30 ? 2000 + y : 1900 + y;
  }

  static bool _isValid(int day, int month, int year) =>
      day >= 1 &&
      day <= 31 &&
      month >= 1 &&
      month <= 12 &&
      year >= 1900 &&
      year <= DateTime.now().year;

  static String _pad2(int v) => v.toString().padLeft(2, '0');
}
