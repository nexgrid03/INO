import 'package:flutter/widgets.dart';

import '../../l10n/app_localizations.dart';

/// Shared, UI-only form validators for the authentication screens.
///
/// Kept in one place so Login, Signup and Forgot-Password validate identically
/// (a premium app never contradicts itself between screens). Pure functions -
/// no state, no side effects - so they're trivial to reason about and reuse.
///
/// Bound to an [AppLocalizations] so the messages follow the active language.
/// Build one per `build()` with [AuthValidators.of] and pass the methods as
/// tear-offs:
///
/// ```dart
/// final validate = AuthValidators.of(context);
/// AuthTextField(validator: validate.email, ...);
/// ```
class AuthValidators {
  const AuthValidators(this._l10n);

  /// Reads the active localizations off [context] - call from `build()`.
  factory AuthValidators.of(BuildContext context) =>
      AuthValidators(AppLocalizations.of(context));

  final AppLocalizations _l10n;

  static final RegExp _emailRegex =
      RegExp(r'^[\w.\-+]+@([\w\-]+\.)+[\w\-]{2,}$');
  // 10–15 digits, optional leading + and spaces/dashes (kept forgiving).
  static final RegExp _phoneRegex = RegExp(r'^\+?[0-9]{10,15}$');

  /// Language-independent shape check - stays static (no message to localize).
  static bool looksLikeEmail(String value) => value.contains('@');

  String? name(String? value) {
    final name = value?.trim() ?? '';
    if (name.isEmpty) return _l10n.t('valEnterFullName');
    if (name.length < 2) return _l10n.t('valNameTooShort');
    return null;
  }

  String? email(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return _l10n.t('valEnterEmail');
    if (!_emailRegex.hasMatch(email)) return _l10n.t('valInvalidEmail');
    return null;
  }

  String? phone(String? value) {
    final digits = (value ?? '').replaceAll(RegExp(r'[\s\-()]'), '');
    if (digits.isEmpty) return _l10n.t('valEnterMobile');
    if (!_phoneRegex.hasMatch(digits)) return _l10n.t('valInvalidMobile');
    return null;
  }

  /// Accepts either a valid email OR a valid phone number (the login /
  /// forgot-password identifier field).
  String? emailOrPhone(String? value) {
    final input = value?.trim() ?? '';
    if (input.isEmpty) return _l10n.t('valEnterEmailOrMobile');
    if (looksLikeEmail(input)) return email(input);
    return phone(input);
  }

  String? password(String? value) {
    final password = value ?? '';
    if (password.isEmpty) return _l10n.t('valEnterPassword');
    if (password.length < 6) return _l10n.t('valPasswordTooShort');
    return null;
  }

  String? confirmPassword(String? value, String original) {
    if ((value ?? '').isEmpty) return _l10n.t('valReenterPassword');
    if (value != original) return _l10n.t('valPasswordMismatch');
    return null;
  }
}
