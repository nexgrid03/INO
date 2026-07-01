/// Shared, UI-only form validators for the authentication screens.
///
/// Kept in one place so Login, Signup and Forgot-Password validate identically
/// (a premium app never contradicts itself between screens). Pure functions —
/// no state, no side effects — so they're trivial to reason about and reuse.
class AuthValidators {
  AuthValidators._();

  static final RegExp _emailRegex =
      RegExp(r'^[\w.\-+]+@([\w\-]+\.)+[\w\-]{2,}$');
  // 10–15 digits, optional leading + and spaces/dashes (kept forgiving).
  static final RegExp _phoneRegex = RegExp(r'^\+?[0-9]{10,15}$');

  static bool looksLikeEmail(String value) => value.contains('@');

  static String? name(String? value) {
    final name = value?.trim() ?? '';
    if (name.isEmpty) return 'Please enter your full name';
    if (name.length < 2) return 'Name is too short';
    return null;
  }

  static String? email(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Please enter your email';
    if (!_emailRegex.hasMatch(email)) return 'Enter a valid email address';
    return null;
  }

  static String? phone(String? value) {
    final digits = (value ?? '').replaceAll(RegExp(r'[\s\-()]'), '');
    if (digits.isEmpty) return 'Please enter your mobile number';
    if (!_phoneRegex.hasMatch(digits)) return 'Enter a valid mobile number';
    return null;
  }

  /// Accepts either a valid email OR a valid phone number (the login /
  /// forgot-password identifier field).
  static String? emailOrPhone(String? value) {
    final input = value?.trim() ?? '';
    if (input.isEmpty) return 'Please enter your email or mobile number';
    if (looksLikeEmail(input)) return email(input);
    return phone(input);
  }

  static String? password(String? value) {
    final password = value ?? '';
    if (password.isEmpty) return 'Please enter a password';
    if (password.length < 6) return 'Password must be at least 6 characters';
    return null;
  }

  static String? confirmPassword(String? value, String original) {
    if ((value ?? '').isEmpty) return 'Please re-enter your password';
    if (value != original) return 'Passwords do not match';
    return null;
  }
}
