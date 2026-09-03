import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Qualitative password strength buckets, with a label and colour for the UI.
enum PasswordStrength {
  empty('', 0, Color(0xFF94A3B8)),
  weak('Weak', 1, AppColors.critical),
  fair('Fair', 2, AppColors.warning),
  good('Good', 3, AppColors.skyBrandSecondary),
  strong('Strong', 4, AppColors.skyBrand);

  const PasswordStrength(this.label, this.score, this.color);

  final String label;

  /// 0–4, doubling as the number of filled segments in the strength bar.
  final int score;
  final Color color;
}

/// Password helpers used by the vault's create/edit screens. Kept as pure,
/// side-effect-free functions so they're trivially unit-testable.
class PasswordUtils {
  PasswordUtils._();

  static const String _lower = 'abcdefghijkmnopqrstuvwxyz';
  static const String _upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
  static const String _digits = '23456789';
  static const String _symbols = '!@#\$%^&*()-_=+[]{}';

  /// Estimates strength from length and character-class diversity.
  static PasswordStrength strength(String password) {
    if (password.isEmpty) return PasswordStrength.empty;

    var classes = 0;
    if (RegExp(r'[a-z]').hasMatch(password)) classes++;
    if (RegExp(r'[A-Z]').hasMatch(password)) classes++;
    if (RegExp(r'\d').hasMatch(password)) classes++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(password)) classes++;

    final len = password.length;
    var points = 0;
    if (len >= 8) points++;
    if (len >= 12) points++;
    if (len >= 16) points++;
    points += classes - 1; // reward diversity

    if (len < 6) return PasswordStrength.weak;
    if (points <= 1) return PasswordStrength.weak;
    if (points == 2) return PasswordStrength.fair;
    if (points <= 4) return PasswordStrength.good;
    return PasswordStrength.strong;
  }

  /// Generates a cryptographically-random password of [length] drawn from the
  /// selected character classes, guaranteeing at least one of each enabled set.
  static String generate({
    int length = 18,
    bool upper = true,
    bool lower = true,
    bool digits = true,
    bool symbols = true,
  }) {
    final rng = Random.secure();
    final pools = <String>[
      if (lower) _lower,
      if (upper) _upper,
      if (digits) _digits,
      if (symbols) _symbols,
    ];
    if (pools.isEmpty) pools.add(_lower);
    final all = pools.join();

    // One from each enabled pool, then fill the rest from the combined set.
    final chars = <String>[
      for (final pool in pools) pool[rng.nextInt(pool.length)],
    ];
    while (chars.length < length) {
      chars.add(all[rng.nextInt(all.length)]);
    }
    chars.shuffle(rng);
    return chars.join();
  }
}
