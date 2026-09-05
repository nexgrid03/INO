import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Hardware-backed secure storage for Supabase authentication sessions.
///
/// Encrypts session tokens using Android Keystore / EncryptedSharedPreferences
/// and iOS Keychain. Transparently migrates any existing plaintext session from
/// legacy [SharedPreferences] to ensure users remain logged in without interruption.
class SecureLocalStorage extends LocalStorage {
  SecureLocalStorage({
    this.persistSessionKey = 'supabase.auth.token',
    FlutterSecureStorage? secureStorage,
  }) : _storage = secureStorage ?? const FlutterSecureStorage();

  final String persistSessionKey;
  final FlutterSecureStorage _storage;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() async {
    final token = await accessToken();
    return token != null && token.isNotEmpty;
  }

  @override
  Future<String?> accessToken() async {
    try {
      final secureVal = await _storage.read(key: persistSessionKey);
      if (secureVal != null && secureVal.isNotEmpty) {
        return secureVal;
      }
    } catch (_) {}

    // Migration fallback: check legacy SharedPreferences to preserve active sessions
    try {
      final prefs = await SharedPreferences.getInstance();
      final legacyVal = prefs.getString(persistSessionKey);
      if (legacyVal != null && legacyVal.isNotEmpty) {
        try {
          await _storage.write(key: persistSessionKey, value: legacyVal);
          await prefs.remove(persistSessionKey);
        } catch (_) {}
        return legacyVal;
      }
    } catch (_) {}

    return null;
  }

  @override
  Future<void> persistSession(String persistSessionString) async {
    try {
      await _storage.write(
        key: persistSessionKey,
        value: persistSessionString,
      );
      // Clean up legacy plaintext copy from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(persistSessionKey);
    } catch (_) {
      // Defensive fallback if hardware keystore throws
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(persistSessionKey, persistSessionString);
    }
  }

  @override
  Future<void> removePersistedSession() async {
    try {
      await _storage.delete(key: persistSessionKey);
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(persistSessionKey);
    } catch (_) {}
  }
}
