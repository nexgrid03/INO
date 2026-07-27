import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

/// Exercises the primitives behind the Password Vault's end-to-end encryption.
///
/// These test the crypto contract directly rather than through [VaultCrypto],
/// because that class needs a live Supabase session to reach `vault_keys`.
/// What matters here is the properties the scheme depends on - the same
/// algorithms, parameters and packing that vault_crypto.dart uses.
///
/// If any of these fail, credentials are not protected the way the schema
/// comment on `w_password_vault.secret` promises.
void main() {
  final algorithm = AesGcm.with256bits();

  // Low rounds ONLY so the suite stays fast. Production uses 210_000; see
  // VaultCrypto._iterations.
  Pbkdf2 kdf({int iterations = 1000}) => Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: iterations,
        bits: 256,
      );

  Future<String> seal(String plaintext, SecretKey key) async {
    final box = await algorithm.encrypt(utf8.encode(plaintext), secretKey: key);
    return base64Encode([...box.nonce, ...box.cipherText, ...box.mac.bytes]);
  }

  Future<String> open(String sealed, SecretKey key) async {
    final raw = base64Decode(sealed);
    const nonceLength = 12;
    final macLength = algorithm.macAlgorithm.macLength;
    final box = SecretBox(
      raw.sublist(nonceLength, raw.length - macLength),
      nonce: raw.sublist(0, nonceLength),
      mac: Mac(raw.sublist(raw.length - macLength)),
    );
    return utf8.decode(await algorithm.decrypt(box, secretKey: key));
  }

  const salt = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16];
  const passphrase = 'correct horse battery staple';

  group('key derivation', () {
    test('the same passphrase and salt always derive the same key', () async {
      final a = await kdf().deriveKeyFromPassword(
          password: passphrase, nonce: salt);
      final b = await kdf().deriveKeyFromPassword(
          password: passphrase, nonce: salt);
      expect(await a.extractBytes(), await b.extractBytes());
    });

    test('a different passphrase derives a different key', () async {
      final a = await kdf().deriveKeyFromPassword(
          password: passphrase, nonce: salt);
      final b = await kdf().deriveKeyFromPassword(
          password: 'not the passphrase', nonce: salt);
      expect(await a.extractBytes(), isNot(await b.extractBytes()));
    });

    test('a different salt derives a different key', () async {
      // This is why the salt is per-user: without it, two users who chose the
      // same passphrase would share a key, and one precomputed table would
      // open both vaults.
      final a = await kdf().deriveKeyFromPassword(
          password: passphrase, nonce: salt);
      final b = await kdf().deriveKeyFromPassword(
          password: passphrase, nonce: const [99, 98, 97, 96]);
      expect(await a.extractBytes(), isNot(await b.extractBytes()));
    });

    test('changing the iteration count changes the key', () async {
      // Which is exactly why `iterations` is stored per row: deriving with
      // today's constant instead of the stored one would lock out every vault
      // created before the constant was raised.
      final a = await kdf(iterations: 1000)
          .deriveKeyFromPassword(password: passphrase, nonce: salt);
      final b = await kdf(iterations: 2000)
          .deriveKeyFromPassword(password: passphrase, nonce: salt);
      expect(await a.extractBytes(), isNot(await b.extractBytes()));
    });
  });

  group('sealing', () {
    late SecretKey key;

    setUp(() async {
      key = await kdf().deriveKeyFromPassword(
          password: passphrase, nonce: salt);
    });

    test('round-trips a secret', () async {
      const secret = 'hunter2-éà中文-🔐';
      expect(await open(await seal(secret, key), key), secret);
    });

    test('the sealed value does not contain the plaintext', () async {
      const secret = 'MyBankPassword123';
      final sealed = await seal(secret, key);
      expect(sealed.contains(secret), isFalse);
      expect(utf8.decode(base64Decode(sealed), allowMalformed: true)
          .contains(secret), isFalse);
    });

    test('sealing twice yields different ciphertext', () async {
      // A fresh nonce per seal. Without this, identical passwords would produce
      // identical ciphertext and the table would leak which users share one.
      const secret = 'same-every-time';
      expect(await seal(secret, key), isNot(await seal(secret, key)));
    });

    test('a wrong key cannot open the secret', () async {
      final sealed = await seal('top secret', key);
      final wrong = await kdf().deriveKeyFromPassword(
          password: 'wrong passphrase', nonce: salt);
      expect(() => open(sealed, wrong), throwsA(isA<SecretBoxAuthenticationError>()));
    });

    test('tampered ciphertext is rejected rather than silently wrong',
        () async {
      // AES-GCM is authenticated: this is what stops someone with database
      // write access from flipping bits to change a stored credential.
      final sealed = await seal('top secret', key);
      final raw = base64Decode(sealed);
      raw[raw.length - 20] ^= 0xFF; // corrupt a ciphertext byte
      expect(
        () => open(base64Encode(raw), key),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });

    test('an empty secret round-trips', () async {
      expect(await open(await seal('', key), key), '');
    });
  });
}
