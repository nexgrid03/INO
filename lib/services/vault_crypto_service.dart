import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

/// Zero-knowledge cryptography for the Password Vault.
///
/// The master password never leaves the device and is never stored. From it we
/// derive a 256-bit key with PBKDF2-HMAC-SHA256 (a per-user random salt +
/// configurable iterations), and use it with AES-GCM (authenticated encryption)
/// to seal each entry's secret fields. Supabase only ever sees ciphertext.
///
/// Ciphertext wire format (base64): `nonce(12) || cipherText || mac(16)`.
class VaultCryptoService {
  VaultCryptoService._();
  static final VaultCryptoService instance = VaultCryptoService._();

  static const int _nonceLength = 12; // AES-GCM standard nonce
  static const int _macLength = 16; // GCM tag
  static const int defaultIterations = 150000;

  final AesGcm _aes = AesGcm.with256bits();
  final Random _random = Random.secure();

  /// A fresh 16-byte random salt, base64-encoded for storage.
  String generateSalt() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return base64Encode(bytes);
  }

  /// Derives the AES key from [masterPassword] and the stored [saltB64].
  Future<SecretKey> deriveKey(
    String masterPassword,
    String saltB64, {
    int iterations = defaultIterations,
  }) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    );
    return pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(masterPassword)),
      nonce: base64Decode(saltB64),
    );
  }

  /// Rebuilds a [SecretKey] from raw bytes cached in secure storage.
  SecretKey keyFromBytes(List<int> bytes) => SecretKey(bytes);

  /// Encrypts [plaintext] with [key], returning the packed base64 blob.
  Future<String> encrypt(String plaintext, SecretKey key) async {
    final box = await _aes.encrypt(utf8.encode(plaintext), secretKey: key);
    final packed = <int>[...box.nonce, ...box.cipherText, ...box.mac.bytes];
    return base64Encode(packed);
  }

  /// Decrypts a packed base64 [blob] produced by [encrypt].
  ///
  /// Throws [SecretBoxAuthenticationError] if the key is wrong or the data was
  /// tampered with — callers use that to detect an incorrect master password.
  Future<String> decrypt(String blob, SecretKey key) async {
    final bytes = base64Decode(blob);
    final nonce = bytes.sublist(0, _nonceLength);
    final mac = Mac(bytes.sublist(bytes.length - _macLength));
    final cipherText = bytes.sublist(_nonceLength, bytes.length - _macLength);
    final clear = await _aes.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: mac),
      secretKey: key,
    );
    return utf8.decode(clear);
  }
}
