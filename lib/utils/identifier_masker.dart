/// Utility for masking sensitive government & document identifiers (Aadhaar, PAN,
/// Passport, Driving License, Voter ID, Policy Numbers, etc.) across the app UI.
class IdentifierMasker {
  IdentifierMasker._();

  static final RegExp _nonDigits = RegExp(r'\D');

  /// Returns a masked display string for [raw] identifier based on [docType] or pattern.
  ///
  /// Examples:
  /// - Aadhaar (12 digits): "XXXX XXXX 1234"
  /// - PAN (10 chars, ABCDE1234F): "ABCDE****F"
  /// - Passport (8-9 chars, P1234567): "P*****67" / "P******89"
  /// - Driving License / Voter ID / General: show only last 4 characters ("******1234")
  static String mask(String? raw, {String? docType}) {
    if (raw == null) return '';
    final cleaned = raw.trim();
    if (cleaned.isEmpty) return '';

    // If already encrypted token representation, return sanitized mask
    if (cleaned.startsWith('enc:')) {
      return '••••••••';
    }

    final type = (docType ?? '').toLowerCase();
    final digitsOnly = cleaned.replaceAll(_nonDigits, '');

    // 1. Aadhaar Number (12 digits) -> XXXX XXXX 1234
    if (type.contains('aadhaar') || type.contains('aadhar') || digitsOnly.length == 12) {
      if (digitsOnly.length >= 12) {
        final last4 = digitsOnly.substring(digitsOnly.length - 4);
        return 'XXXX XXXX $last4';
      }
    }

    // 2. PAN Card (10 characters: 5 letters + 4 digits + 1 letter, e.g. ABCDE1234F) -> ABCDE****F
    if (type.contains('pan') ||
        (cleaned.length == 10 && RegExp(r'^[A-Za-z]{5}[0-9]{4}[A-Za-z]$').hasMatch(cleaned))) {
      final upper = cleaned.toUpperCase();
      return '${upper.substring(0, 5)}****${upper.substring(9)}';
    }

    // 3. Passport (8-9 characters starting with letter, e.g. P1234567 or Z12345678) -> P*****67
    if (type.contains('passport') ||
        (cleaned.length >= 8 && cleaned.length <= 9 && RegExp(r'^[A-Za-z]').hasMatch(cleaned))) {
      final upper = cleaned.toUpperCase();
      if (upper.length >= 8) {
        final prefix = upper[0];
        final suffix = upper.substring(upper.length - 2);
        final maskLen = upper.length - 3;
        return '$prefix${'*' * maskLen}$suffix';
      }
    }

    // 4. Driving License / Voter ID / General -> mask all except last 4 chars
    if (cleaned.length > 4) {
      final maskLen = cleaned.length - 4;
      return '${'*' * maskLen}${cleaned.substring(cleaned.length - 4)}';
    }

    return cleaned;
  }

  /// Extracts the last 4 characters for fast identification.
  static String last4(String? raw) {
    if (raw == null) return '';
    final cleaned = raw.trim();
    if (cleaned.length <= 4) return cleaned;
    return cleaned.substring(cleaned.length - 4);
  }

  /// Whether [raw] is already a masked representation (e.g. contains 'X', '*', or '•').
  static bool isMasked(String? raw) {
    if (raw == null) return false;
    final cleaned = raw.trim();
    if (cleaned.isEmpty) return false;
    return cleaned.contains('X') ||
        cleaned.contains('x') ||
        cleaned.contains('*') ||
        cleaned.contains('•') ||
        cleaned.startsWith('enc:');
  }
}
