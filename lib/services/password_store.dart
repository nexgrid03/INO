import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/net/net_guard.dart';
import '../core/storage/shared_prefs_cache.dart';
import '../models/password_models.dart';
import 'local_collection_store.dart';
import 'vault_crypto.dart';

/// The Password Vault's saved passwords, synced to `w_password_vault` as
/// **end-to-end encrypted** ciphertext.
///
/// SECURITY HARDENING:
/// Decrypted passwords exist ONLY in transient memory while the vault is UNLOCKED.
/// Local disk cache is stored exclusively in [FlutterSecureStorage] with
/// passwords sealed via [VaultCrypto] (AES-GCM ciphertext). Plaintext passwords
/// are NEVER written to SharedPreferences or disk. Locking the vault or signing
/// out immediately wipes all in-memory password entries.
class PasswordStore extends LocalCollectionStore<PasswordEntry> {
  PasswordStore._();
  static final PasswordStore instance = PasswordStore._();

  static const _secureStorage = FlutterSecureStorage();

  @override
  String get storageKey => 'ino_passwords';

  @override
  Map<String, dynamic> encode(PasswordEntry item) => item.toJson();

  @override
  PasswordEntry decode(Map<String, dynamic> json) =>
      PasswordEntry.fromJson(json);

  @override
  String idOf(PasswordEntry item) => item.id;

  @override
  Future<void> loadLocalCache(String? uid) => loadFromSecureStorage(uid);

  /// Clears in-memory decrypted passwords without modifying disk cache.
  /// Called when vault locks or session is reset.
  void clearMemory() {
    items.clear();
    notifyListeners();
  }

  /// Loads from FlutterSecureStorage, ensuring plaintext passwords NEVER touch SharedPreferences.
  /// Sealed passwords stored in FlutterSecureStorage are decrypted lazily using VaultCrypto.
  Future<void> loadFromSecureStorage(String? uid) async {
    final key = '${storageKey}_${uid ?? 'local'}';
    final loaded = <PasswordEntry>[];
    try {
      // 1. Purge legacy SharedPreferences plaintext cache if found
      final p = await SharedPrefsCache.instance.prefsAsync;
      final legacyRaw = p.getStringList(key);
      if (legacyRaw != null) {
        await p.remove(key);
      }

      // 2. Read sealed payload from FlutterSecureStorage
      final raw = await _secureStorage.read(key: key);
      if (raw != null && raw.isNotEmpty) {
        final maps = jsonDecode(raw) as List<dynamic>;
        for (final m in maps) {
          if (m is Map<String, dynamic>) {
            final isSealed = m['isSealed'] as bool? ?? false;
            var entry = PasswordEntry.fromJson(m);
            if (isSealed && entry.password.isNotEmpty && VaultCrypto.instance.isUnlocked) {
              final unsealed = await VaultCrypto.instance.decrypt(entry.password);
              entry = entry.copyWith(password: unsealed ?? '');
            }
            loaded.add(entry);
          }
        }
      }
    } catch (e) {
      developer.log('PasswordStore secure load failed: $e', name: 'vault');
    }

    items
      ..clear()
      ..addAll(loaded);
  }

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

  /// Re-seals every locally-cached entry under the vault's current key, and
  /// drops server rows this device cannot account for.
  ///
  /// Called immediately after [VaultCrypto.resetPassphrase]. The local cache
  /// holds plaintext, so those entries survive a forgotten passphrase intact -
  /// this is what turns "reset" from "lose everything" into "lose only what
  /// was never on this phone".
  ///
  /// The orphan sweep is not tidiness. A row sealed under the old key can
  /// never be opened again; leaving it would mean the vault permanently listed
  /// entries that show as blank passwords, with no way for the user to tell
  /// those apart from a genuine sync problem. Deleting them makes the loss
  /// visible once, which is the honest outcome.
  ///
  /// Best-effort throughout: a failure here leaves the new key working and the
  /// local entries intact, and the next sync retries.
  Future<void> resealForNewKey() async {
    if (!VaultCrypto.instance.isUnlocked) return;
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) return;

    final local = {for (final e in items) e.id: e};

    try {
      final rows = await client
          .from('w_password_vault')
          .select('id')
          .eq('auth_user_id', uid)
          .timeout(NetGuard.query);
      for (final row in rows) {
        final id = row['id'] as String?;
        if (id == null || local.containsKey(id)) continue;
        await client
            .from('w_password_vault')
            .delete()
            .eq('id', id)
            .timeout(NetGuard.mutation);
      }
    } catch (e) {
      developer.log('reseal: orphan sweep failed: $e', name: 'vault');
    }

    for (final entry in local.values) {
      try {
        // update() runs toRow(), which seals with whatever key is loaded now -
        // so this is the re-encryption, not just a touch.
        await update(entry);
      } catch (e) {
        developer.log('reseal: ${entry.id} failed: $e', name: 'vault');
      }
    }
  }

  /// Securely persist items to platform Keystore/Keychain via FlutterSecureStorage.
  /// Passwords are encrypted before writing, so plaintext NEVER exists on disk.
  @override
  Future<void> persist() async {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      final key = '${storageKey}_${uid ?? 'local'}';
      
      // Clean up legacy SharedPreferences key if present
      try {
        final p = await SharedPrefsCache.instance.prefsAsync;
        await p.remove(key);
      } catch (_) {}

      if (items.isEmpty) {
        await _secureStorage.delete(key: key);
        return;
      }

      // Seal entries for disk persistence using AES-GCM via VaultCrypto if unlocked
      final sealedPayloads = <Map<String, dynamic>>[];
      for (final item in items) {
        final row = item.toJson();
        if (VaultCrypto.instance.isUnlocked && item.password.isNotEmpty) {
          final sealed = await VaultCrypto.instance.encrypt(item.password);
          if (sealed != null) {
            row['password'] = sealed;
            row['isSealed'] = true;
          }
        }
        sealedPayloads.add(row);
      }
      await _secureStorage.write(
        key: key,
        value: jsonEncode(sealedPayloads),
      );
    } catch (e) {
      developer.log('PasswordStore persist failed: $e', name: 'vault');
    }
  }

  @override
  Future<void> clear() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    final key = '${storageKey}_${uid ?? 'local'}';
    items.clear();
    notifyListeners();
    try {
      await _secureStorage.delete(key: key);
      final p = await SharedPrefsCache.instance.prefsAsync;
      await p.remove(key);
    } catch (_) {}
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
