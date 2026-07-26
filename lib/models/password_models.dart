import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Models backing the Password Vault.
///
/// Entries live on-device only (see `PasswordStore`) and the vault is gated
/// behind the app's biometric [VaultGuard]. Passwords are masked everywhere by
/// default and only revealed on an explicit, per-entry tap.

enum PasswordCategory {
  social,
  banking,
  shopping,
  work,
  entertainment,
  utilities,
  email,
  other,
}

extension PasswordCategoryX on PasswordCategory {
  String get label => switch (this) {
        PasswordCategory.social => 'Social',
        PasswordCategory.banking => 'Banking',
        PasswordCategory.shopping => 'Shopping',
        PasswordCategory.work => 'Work',
        PasswordCategory.entertainment => 'Entertainment',
        PasswordCategory.utilities => 'Utilities',
        PasswordCategory.email => 'Email',
        PasswordCategory.other => 'Other',
      };

  IconData get icon => switch (this) {
        PasswordCategory.social => Icons.people_alt_rounded,
        PasswordCategory.banking => Icons.account_balance_rounded,
        PasswordCategory.shopping => Icons.shopping_bag_rounded,
        PasswordCategory.work => Icons.work_rounded,
        PasswordCategory.entertainment => Icons.movie_rounded,
        PasswordCategory.utilities => Icons.bolt_rounded,
        PasswordCategory.email => Icons.alternate_email_rounded,
        PasswordCategory.other => Icons.lock_rounded,
      };

  Color get color => switch (this) {
        PasswordCategory.social => const Color(0xFF4383EA),
        PasswordCategory.banking => AppColors.primaryGreen,
        PasswordCategory.shopping => const Color(0xFFF5704A),
        PasswordCategory.work => const Color(0xFF64748B),
        PasswordCategory.entertainment => const Color(0xFF9B6DE0),
        PasswordCategory.utilities => AppColors.warning,
        PasswordCategory.email => const Color(0xFF0891B2),
        PasswordCategory.other => const Color(0xFF94A3B8),
      };

  static PasswordCategory fromName(String? name) =>
      PasswordCategory.values.firstWhere(
        (c) => c.name == name,
        orElse: () => PasswordCategory.other,
      );
}

/// How strong a password is. Derived, never stored.
enum PasswordStrength { weak, fair, good, strong }

extension PasswordStrengthX on PasswordStrength {
  String get label => switch (this) {
        PasswordStrength.weak => 'Weak',
        PasswordStrength.fair => 'Fair',
        PasswordStrength.good => 'Good',
        PasswordStrength.strong => 'Strong',
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

/// One credential in the vault.
class PasswordEntry {
  const PasswordEntry({
    required this.id,
    required this.title,
    required this.password,
    required this.category,
    required this.createdAt,
    required this.updatedAt,
    this.url,
    this.username,
    this.email,
    this.notes,
    this.tags = const [],
    this.iconKey,
    this.isFavorite = false,
  });

  final String id;

  /// The site or app this belongs to, e.g. "Google".
  final String title;
  final String password;
  final PasswordCategory category;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? url;
  final String? username;
  final String? email;
  final String? notes;
  final List<String> tags;

  /// Optional icon override from the shared icon catalogue; falls back to the
  /// category glyph.
  final String? iconKey;
  final bool isFavorite;

  PasswordStrength get strength => passwordStrength(password);

  /// The account line shown under the title: username, else email.
  String get accountLine {
    final u = username?.trim();
    if (u != null && u.isNotEmpty) return u;
    return email?.trim() ?? '';
  }

  /// The first letter, for the fallback monogram tile.
  String get monogram =>
      title.trim().isEmpty ? '?' : title.trim()[0].toUpperCase();

  /// Search across everything except the password itself - a credential must
  /// never be findable by typing part of its secret.
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return title.toLowerCase().contains(q) ||
        (username ?? '').toLowerCase().contains(q) ||
        (email ?? '').toLowerCase().contains(q) ||
        (url ?? '').toLowerCase().contains(q) ||
        category.label.toLowerCase().contains(q) ||
        tags.any((t) => t.toLowerCase().contains(q));
  }

  PasswordEntry copyWith({
    String? title,
    String? password,
    PasswordCategory? category,
    DateTime? updatedAt,
    String? url,
    String? username,
    String? email,
    String? notes,
    List<String>? tags,
    String? iconKey,
    bool? isFavorite,
  }) {
    return PasswordEntry(
      id: id,
      title: title ?? this.title,
      password: password ?? this.password,
      category: category ?? this.category,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      url: url ?? this.url,
      username: username ?? this.username,
      email: email ?? this.email,
      notes: notes ?? this.notes,
      tags: tags ?? this.tags,
      iconKey: iconKey ?? this.iconKey,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'password': password,
        'category': category.name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'url': url,
        'username': username,
        'email': email,
        'notes': notes,
        'tags': tags,
        'iconKey': iconKey,
        'isFavorite': isFavorite,
      };

  factory PasswordEntry.fromJson(Map<String, dynamic> j) => PasswordEntry(
        id: j['id']?.toString() ?? '',
        title: (j['title'] as String?) ?? '',
        password: (j['password'] as String?) ?? '',
        category: PasswordCategoryX.fromName(j['category'] as String?),
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ??
            DateTime.now(),
        updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? '') ??
            DateTime.now(),
        url: j['url'] as String?,
        username: j['username'] as String?,
        email: j['email'] as String?,
        notes: j['notes'] as String?,
        tags: (j['tags'] as List?)?.map((t) => t.toString()).toList() ??
            const [],
        iconKey: j['iconKey'] as String?,
        isFavorite: (j['isFavorite'] as bool?) ?? false,
      );
}
