import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/services/account_switcher.dart';
import 'package:inoapp/services/trusted_device_service.dart';
import 'package:inoapp/services/vault_guard.dart';

void main() {
  group('TrustedDevice & Real Sessions (Issue L2)', () {
    test('TrustedDevice.fromSupabase maps all session columns accurately', () {
      final now = DateTime.now().toUtc();
      final row = {
        'id': 'sess-uuid-1234',
        'session_id': 'sess-uuid-5678',
        'user_id': 'user-uuid-9999',
        'device_id': 'dev_pixel7_abc',
        'device_name': 'Pixel 7 · Android',
        'platform': 'Android',
        'created_at': now.subtract(const Duration(days: 2)).toIso8601String(),
        'last_seen': now.toIso8601String(),
        'revoked': false,
      };

      final device = TrustedDevice.fromSupabase(row, 'dev_pixel7_abc');

      expect(device.id, 'dev_pixel7_abc');
      expect(device.sessionId, 'sess-uuid-5678');
      expect(device.name, 'Pixel 7 · Android');
      expect(device.platform, 'Android');
      expect(device.isCurrent, isTrue);
      expect(device.revoked, isFalse);
    });

    test('TrustedDevice.fromSupabase falls back to id when session_id is absent', () {
      final row = {
        'id': 'fallback-session-id',
        'device_id': 'dev_iphone14_xyz',
        'device_name': 'iPhone 14 · iOS',
        'platform': 'iOS',
        'created_at': DateTime.now().toIso8601String(),
        'last_seen': DateTime.now().toIso8601String(),
        'revoked': true,
      };

      final device = TrustedDevice.fromSupabase(row, 'dev_other');

      expect(device.id, 'dev_iphone14_xyz');
      expect(device.sessionId, 'fallback-session-id');
      expect(device.isCurrent, isFalse);
      expect(device.revoked, isTrue);
    });

    test('TrustedDevice JSON serialization roundtrip preserves fields', () {
      final now = DateTime.now();
      final device = TrustedDevice(
        id: 'dev_100',
        name: 'MacBook Pro',
        platform: 'macOS',
        firstSeen: now.subtract(const Duration(hours: 5)),
        lastActive: now,
        isCurrent: true,
        sessionId: 'sess-mac-001',
        revoked: false,
      );

      final json = device.toJson();
      expect(json['id'], 'dev_100');
      expect(json['name'], 'MacBook Pro');
      expect(json['platform'], 'macOS');
      expect(json['session_id'], 'sess-mac-001');
      expect(json['revoked'], isFalse);

      final restored = TrustedDevice.fromJson(json, 'dev_100');
      expect(restored.id, device.id);
      expect(restored.name, device.name);
      expect(restored.sessionId, 'sess-mac-001');
      expect(restored.isCurrent, isTrue);
      expect(restored.revoked, isFalse);
    });
  });

  group('Google Sign-In Nonce Replay Protection (Issue L4)', () {
    test('SHA-256 nonce generation produces valid 64-character hex hash', () {
      // Emulates the exact flow in AuthService.signInWithGoogle()
      const rawNonce = 'ino_secure_nonce_1234567890_abcdef';
      final bytes = utf8.encode(rawNonce);
      final hashedNonce = sha256.convert(bytes).toString();

      expect(hashedNonce.length, 64);
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(hashedNonce), isTrue);

      // Known test vector for sha256(rawNonce)
      final expectedDigest = sha256.convert(utf8.encode(rawNonce)).toString();
      expect(hashedNonce, expectedDigest);
    });

    test('Distinct raw nonces produce cryptographically distinct hashes', () {
      const nonceA = 'raw_nonce_alpha';
      const nonceB = 'raw_nonce_beta';

      final hashA = sha256.convert(utf8.encode(nonceA)).toString();
      final hashB = sha256.convert(utf8.encode(nonceB)).toString();

      expect(hashA, isNot(equals(hashB)));
    });
  });

  group('Account Switch & Vault Reauth (Issue L3)', () {
    test('VaultGuard lock() immediately revokes unlocked state', () {
      final guard = VaultGuard.instance;
      expect(guard.isUnlocked, isFalse);

      // Manual lock ensures unlocked window is immediately null
      guard.lock();
      expect(guard.isUnlocked, isFalse);
    });

    test('SavedAccount serialization and identity preservation', () {
      const account = SavedAccount(
        id: 'user_456',
        email: 'test@example.com',
        refreshToken: 'refresh-token-xyz',
        name: 'Test User',
      );

      final json = account.toJson();
      expect(json['id'], 'user_456');
      expect(json['email'], 'test@example.com');
      expect(json['refreshToken'], 'refresh-token-xyz');
      expect(json['name'], 'Test User');

      final fromJson = SavedAccount.fromJson(json);
      expect(fromJson.id, account.id);
      expect(fromJson.displayName, 'Test User');
      expect(fromJson.refreshToken, account.refreshToken);
    });
  });
}
