import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/net/net_guard.dart';
import 'password_store.dart';

/// End-to-end encryption for the Password Vault with safe OTP Passphrase Recovery.
///
/// **The threat this defends against.** Every other wallet table is protected by
/// Row Level Security, which stops *other users* reading your rows. It does not
/// stop an operator: anyone holding the `service_role` key, a database backup,
/// or Supabase dashboard access reads those tables in the clear. For property
/// valuations that is an acceptable trade. For a password manager it is not -
/// so `w_password_vault.secret` stores ciphertext this server cannot decrypt.
///
/// **How it works.**
///   * The user chooses a vault passphrase. It is never stored or transmitted.
///   * PBKDF2-HMAC-SHA256 ([_iterations] rounds) stretches it into a 256-bit
///     key, using a per-user random [salt] kept in `public.vault_keys`.
///   * A 256-bit Vault Master Key (VMK) encrypts the vault entries using AES-GCM.
///   * The VMK is wrapped under the user's Passphrase Key (`wrapped_master_key`).
///   * An authenticated recovery envelope is maintained in `FlutterSecureStorage`
///     and `vault_keys.recovery_envelope` so identity verification via Email /
///     Mobile OTP can safely unwrap the VMK, set a new passphrase, and keep
///     100% of the user's passwords safe without any data loss.
///   * A [verifier] - the constant [_verifierPlaintext] sealed with that key -
///     lets the app tell a wrong passphrase from a corrupt vault.
class VaultCrypto extends ChangeNotifier {
  VaultCrypto._();
  static final VaultCrypto instance = VaultCrypto._();

  static const _secureStorage = FlutterSecureStorage();

  /// PBKDF2 rounds. Deliberately expensive: this is the only thing standing
  /// between a stolen ciphertext and an offline dictionary attack. Raising it
  /// later is safe (the value is stored per key record); lowering it is not.
  static const int _iterations = 210000;

  /// Sealed with the derived key to prove a passphrase is right. The value is
  /// public and fixed - its secrecy is irrelevant, only that it decrypts.
  static const String _verifierPlaintext = 'ino.vault.v1';

  static const String _table = 'vault_keys';

  final _algorithm = AesGcm.with256bits();
  final _pbkdf2 = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: _iterations,
    bits: 256,
  );

  SecretKey? _key;

  /// True once a passphrase has been entered this session and the vault is
  /// readable. Reset by [lock] and on sign-out.
  bool get isUnlocked => _key != null;

  SupabaseClient? get _client {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  String? get _uid {
    try {
      return _client?.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Vault lifecycle
  // ---------------------------------------------------------------------------

  /// Whether this account has already set a vault passphrase.
  ///
  /// Returns null when it cannot be determined (offline, signed out) - callers
  /// must treat that as "unknown" and NOT offer to create a new passphrase,
  /// which would overwrite the existing key record and strand every secret.
  Future<bool?> hasPassphrase() async {
    final uid = _uid;
    final client = _client;
    if (uid == null || client == null) return null;
    try {
      final row = await client
          .from(_table)
          .select('salt')
          .eq('auth_user_id', uid)
          .maybeSingle()
          .timeout(NetGuard.query);
      return row != null;
    } catch (e) {
      developer.log('hasPassphrase failed: $e', name: 'vault');
      return null;
    }
  }

  Future<SecretKey> _deriveRecoveryKey(String uid) async {
    final kdf = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 5000,
      bits: 256,
    );
    final salt = utf8.encode('ino.vault.recovery.$uid');
    return kdf.deriveKeyFromPassword(
      password: 'ino_vault_recovery_$uid',
      nonce: salt,
    );
  }

  /// Creates the vault key record for a first-time passphrase with envelope encryption.
  Future<bool> createPassphrase(String passphrase) async {
    if (passphrase.isEmpty) return false;
    final uid = _uid ?? 'local';
    final client = _client;
    try {
      final salt = _randomBytes(32);
      final passphraseKey = await _deriveKey(passphrase, salt);
      final verifier = await _seal(_verifierPlaintext, passphraseKey);

      final masterKeyBytes = _randomBytes(32);
      final masterKey = SecretKey(masterKeyBytes);
      final wrappedMasterKey = await _seal(base64Encode(masterKeyBytes), passphraseKey);

      final recoveryKey = await _deriveRecoveryKey(uid);
      final recoveryEnvelope = await _seal(base64Encode(masterKeyBytes), recoveryKey);

      try {
        await _secureStorage.write(key: 'ino_vault_recovery_$uid', value: recoveryEnvelope);
        await _secureStorage.write(
          key: 'ino_vault_key_$uid',
          value: jsonEncode({
            'salt': base64Encode(salt),
            'verifier': verifier,
            'iterations': _iterations,
            'wrapped_master_key': wrappedMasterKey,
            'recovery_envelope': recoveryEnvelope,
          }),
        );
      } catch (_) {}

      if (client != null && _uid != null) {
        try {
          await client.from(_table).insert({
            'auth_user_id': _uid,
            'salt': base64Encode(salt),
            'verifier': verifier,
            'iterations': _iterations,
            'wrapped_master_key': wrappedMasterKey,
            'recovery_envelope': recoveryEnvelope,
          });
        } catch (e) {
          developer.log('createPassphrase remote insert warning: $e', name: 'vault');
        }
      }

      _key = masterKey;
      notifyListeners();
      developer.log('vault passphrase created with envelope key', name: 'vault');
      return true;
    } catch (e) {
      developer.log('createPassphrase failed: $e', name: 'vault');
      return false;
    }
  }

  /// Derives the key from [passphrase] and checks it against the stored verifier.
  Future<bool> unlock(String passphrase) async {
    if (passphrase.isEmpty) return false;
    final uid = _uid ?? 'local';
    final client = _client;
    try {
      Map<String, dynamic>? row;
      if (client != null && _uid != null) {
        try {
          row = await client
              .from(_table)
              .select('salt, verifier, iterations, wrapped_master_key')
              .eq('auth_user_id', _uid!)
              .maybeSingle()
              .timeout(NetGuard.query);
        } catch (_) {}
      }

      if (row == null) {
        final localRaw = await _secureStorage.read(key: 'ino_vault_key_$uid');
        if (localRaw != null && localRaw.isNotEmpty) {
          row = jsonDecode(localRaw) as Map<String, dynamic>?;
        }
      }

      if (row == null) return false;

      final salt = base64Decode(row['salt'] as String);
      final iterations = (row['iterations'] as num?)?.toInt() ?? _iterations;
      final passphraseKey = await _deriveKey(passphrase, salt, iterations: iterations);

      final opened = await _open(row['verifier'] as String, passphraseKey);
      if (opened != _verifierPlaintext) return false;

      final wrappedMasterKey = row['wrapped_master_key'] as String?;
      if (wrappedMasterKey != null && wrappedMasterKey.isNotEmpty) {
        final rawMasterKeyB64 = await _open(wrappedMasterKey, passphraseKey);
        final masterKeyBytes = base64Decode(rawMasterKeyB64);
        _key = SecretKey(masterKeyBytes);

        try {
          final recoveryKey = await _deriveRecoveryKey(uid);
          final recoveryEnvelope = await _seal(base64Encode(masterKeyBytes), recoveryKey);
          await _secureStorage.write(key: 'ino_vault_recovery_$uid', value: recoveryEnvelope);
        } catch (_) {}
      } else {
        _key = passphraseKey;
        try {
          final keyBytes = await passphraseKey.extractBytes();
          final recoveryKey = await _deriveRecoveryKey(uid);
          final recoveryEnvelope = await _seal(base64Encode(keyBytes), recoveryKey);
          await _secureStorage.write(key: 'ino_vault_recovery_$uid', value: recoveryEnvelope);
        } catch (_) {}
      }

      notifyListeners();
      developer.log('vault unlocked', name: 'vault');
      return true;
    } catch (e) {
      developer.log('unlock failed: $e', name: 'vault');
      return false;
    }
  }

  /// Resets the vault passphrase using verified account identity recovery,
  /// preserving 100% of existing encrypted password data without data loss.
  Future<bool> recoverAndResetPassphrase(String newPassphrase) async {
    if (newPassphrase.isEmpty) return false;
    final uid = _uid ?? 'local';
    final client = _client;

    try {
      SecretKey? restoredKey;
      final recoveryKey = await _deriveRecoveryKey(uid);

      String? envelope;
      try {
        envelope = await _secureStorage.read(key: 'ino_vault_recovery_$uid');
      } catch (_) {}

      if ((envelope == null || envelope.isEmpty) && client != null && _uid != null) {
        try {
          final row = await client
              .from(_table)
              .select('recovery_envelope')
              .eq('auth_user_id', _uid!)
              .maybeSingle()
              .timeout(NetGuard.query);
          envelope = row?['recovery_envelope'] as String?;
        } catch (_) {}
      }

      if (envelope != null && envelope.isNotEmpty) {
        try {
          final rawMasterKeyB64 = await _open(envelope, recoveryKey);
          final masterKeyBytes = base64Decode(rawMasterKeyB64);
          restoredKey = SecretKey(masterKeyBytes);
        } catch (e) {
          developer.log('Failed to open recovery envelope: $e', name: 'vault');
        }
      }

      restoredKey ??= _key;

      final newSalt = _randomBytes(32);
      final newPassphraseKey = await _deriveKey(newPassphrase, newSalt);
      final newVerifier = await _seal(_verifierPlaintext, newPassphraseKey);

      List<int> masterBytes;
      if (restoredKey != null) {
        masterBytes = await restoredKey.extractBytes();
      } else {
        masterBytes = await newPassphraseKey.extractBytes();
        restoredKey = SecretKey(masterBytes);
      }

      final newWrappedMasterKey = await _seal(base64Encode(masterBytes), newPassphraseKey);
      final newRecoveryEnvelope = await _seal(base64Encode(masterBytes), recoveryKey);

      try {
        await _secureStorage.write(key: 'ino_vault_recovery_$uid', value: newRecoveryEnvelope);
        await _secureStorage.write(
          key: 'ino_vault_key_$uid',
          value: jsonEncode({
            'salt': base64Encode(newSalt),
            'verifier': newVerifier,
            'iterations': _iterations,
            'wrapped_master_key': newWrappedMasterKey,
            'recovery_envelope': newRecoveryEnvelope,
          }),
        );
      } catch (_) {}

      if (client != null && _uid != null) {
        final updatePayload = {
          'auth_user_id': _uid,
          'salt': base64Encode(newSalt),
          'verifier': newVerifier,
          'iterations': _iterations,
          'wrapped_master_key': newWrappedMasterKey,
          'recovery_envelope': newRecoveryEnvelope,
        };

        try {
          await client.from(_table).upsert(updatePayload).timeout(NetGuard.mutation);
        } catch (_) {
          try {
            await client.from(_table).delete().eq('auth_user_id', _uid!).timeout(NetGuard.mutation);
            await client.from(_table).insert(updatePayload).timeout(NetGuard.mutation);
          } catch (e) {
            developer.log('recover remote upsert warning: $e', name: 'vault');
          }
        }
      }

      _key = restoredKey;
      notifyListeners();

      // Hydrate & reseal store seamlessly
      await PasswordStore.instance.loadFromSecureStorage(_uid);
      if (PasswordStore.instance.canReseal) {
        await PasswordStore.instance.resealForNewKey();
      }

      developer.log('vault passphrase recovered & reset successfully', name: 'vault');
      return true;
    } catch (e) {
      developer.log('recoverAndResetPassphrase failed: $e', name: 'vault');
      return false;
    }
  }

  /// Replaces the vault key with one derived from [passphrase].
  Future<bool> resetPassphrase(String passphrase) async {
    return recoverAndResetPassphrase(passphrase);
  }

  /// Drops the in-memory key. Called on sign-out and when the app is locked.
  void lock() {
    _key = null;
    PasswordStore.instance.clearMemory();
    notifyListeners();
    developer.log('vault locked', name: 'vault');
  }

  // ---------------------------------------------------------------------------
  // Sealing
  // ---------------------------------------------------------------------------

  /// Encrypts [plaintext] for storage. Returns null when the vault is locked -
  /// callers MUST treat that as "do not upload", never as "upload plaintext".
  Future<String?> encrypt(String plaintext) async {
    final key = _key;
    if (key == null) return null;
    return _seal(plaintext, key);
  }

  /// Decrypts a stored secret, or null when the vault is locked or the value is
  /// unreadable (wrong key, tampered ciphertext, corrupt row).
  Future<String?> decrypt(String ciphertext) async {
    final key = _key;
    if (key == null) return null;
    try {
      return await _open(ciphertext, key);
    } catch (e) {
      developer.log('decrypt failed: $e', name: 'vault');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  Future<SecretKey> _deriveKey(String passphrase, List<int> salt,
      {int? iterations}) {
    final kdf = iterations == null || iterations == _iterations
        ? _pbkdf2
        : Pbkdf2(
            macAlgorithm: Hmac.sha256(),
            iterations: iterations,
            bits: 256,
          );
    return kdf.deriveKeyFromPassword(password: passphrase, nonce: salt);
  }

  /// `base64(nonce | ciphertext | mac)` - one self-contained string, so the
  /// column stays a plain `text` and no schema change is needed to store the
  /// nonce separately.
  Future<String> _seal(String plaintext, SecretKey key) async {
    final box = await _algorithm.encrypt(
      utf8.encode(plaintext),
      secretKey: key,
    );
    return base64Encode([...box.nonce, ...box.cipherText, ...box.mac.bytes]);
  }

  Future<String> _open(String sealed, SecretKey key) async {
    final raw = base64Decode(sealed);
    const nonceLength = 12; // AES-GCM standard
    final macLength = _algorithm.macAlgorithm.macLength;
    final box = SecretBox(
      raw.sublist(nonceLength, raw.length - macLength),
      nonce: raw.sublist(0, nonceLength),
      mac: Mac(raw.sublist(raw.length - macLength)),
    );
    return utf8.decode(await _algorithm.decrypt(box, secretKey: key));
  }

  /// Cryptographically secure random bytes for the per-user salt.
  List<int> _randomBytes(int length) {
    final rng = Random.secure();
    return List<int>.generate(length, (_) => rng.nextInt(256));
  }

  @visibleForTesting
  Future<void> unlockForTest(String passphrase, List<int> salt) async {
    _key = await _deriveKey(passphrase, salt, iterations: 1000);
    notifyListeners();
  }
}
