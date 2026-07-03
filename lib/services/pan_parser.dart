import 'ocr_text_utils.dart';

/// Extracts and validates the fields on a PAN card from its OCR text.
///
/// PAN layout: the labels "Name" and "Father's Name" precede their values;
/// the 10-character PAN follows the pattern `ABCDE1234F`.
class PanParser {
  PanParser._();

  static final RegExp _numberRe = RegExp(r'\b([A-Z]{5}[0-9]{4}[A-Z])\b');

  /// Returns `{name, dob, number, fatherName}` (values may be null).
  static Map<String, String?> parse(String text, List<String> lines) {
    final names = _extractNames(lines);
    return {
      'name': names.$1,
      'dob': extractDob(text),
      'number': extractNumber(text),
      'fatherName': names.$2,
    };
  }

  /// The 10-character PAN (uppercased), or null.
  static String? extractNumber(String text) {
    final m = _numberRe.firstMatch(text.toUpperCase());
    return m?[1];
  }

  /// Mandatory PAN format validation: 5 letters, 4 digits, 1 letter.
  static bool isValid(String pan) =>
      RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$').hasMatch(pan.trim().toUpperCase());

  /// Returns `(name, fatherName)` using label anchors first, then a fallback of
  /// the first two name-like lines.
  static (String?, String?) _extractNames(List<String> lines) {
    String? name;
    String? father;

    for (var i = 0; i < lines.length; i++) {
      final l = lines[i].toLowerCase().trim();
      final next = i + 1 < lines.length ? lines[i + 1] : '';

      final isFatherLabel = l.contains("father") || l.contains('पिता');
      final isNameLabel = !isFatherLabel &&
          (l == 'name' || l.startsWith('name ') || l == 'नाम');

      if (isFatherLabel && father == null && looksLikeName(next)) {
        father = titleCase(next);
      } else if (isNameLabel && name == null && looksLikeName(next)) {
        name = titleCase(next);
      }
    }

    // Fallback: first two distinct name-like lines (name, then father).
    if (name == null || father == null) {
      final candidates = <String>[];
      for (final l in lines) {
        if (looksLikeName(l)) {
          final t = titleCase(l);
          if (!candidates.contains(t)) candidates.add(t);
        }
      }
      name ??= candidates.isNotEmpty ? candidates[0] : null;
      father ??= candidates.length > 1 ? candidates[1] : null;
    }
    return (name, father);
  }
}
