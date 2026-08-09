import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/net/net_guard.dart';

/// End-to-end encryption for the Password Vault.
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
///   * Secrets are sealed with AES-GCM, which is authenticated: tampering with
///     the ciphertext makes decryption fail rather than return wrong plaintext.
///   * A [verifier] - the constant [_verifierPlaintext] sealed with that key -
///     lets the app tell a wrong passphrase from a corrupt vault, without ever
///     having anything to compare the passphrase itself against.
///
/// **What this deliberately cannot do.** There is no recovery. The passphrase is
/// the only thing that can derive the key, and nothing recoverable is stored
/// anywhere - that is the entire point. A user who forgets it loses the vault
/// contents, and the UI must say so plainly before they set one.
class VaultCrypto extends ChangeNotifier {
  VaultCrypto._();
  static final VaultCrypto instance = VaultCrypto._();

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

  SupabaseClient get _client => Supabase.instance.client;
  String? get _uid => _client.auth.currentUser?.id;

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
    if (uid == null) return null;
    try {
      final row = await _client
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

  /// Creates the vault key record for a first-time passphrase.
  ///
  /// Fails rather than overwrites if one already exists: the insert would
  /// replace the salt, and every secret sealed under the old key would become
  /// permanently unreadable.
  Future<bool> createPassphrase(String passphrase) async {
    final uid = _uid;
    if (uid == null || passphrase.isEmpty) return false;
    try {
      final salt = _randomBytes(32);
      final key = await _deriveKey(passphrase, salt);
      final verifier = await _seal(_verifierPlaintext, key);

      await _client.from(_table).insert({
        'auth_user_id': uid,
        'salt': base64Encode(salt),
        'verifier': verifier,
        'iterations': _iterations,
      });

      _key = key;
      notifyListeners();
      developer.log('vault passphrase created', name: 'vault');
      return true;
    } catch (e) {
      // A unique-violation here means a passphrase already exists - the caller
      // should be unlocking, not creating.
      developer.log('createPassphrase failed: $e', name: 'vault');
      return false;
    }
  }

  /// Derives the key from [passphrase] and checks it against the stored
  /// verifier. Returns false for a wrong passphrase; the vault stays locked.
  Future<bool> unlock(String passphrase) async {
    final uid = _uid;
    if (uid == null || passphrase.isEmpty) return false;
    try {
      final row = await _client
          .from(_table)
          .select('salt, verifier, iterations')
          .eq('auth_user_id', uid)
          .maybeSingle()
          .timeout(NetGuard.query);
      if (row == null) return false;

      final salt = base64Decode(row['salt'] as String);
      // Honour the iteration count the key was CREATED with, not today's
      // constant - otherwise raising _iterations would lock out every existing
      // vault.
      final iterations = (row['iterations'] as num?)?.toInt() ?? _iterations;
      final key = await _deriveKey(passphrase, salt, iterations: iterations);

      final opened = await _open(row['verifier'] as String, key);
      if (opened != _verifierPlaintext) return false;

      _key = key;
      notifyListeners();
      developer.log('vault unlocked', name: 'vault');
      return true;
    } catch (e) {
      // A MAC mismatch (wrong passphrase) lands here too - same answer, and
      // deliberately indistinguishable from any other failure to the caller.
      developer.log('unlock failed: $e', name: 'vault');
      return false;
    }
  }

  /// Drops the in-memory key. Called on sign-out and when the app is locked.
  void lock() {
    if (_key == null) return;
    _key = null;
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
