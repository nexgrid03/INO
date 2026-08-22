import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

/// Models backing the simplified Password Vault.
///
/// One entry is deliberately just two facts: a [PasswordEntry.nickname] the
/// user invents - the UI insists it must NOT be the real site or app name -
/// and the password itself. The password is sealed on-device by `VaultCrypto`
/// before it is ever uploaded, and [PasswordEntry.consent] records that the
/// user approved saving it in the consent dialog.

/// How strong a password is. Derived, never stored.
enum PasswordStrength { weak, fair, good, strong }

extension PasswordStrengthX on PasswordStrength {
  String get label => switch (this) {
        PasswordStrength.weak => 'Weak',
        PasswordStrength.fair => 'Fair',
        PasswordStrength.good => 'Good',
        PasswordStrength.strong => 'Strong',
      };

  /// [label] in the active language.
  String localizedLabel(AppLocalizations l10n) => switch (this) {
        PasswordStrength.weak => l10n.t('strengthWeak'),
        PasswordStrength.fair => l10n.t('strengthFair'),
        PasswordStrength.good => l10n.t('strengthGood'),
        PasswordStrength.strong => l10n.t('strengthStrong'),
      };

  Color get color => switch (this) {
        PasswordStrength.weak => AppColors.critical,
        PasswordStrength.fair => AppColors.warning,
        PasswordStrength.good => const Color(0xFF4383EA),
        PasswordStrength.strong => AppColors.success,
      };

  /// 0..1, for the strength meter.
  double get fraction => switch (this) {
        PasswordStrength.weak => 0.25,
        PasswordStrength.fair => 0.5,
        PasswordStrength.good => 0.75,
        PasswordStrength.strong => 1.0,
      };
}

/// Scores a password on length and character variety.
///
/// Deliberately simple and transparent (no dictionary check): length carries
/// the most weight, then the four character classes. A short password can never
/// score above [PasswordStrength.fair] no matter how varied it is.
PasswordStrength passwordStrength(String password) {
  if (password.isEmpty) return PasswordStrength.weak;
  final classes = [
    RegExp(r'[a-z]'),
    RegExp(r'[A-Z]'),
    RegExp(r'\d'),
    RegExp(r'[^A-Za-z0-9]'),
  ].where((r) => r.hasMatch(password)).length;

  var score = 0;
  if (password.length >= 8) score++;
  if (password.length >= 12) score++;
  if (password.length >= 16) score++;
  score += classes - 1; // 0..3

  if (password.length < 8) return PasswordStrength.weak;
  if (password.length < 12 && score < 4) return PasswordStrength.fair;
  if (score >= 6) return PasswordStrength.strong;
  if (score >= 4) return PasswordStrength.good;
  return PasswordStrength.fair;
}

/// One saved password in the vault.
class PasswordEntry {
  const PasswordEntry({
    required this.id,
    required this.nickname,
    required this.password,
    required this.createdAt,
    required this.updatedAt,
    this.consent = false,
  });

  final String id;

  /// The decoy label the user invents, e.g. "blue parrot" - never the real
  /// site or app name. It is the only thing the vault list shows.
  final String nickname;
  final String password;

  /// True once the user approved the save-consent dialog. An entry never
  /// reaches the server without it - the form refuses to save on decline.
  final bool consent;
  final DateTime createdAt;
  final DateTime updatedAt;

  PasswordStrength get strength => passwordStrength(password);

  /// The first letter, for the fallback monogram tile.
  String get monogram =>
      nickname.trim().isEmpty ? '?' : nickname.trim()[0].toUpperCase();

  /// Search matches the nickname only - a password must never be findable by
  /// typing part of its secret.
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return nickname.toLowerCase().contains(q);
  }

  PasswordEntry copyWith({
    /// Only set when adopting the database's uuid after the record is first
    /// uploaded (see LocalCollectionStore.withId). Never change an id otherwise.
    String? id,
    String? nickname,
    String? password,
    bool? consent,
    DateTime? updatedAt,
  }) {
    return PasswordEntry(
      id: id ?? this.id,
      nickname: nickname ?? this.nickname,
      password: password ?? this.password,
      consent: consent ?? this.consent,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'nickname': nickname,
        'password': password,
        'consent': consent,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory PasswordEntry.fromJson(Map<String, dynamic> j) => PasswordEntry(
        id: j['id']?.toString() ?? '',
        // 'title' is the key the pre-simplification vault wrote; falling back
        // keeps entries cached on-device by older builds readable.
        nickname: (j['nickname'] as String?) ?? (j['title'] as String?) ?? '',
        password: (j['password'] as String?) ?? '',
        consent: (j['consent'] as bool?) ?? false,
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ??
            DateTime.now(),
        updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? '') ??
            DateTime.now(),
      );
}
