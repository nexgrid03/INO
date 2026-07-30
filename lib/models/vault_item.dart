import 'package:flutter/material.dart';

/// The category a vault entry belongs to. The [name] (enum id) is what we
/// persist in the `category` column; label/icon/color are presentation-only.
enum VaultCategory {
  social('Social', Icons.public_rounded, Color(0xFF38BDF8)),
  finance('Finance', Icons.account_balance_rounded, Color(0xFF00A86B)),
  email('Email', Icons.alternate_email_rounded, Color(0xFF8B6CEF)),
  work('Work', Icons.work_rounded, Color(0xFFF5A524)),
  shopping('Shopping', Icons.shopping_bag_rounded, Color(0xFFEC6A8C)),
  other('Other', Icons.lock_rounded, Color(0xFF64748B));

  const VaultCategory(this.label, this.icon, this.color);

  final String label;
  final IconData icon;
  final Color color;

  /// Resolves a persisted id back to a category, defaulting to [other].
  static VaultCategory fromId(String? id) => VaultCategory.values.firstWhere(
        (c) => c.name == id,
        orElse: () => VaultCategory.other,
      );
}

/// One decrypted credential in the Password Vault.
///
/// The sensitive fields ([username], [password], [notes]) live in memory only
/// while the vault is unlocked; on disk (Supabase) they are stored as a single
/// AES-GCM ciphertext blob. [title], [url], [category] and [favorite] are
/// metadata kept in the clear so the list can render and search without the
/// master key.
@immutable
class VaultItem {
  const VaultItem({
    required this.id,
    required this.title,
    required this.username,
    required this.password,
    this.url,
    this.notes,
    required this.category,
    required this.favorite,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String username;
  final String password;
  final String? url;
  final String? notes;
  final VaultCategory category;
  final bool favorite;
  final DateTime updatedAt;

  VaultItem copyWith({
    String? id,
    String? title,
    String? username,
    String? password,
    String? url,
    String? notes,
    VaultCategory? category,
    bool? favorite,
    DateTime? updatedAt,
  }) {
    return VaultItem(
      id: id ?? this.id,
      title: title ?? this.title,
      username: username ?? this.username,
      password: password ?? this.password,
      url: url ?? this.url,
      notes: notes ?? this.notes,
      category: category ?? this.category,
      favorite: favorite ?? this.favorite,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Per-user vault cryptography parameters, stored in `public.vault_meta`.
///
/// None of these are secret: [salt] and [iterations] parameterise the PBKDF2
/// key derivation, and [verifier] is a ciphertext of a known constant used to
/// check the entered master password without ever storing it.
@immutable
class VaultMeta {
  const VaultMeta({
    required this.salt,
    required this.verifier,
    required this.iterations,
  });

  /// Base64 PBKDF2 salt.
  final String salt;

  /// Base64 AES-GCM ciphertext of [verifierPlaintext], encrypted with the
  /// master key. Decrypting it back to the constant proves the password.
  final String verifier;

  /// PBKDF2 iteration count used when the vault was created.
  final int iterations;

  /// The known plaintext sealed into [verifier].
  static const String verifierPlaintext = 'INO_VAULT_VERIFIER_V1';

  factory VaultMeta.fromMap(Map<String, dynamic> map) {
    return VaultMeta(
      salt: map['kdf_salt'] as String,
      verifier: map['verifier'] as String,
      iterations: (map['iterations'] as num?)?.toInt() ?? 150000,
    );
  }
}
