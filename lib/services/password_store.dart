import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math';

import 'package:flutter/foundation.dart';
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

  bool _hydratedWhileLocked = false;

  /// True if the store was hydrated while the vault was locked.
  /// When true, in-memory items may hold unverified ciphertext loaded from disk.
  bool get hydratedWhileLocked => _hydratedWhileLocked;

  /// True if all loaded entries are verified decrypted plaintext.
  bool get allEntriesDecrypted =>
      isLoaded &&
      items.isNotEmpty &&
      items.every((e) => e.isDecrypted);

  /// True if any entry in the store contains sealed ciphertext.
  bool get hasSealedEntries => items.any((e) => e.isSealed);

  /// Safe precondition check for reseal or passphrase reset.
  /// Reseal MUST refuse to execute unless:
  /// 1. Vault is unlocked
  /// 2. Store was not hydrated while locked without subsequent verified unlock/decrypt
  /// 3. Items list is non-empty
  /// 4. Every single item is verified decrypted plaintext
  bool get canReseal =>
      VaultCrypto.instance.isUnlocked &&
      !_hydratedWhileLocked &&
      items.isNotEmpty &&
      items.every((e) => e.isDecrypted);

  @override
  @visibleForTesting
  void reset() {
    items.clear();
    _hydratedWhileLocked = false;
    markUnloaded();
    notifyListeners();
  }

  /// Clears in-memory decrypted passwords without modifying disk cache.
  /// Called when vault locks or session is reset.
  void clearMemory() {
    items.clear();
    _hydratedWhileLocked = false;
    markUnloaded();
    notifyListeners();
  }

  /// Loads from FlutterSecureStorage, ensuring plaintext passwords NEVER touch SharedPreferences.
  /// Sealed passwords stored in FlutterSecureStorage are decrypted lazily using VaultCrypto.
  Future<void> loadFromSecureStorage(String? uid) async {
    final key = '${storageKey}_${uid ?? 'local'}';
    final loaded = <PasswordEntry>[];
    _hydratedWhileLocked = !VaultCrypto.instance.isUnlocked;
    try {
      // 1. Read secure storage first
      String? raw = await _secureStorage.read(key: key);

      // 2. If empty: read legacy storage
      final p = await SharedPrefsCache.instance.prefsAsync;
      final legacyRaw = p.getStringList(key);

      if ((raw == null || raw.isEmpty) && legacyRaw != null && legacyRaw.isNotEmpty) {
        // 3. Import entries
        final importedEntries = <PasswordEntry>[];
        for (final itemStr in legacyRaw) {
          try {
            final m = jsonDecode(itemStr);
            if (m is Map<String, dynamic>) {
              importedEntries.add(PasswordEntry.fromJson(m));
            }
          } catch (_) {}
        }

        if (importedEntries.isNotEmpty) {
          // Prepare secure storage payload
          final payloads = <Map<String, dynamic>>[];
          for (final entry in importedEntries) {
            final row = entry.toJson();
            if (VaultCrypto.instance.isUnlocked && entry.password.isNotEmpty) {
              final sealed = await VaultCrypto.instance.encrypt(entry.password);
              if (sealed != null) {
                row['password'] = sealed;
                row['isSealed'] = true;
                row['encryptionState'] = 'sealed';
              }
            }
            payloads.add(row);
          }

          final encodedPayload = jsonEncode(payloads);
          await _secureStorage.write(key: key, value: encodedPayload);

          // 4. Verify counts & 5. Re-read secure storage & 6. Validate import
          final verifyRaw = await _secureStorage.read(key: key);
          var validated = false;
          if (verifyRaw != null && verifyRaw.isNotEmpty) {
            try {
              final verifyMaps = jsonDecode(verifyRaw) as List<dynamic>;
              if (verifyMaps.length == importedEntries.length) {
                validated = true;
              }
            } catch (_) {}
          }

          // 7. Only then delete legacy cache
          if (validated) {
            await p.remove(key);
            raw = verifyRaw;
          } else {
            developer.log(
              'PasswordStore legacy migration validation failed. Keeping legacy cache.',
              name: 'vault',
            );
          }
        }
      }

      // Read sealed payload from FlutterSecureStorage
      if (raw != null && raw.isNotEmpty) {
        final maps = jsonDecode(raw) as List<dynamic>;
        for (final m in maps) {
          if (m is Map<String, dynamic>) {
            final isSealed = (m['isSealed'] as bool?) ??
                (m['encryptionState'] == 'sealed');
            var entry = PasswordEntry.fromJson(m);
            if (isSealed && entry.password.isNotEmpty) {
              if (VaultCrypto.instance.isUnlocked) {
                final unsealed = await VaultCrypto.instance.decrypt(entry.password);
                if (unsealed != null) {
                  entry = entry.copyWith(
                    password: unsealed,
                    encryptionState: PasswordEncryptionState.unsealed,
                  );
                } else {
                  // Decryption failed under current key: remains sealed!
                  entry = entry.copyWith(
                    encryptionState: PasswordEncryptionState.sealed,
                  );
                }
              } else {
                // Vault is locked: cannot decrypt, MUST remain marked sealed!
                entry = entry.copyWith(
                  encryptionState: PasswordEncryptionState.sealed,
                );
              }
            }
            loaded.add(entry);
          }
        }
      }
    } catch (e) {
      developer.log('PasswordStore secure load failed: $e', name: 'vault');
      setLoadedState(loaded: false, loading: false, uid: uid);
      return;
    }

    items
      ..clear()
      ..addAll(loaded);
    setLoadedState(loaded: true, loading: false, uid: uid);
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
  /// Throws if the entry is already sealed ciphertext (preventing double-encryption)
  /// or if the vault locked between the caller's check and here.
  @override
  Future<Map<String, dynamic>> toRow(PasswordEntry e) async {
    if (e.isSealed || !e.isDecrypted) {
      throw StateError(
        'Refusing to upload or re-encrypt an already-sealed ciphertext entry: ${e.id}',
      );
    }
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
  /// A password that will not open (wrong key, tampered row) yields an entry marked
  /// [PasswordEncryptionState.sealed] rather than throwing, so one bad row cannot
  /// make the whole vault unreadable.
  @override
  Future<PasswordEntry> fromRow(Map<String, dynamic> row) async {
    final sealed = row['password'] as String?;
    if (sealed == null || sealed.isEmpty) {
      return PasswordEntry(
        id: row['id'] as String,
        nickname: (row['nickname'] as String?) ?? '',
        password: '',
        consent: (row['consent'] as bool?) ?? false,
        createdAt: DateTime.tryParse('${row['created_at']}') ?? DateTime.now(),
        updatedAt: DateTime.tryParse('${row['updated_at']}') ?? DateTime.now(),
        encryptionState: PasswordEncryptionState.unsealed,
      );
    }
    final plaintext = await VaultCrypto.instance.decrypt(sealed);
    if (plaintext != null) {
      return PasswordEntry(
        id: row['id'] as String,
        nickname: (row['nickname'] as String?) ?? '',
        password: plaintext,
        consent: (row['consent'] as bool?) ?? false,
        createdAt: DateTime.tryParse('${row['created_at']}') ?? DateTime.now(),
        updatedAt: DateTime.tryParse('${row['updated_at']}') ?? DateTime.now(),
        encryptionState: PasswordEncryptionState.unsealed,
      );
    } else {
      return PasswordEntry(
        id: row['id'] as String,
        nickname: (row['nickname'] as String?) ?? '',
        password: sealed,
        consent: (row['consent'] as bool?) ?? false,
        createdAt: DateTime.tryParse('${row['created_at']}') ?? DateTime.now(),
        updatedAt: DateTime.tryParse('${row['updated_at']}') ?? DateTime.now(),
        encryptionState: PasswordEncryptionState.sealed,
      );
    }
  }

  /// Re-seals every locally-cached entry under the vault's current key, and
  /// drops server rows this device cannot account for.
  ///
  /// Called immediately after [VaultCrypto.resetPassphrase].
  ///
  /// MANDATORY DEFENSE: Reseal MUST refuse to execute unless entries were actually
  /// decrypted under the vault key. If the store was hydrated while locked, or if
  /// any entry is marked sealed, this method immediately aborts and makes ZERO writes
  /// to Supabase or local storage.
  Future<bool> resealForNewKey() async {
    if (!VaultCrypto.instance.isUnlocked) {
      developer.log('resealForNewKey aborted: vault is locked', name: 'vault');
      return false;
    }

    if (_hydratedWhileLocked || hasSealedEntries || !allEntriesDecrypted) {
      developer.log(
        'resealForNewKey aborted: store contains sealed or unverified ciphertext entries (hydratedWhileLocked: $_hydratedWhileLocked, hasSealed: $hasSealedEntries, allDecrypted: $allEntriesDecrypted)',
        name: 'vault',
      );
      return false;
    }

    // Safety guard: An empty local vault MUST NEVER trigger an orphan sweep
    // that wipes the server vault.
    if (items.isEmpty) {
      developer.log(
        'resealForNewKey: local items is empty; aborting orphan sweep and reseal to prevent data loss',
        name: 'vault',
      );
      return false;
    }

    final local = {for (final e in items) e.id: e};

    // Explicitly verify each entry is unsealed before any writes
    for (final entry in local.values) {
      if (entry.isSealed || !entry.isDecrypted) {
        developer.log(
          'resealForNewKey aborted: entry ${entry.id} is sealed ciphertext',
          name: 'vault',
        );
        return false;
      }
    }

    SupabaseClient? client;
    String? uid;
    try {
      client = Supabase.instance.client;
      uid = client.auth.currentUser?.id;
    } catch (_) {}

    if (client != null && uid != null) {
      try {
        final rows = await client
            .from('w_password_vault')
            .select('id')
            .eq('auth_user_id', uid)
            .timeout(NetGuard.query);

        // Guard: If server has rows but local is somehow empty, abort deletion
        if (rows.isNotEmpty && local.isEmpty) {
          developer.log(
            'reseal: server has ${rows.length} rows but local is empty. Aborting orphan sweep.',
            name: 'vault',
          );
          return false;
        }

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
    }

    for (final entry in local.values) {
      try {
        // update() runs toRow(), which seals with whatever key is loaded now -
        // so this is the re-encryption of verified plaintext, not ciphertext.
        await update(entry);
      } catch (e) {
        developer.log('reseal: ${entry.id} failed: $e', name: 'vault');
      }
    }
    await persist();
    return true;
  }

  /// Securely persist items to platform Keystore/Keychain via FlutterSecureStorage.
  /// Passwords are encrypted before writing, so plaintext NEVER exists on disk.
  @override
  Future<void> persist() async {
    if (!isLoaded) {
      developer.log('PasswordStore persist skipped: store not loaded', name: 'vault');
      return;
    }
    try {
      String? uid = loadedUid;
      if (uid == null || uid.isEmpty) {
        try {
          uid = Supabase.instance.client.auth.currentUser?.id;
        } catch (_) {}
      }
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
        if (item.isDecrypted && VaultCrypto.instance.isUnlocked && item.password.isNotEmpty) {
          final sealed = await VaultCrypto.instance.encrypt(item.password);
          if (sealed != null) {
            row['password'] = sealed;
            row['isSealed'] = true;
            row['encryptionState'] = 'sealed';
          }
        } else if (item.isSealed) {
          // Already sealed! Do NOT encrypt again! Preserve existing ciphertext.
          row['isSealed'] = true;
          row['encryptionState'] = 'sealed';
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

  /// Clears in-memory vault state for the loaded owner UID.
  /// Does NOT delete secure storage on disk, ensuring account switching
  /// (A -> B -> A) and sign-out preserve user credentials without data loss.
  @override
  Future<void> clear() async {
    final ownerUid = loadedUid;
    items.clear();
    markUnloaded();
    notifyListeners();

    // Clean up any legacy prefs for this specific owner if present, but preserve secure storage
    if (ownerUid != null && ownerUid.isNotEmpty) {
      try {
        final p = await SharedPrefsCache.instance.prefsAsync;
        await p.remove('${storageKey}_$ownerUid');
      } catch (_) {}
    }
  }

  /// Purges local secure storage for [targetUid]. Only called on explicit account deletion.
  Future<void> purgeSecureStorageForUser(String targetUid) async {
    final key = '${storageKey}_$targetUid';
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
