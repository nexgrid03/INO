import 'dart:math';

import '../models/password_models.dart';
import 'local_collection_store.dart';
import 'vault_crypto.dart';

/// The Password Vault's saved passwords, synced to `w_password_vault` as
/// **end-to-end encrypted** ciphertext.
///
/// SECURITY NOTE - read before extending this:
///
/// The password itself is sealed by [VaultCrypto] with a key derived on-device
/// from the user's vault passphrase, so the `password` column holds ciphertext
/// the server cannot read. The nickname is stored in the clear, protected only
/// by RLS - which is exactly why the UI insists it must be a decoy the user
/// invents, never the real site or app name. Do not add columns that would
/// carry a credential in the clear.
///
/// `consent` records the user's approval from the save dialog. The form never
/// calls [add]/[update] without it, so every uploaded row carries true.
///
/// Sync only happens while the vault is UNLOCKED, because sealing needs the
/// key. When it is locked, [syncTable] is null and this store behaves exactly
/// as it did before: local only, nothing uploaded. That is a deliberate
/// fail-closed: the alternative to "cannot encrypt" is never "upload
/// plaintext".
///
/// Locally, entries are still `shared_preferences`, which is app-private but
/// **not encrypted at rest**; a rooted device or a full device backup could
/// read it. Moving the local copy to the platform keystore remains the intended
/// hardening step and only [persist]/[decode] would change.
class PasswordStore extends LocalCollectionStore<PasswordEntry> {
  PasswordStore._();
  static final PasswordStore instance = PasswordStore._();

  @override
  String get storageKey => 'ino_passwords';

  @override
  Map<String, dynamic> encode(PasswordEntry item) => item.toJson();

  @override
  PasswordEntry decode(Map<String, dynamic> json) =>
      PasswordEntry.fromJson(json);

  @override
  String idOf(PasswordEntry item) => item.id;

  // ---- Supabase sync (end-to-end encrypted) --------------------------------

  /// Null while the vault is locked, which disables sync entirely.
  ///
  /// This is the fail-closed switch: with no key there is no way to seal a
  /// secret, and a password must never be uploaded unsealed. A locked vault
  /// therefore degrades to the old device-local behaviour rather than to a
  /// plaintext upload.
  @override
  String? get syncTable =>
      VaultCrypto.instance.isUnlocked ? 'w_password_vault' : null;

  @override
  PasswordEntry withId(PasswordEntry item, String id) =>
      item.copyWith(id: id);

  /// Maps an entry onto `w_password_vault`, sealing the password.
  ///
  /// Throws if the vault locked between the caller's check and here. That is
  /// intentional: [LocalCollectionStore] catches it, keeps the record local,
  /// and retries on the next sync - which is the correct outcome. Writing a
  /// null or plaintext `password` would not be.
  @override
  Future<Map<String, dynamic>> toRow(PasswordEntry e) async {
    final sealed = await VaultCrypto.instance.encrypt(e.password);
    if (sealed == null) {
      throw StateError('vault locked - refusing to upload an unsealed secret');
    }
    return {
      'nickname': e.nickname,
      'password': sealed,
      'consent': e.consent,
      'created_at': e.createdAt.toIso8601String(),
      'updated_at': e.updatedAt.toIso8601String(),
    };
  }

  /// Rebuilds an entry, decrypting the sealed password.
  ///
  /// A password that will not open (wrong key, tampered row) yields an empty
  /// string rather than throwing, so one bad row cannot make the whole vault
  /// unreadable. The entry is still listed - the user can see it exists and
  /// re-enter it.
  @override
  Future<PasswordEntry> fromRow(Map<String, dynamic> row) async {
    final sealed = row['password'] as String?;
    final plaintext =
        sealed == null ? '' : (await VaultCrypto.instance.decrypt(sealed) ?? '');
    return PasswordEntry(
      id: row['id'] as String,
      nickname: (row['nickname'] as String?) ?? '',
      password: plaintext,
      consent: (row['consent'] as bool?) ?? false,
      createdAt: DateTime.tryParse('${row['created_at']}') ?? DateTime.now(),
      updatedAt: DateTime.tryParse('${row['updated_at']}') ?? DateTime.now(),
    );
  }

  /// A–Z by nickname - the vault list reads best alphabetically.
  List<PasswordEntry> get sorted {
    final list = [...items]..sort((a, b) =>
        a.nickname.toLowerCase().compareTo(b.nickname.toLowerCase()));
    return List.unmodifiable(list);
  }
}

// ---------------------------------------------------------------------------
// Generator
// ---------------------------------------------------------------------------

/// Options for [generatePassword].
class PasswordRecipe {
  const PasswordRecipe({
    this.length = 16,
    this.lowercase = true,
    this.uppercase = true,
    this.digits = true,
    this.symbols = true,
  });

  final int length;
  final bool lowercase;
  final bool uppercase;
  final bool digits;
  final bool symbols;

  PasswordRecipe copyWith({
    int? length,
    bool? lowercase,
    bool? uppercase,
    bool? digits,
    bool? symbols,
  }) =>
      PasswordRecipe(
        length: length ?? this.length,
        lowercase: lowercase ?? this.lowercase,
        uppercase: uppercase ?? this.uppercase,
        digits: digits ?? this.digits,
        symbols: symbols ?? this.symbols,
      );

  /// At least one class must stay on - the UI enforces this too.
  bool get isValid => lowercase || uppercase || digits || symbols;
}

const _lower = 'abcdefghijkmnopqrstuvwxyz'; // no 'l'
const _upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ'; // no 'I', 'O'
const _digits = '23456789'; // no '0', '1'
const _symbols = '!@#\$%^&*()-_=+[]{};:,.?';

/// A cryptographically-seeded random password matching [recipe].
///
/// Uses `Random.secure()` (the platform CSPRNG), guarantees at least one
/// character from every enabled class, and omits look-alike characters
/// (0/O, 1/l/I) so a generated password can still be typed by hand.
String generatePassword([PasswordRecipe recipe = const PasswordRecipe()]) {
  final pools = <String>[
    if (recipe.lowercase) _lower,
    if (recipe.uppercase) _upper,
    if (recipe.digits) _digits,
    if (recipe.symbols) _symbols,
  ];
  if (pools.isEmpty) return '';

  final rng = Random.secure();
  final length = recipe.length.clamp(pools.length, 64);
  final chars = <String>[
    // One from each enabled class first, so the recipe is always honoured.
    for (final pool in pools) pool[rng.nextInt(pool.length)],
  ];
  final all = pools.join();
  while (chars.length < length) {
    chars.add(all[rng.nextInt(all.length)]);
  }
  chars.shuffle(rng); // the guaranteed characters must not sit in a fixed order
  return chars.join();
}
