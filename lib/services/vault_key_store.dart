import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'vault_crypto_service.dart';

/// On-device, Keystore-backed cache for the derived vault key.
///
/// After a successful unlock we keep the raw key bytes in Android's encrypted
/// [FlutterSecureStorage] (hardware-backed where available) so the user doesn't
/// re-enter their master password on every action. Locking the vault wipes it.
/// The key is namespaced per auth user so switching accounts can't cross over.
class VaultKeyStore {
  VaultKeyStore._();
  static final VaultKeyStore instance = VaultKeyStore._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  String _keyName(String userId) => 'vault_key_$userId';

  /// Persists the derived [key] for [userId].
  Future<void> cacheKey(String userId, SecretKey key) async {
    final bytes = await key.extractBytes();
    await _storage.write(key: _keyName(userId), value: base64Encode(bytes));
  }

  /// Returns the cached key for [userId], or null if the vault is locked.
  Future<SecretKey?> readKey(String userId) async {
    final value = await _storage.read(key: _keyName(userId));
    if (value == null) return null;
    return VaultCryptoService.instance.keyFromBytes(base64Decode(value));
  }

  /// Wipes the cached key (i.e. locks the vault) for [userId].
  Future<void> clear(String userId) async {
    await _storage.delete(key: _keyName(userId));
  }
}
