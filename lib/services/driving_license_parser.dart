import 'ocr_text_utils.dart';

/// Extracts fields from an Indian Driving Licence's OCR text.
///
/// Layout cues: a DL number like `MH12 20110012345` (2 letters + 2 digits +
/// a long run of digits); a "Valid Till" date; a class-of-vehicle (COV) code
/// such as LMV / MCWG / HGMV.
class DrivingLicenseParser {
  DrivingLicenseParser._();

  static final RegExp _numberRe =
      RegExp(r'\b([A-Z]{2}[-\s]?\d{2}[-\s]?\d{4,11})\b');

  // Common class-of-vehicle codes (curated so 'MC' inside 'MCWG' isn't matched
  // separately). Matched as whole tokens.
  static const List<String> _cov = [
    'LMV', 'MCWG', 'MCWOG', 'MGV', 'HGMV', 'HMV', 'HPMV', 'HTV', 'TRANS', 'LTV',
  ];

  /// Returns `{number, name, dob, validity, vehicleClass}` (values may be null).
  static Map<String, String?> parse(String text, List<String> lines) {
    final clean = [
      for (final l in lines) l.trim().replaceAll(RegExp(r'\s+'), ' '),
    ].where((l) => l.isNotEmpty).toList();
    final upper = text.toUpperCase();

    return {
      'number': _numberRe.firstMatch(upper)?[1],
      'name': nameAfterLabel(clean, ['name', 'holder']) ?? firstNameLine(clean),
      'dob': dateNear(clean, ['birth', 'dob']),
      'validity': dateNear(clean, ['valid', 'validity', 'till', 'expiry']),
      'vehicleClass': _vehicleClass(upper),
    };
  }

  static String? _vehicleClass(String upper) {
    final found = <String>[];
    for (final code in _cov) {
      final re = RegExp('(?<![A-Z])$code(?![A-Z])');
      if (re.hasMatch(upper) && !found.contains(code)) found.add(code);
    }
    return found.isEmpty ? null : found.join(', ');
  }
}
