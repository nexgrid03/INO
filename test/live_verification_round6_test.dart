// ignore_for_file: avoid_print
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:inoapp/core/storage/shared_prefs_cache.dart';
import 'package:inoapp/models/password_models.dart';
import 'package:inoapp/services/password_store.dart';
import 'package:inoapp/services/vault_crypto.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ROUND 6: CRITICAL LIVE SECURITY VERIFICATION', () {
    const testUser = 'user_live_verify_r6';
    const storageKey = 'ino_passwords_$testUser';
    final salt = List<int>.generate(32, (i) => i + 7);
    final secure = const FlutterSecureStorage();

    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
      SharedPrefsCache.resetForTesting();
      VaultCrypto.instance.lock();
      PasswordStore.instance.reset();
    });

    test('Scenario A: Locked vault -> forgot passphrase aborts safely without corrupting or writing ciphertext', () async {
      print('\n[SCENARIO A] Locked Vault -> Forgot Passphrase Reset Attempt');
      const originalCiphertext = 'AES_GCM_RAW_SEALED_CIPHER_777';
      final initialPayload = [
        {
          'id': 'entry_scenario_a',
          'nickname': 'Primary Bank',
          'password': originalCiphertext,
          'consent': true,
          'createdAt': DateTime.now().toIso8601String(),
          'updatedAt': DateTime.now().toIso8601String(),
          'isSealed': true,
          'encryptionState': 'sealed',
        }
      ];
      await secure.write(key: storageKey, value: jsonEncode(initialPayload));

      // 1. Hydrate while locked
      await PasswordStore.instance.loadFromSecureStorage(testUser);
      expect(PasswordStore.instance.hydratedWhileLocked, isTrue);
      expect(PasswordStore.instance.hasSealedEntries, isTrue);
      expect(PasswordStore.instance.allEntriesDecrypted, isFalse);
      expect(PasswordStore.instance.canReseal, isFalse);

      final entryA = PasswordStore.instance.items.first;
      expect(entryA.isSealed, isTrue);
      expect(entryA.isDecrypted, isFalse);
      expect(entryA.password, equals(originalCiphertext));

      // 2. Snapshot disk before reset attempt
      final diskBefore = await secure.read(key: storageKey);

      // 3. Attempt resetPassphrase
      final resetAttempt = await VaultCrypto.instance.resetPassphrase('AttemptedNewPassphrase!');
      expect(resetAttempt, isFalse);

      // 4. Attempt resealForNewKey directly
      final resealAttempt = await PasswordStore.instance.resealForNewKey();
      expect(resealAttempt, isFalse);

      // 5. Verify local storage has ZERO changes
      final diskAfter = await secure.read(key: storageKey);
      expect(diskAfter, equals(diskBefore));
      print('  Verified local disk cache had ZERO writes. Safe abort confirmed.');
      print('  --> SCENARIO A PASSED SAFELY.');
    });

    test('Scenario B: Unlocked vault -> forgot passphrase reseals cleanly, plaintext survives', () async {
      print('\n[SCENARIO B] Unlocked Vault -> Passphrase Reset');
      const originalPlaintext = 'MySecretBankPlaintext#2026';

      // 1. Unlock vault with Key 1
      await VaultCrypto.instance.unlockForTest('OriginalPassphrase#1', salt);
      expect(VaultCrypto.instance.isUnlocked, isTrue);

      // 2. Hydrate store while unlocked
      await PasswordStore.instance.loadFromSecureStorage(testUser);

      // 3. Add legitimate decrypted entry
      final legitimateEntry = PasswordEntry(
        id: 'entry_scenario_b',
        nickname: 'Trading Account',
        password: originalPlaintext,
        consent: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        encryptionState: PasswordEncryptionState.unsealed,
      );
      PasswordStore.instance.items.add(legitimateEntry);
      await PasswordStore.instance.persist();
      expect(PasswordStore.instance.canReseal, isTrue);

      // 4. Unlock with new passphrase (Key 2)
      await VaultCrypto.instance.unlockForTest('NewStrongPassphrase#2', salt);

      // 5. Reseal
      final resealSuccess = await PasswordStore.instance.resealForNewKey();
      expect(resealSuccess, isTrue);

      // 6. Verify in-memory plaintext is intact
      final memoryEntry = PasswordStore.instance.items.first;
      expect(memoryEntry.password, equals(originalPlaintext));

      // 7. Verify disk payload is encrypted under Key 2
      final diskB = await secure.read(key: storageKey);
      expect(diskB, isNotNull);
      final listB = jsonDecode(diskB!) as List<dynamic>;
      final diskCiphertext = (listB.first as Map<String, dynamic>)['password'] as String;
      expect(diskCiphertext, isNot(equals(originalPlaintext)));

      final decryptedUnderKey2 = await VaultCrypto.instance.decrypt(diskCiphertext);
      expect(decryptedUnderKey2, equals(originalPlaintext));
      print('  Decrypted from disk using new key: $decryptedUnderKey2');
      print('  --> SCENARIO B PASSED CLEANLY.');
    });

    test('Scenario C: Reopen app with new key — passwords remain correct without double-encryption', () async {
      print('\n[SCENARIO C] App Restart & Reopen Simulation');
      const originalPlaintext = 'MySecretBankPlaintext#2026';

      // Setup sealed entry under Key 2
      await VaultCrypto.instance.unlockForTest('NewStrongPassphrase#2', salt);
      final sealed = await VaultCrypto.instance.encrypt(originalPlaintext);
      expect(sealed, isNotNull);

      final diskPayload = [
        {
          'id': 'entry_scenario_c',
          'nickname': 'Trading Account',
          'password': sealed,
          'consent': true,
          'createdAt': DateTime.now().toIso8601String(),
          'updatedAt': DateTime.now().toIso8601String(),
          'isSealed': true,
          'encryptionState': 'sealed',
        }
      ];
      await secure.write(key: storageKey, value: jsonEncode(diskPayload));

      // 1. Terminate session (lock crypto, clear memory store)
      VaultCrypto.instance.lock();
      PasswordStore.instance.clearMemory();
      expect(PasswordStore.instance.items.isEmpty, isTrue);
      expect(VaultCrypto.instance.isUnlocked, isFalse);

      // 2. Hydrate on app launch while locked
      await PasswordStore.instance.loadFromSecureStorage(testUser);
      expect(PasswordStore.instance.items.first.isSealed, isTrue);
      expect(PasswordStore.instance.canReseal, isFalse);

      // 3. User enters new passphrase to unlock
      await VaultCrypto.instance.unlockForTest('NewStrongPassphrase#2', salt);

      // 4. Decrypt entries in store
      await PasswordStore.instance.loadFromSecureStorage(testUser);
      final reopenedEntry = PasswordStore.instance.items.first;
      expect(reopenedEntry.password, equals(originalPlaintext));
      expect(reopenedEntry.isDecrypted, isTrue);
      expect(reopenedEntry.isSealed, isFalse);
      print('  Decrypted entry after unlock: ${reopenedEntry.nickname} -> ${reopenedEntry.password}');
      print('  --> SCENARIO C PASSED WITH ZERO CORRUPTION.');
    });
  });
}
