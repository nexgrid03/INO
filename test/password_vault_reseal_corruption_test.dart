import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/core/storage/shared_prefs_cache.dart';
import 'package:inoapp/models/password_models.dart';
import 'package:inoapp/services/password_store.dart';
import 'package:inoapp/services/vault_crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testUser = 'user_vault_audit_6';
  const storageKey = 'ino_passwords_$testUser';
  final salt = List<int>.generate(32, (i) => i + 1);

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    SharedPrefsCache.resetForTesting();
    VaultCrypto.instance.lock();
    PasswordStore.instance.reset();
  });

  tearDown(() {
    VaultCrypto.instance.lock();
    PasswordStore.instance.reset();
  });

  group('CRITICAL SECURITY REMEDIATION – ROUND 6: Passphrase Reset Corruption Prevention', () {
    test('TEST 1: Hydrate while locked — entries remain marked sealed, reseal is rejected', () async {
      final secure = const FlutterSecureStorage();
      const mockCiphertext = 'AES_GCM_MOCK_CIPHERTEXT_12345';

      // Seed sealed entries into secure storage
      final sealedDiskPayload = [
        {
          'id': 'entry_1',
          'nickname': 'Bank Login',
          'password': mockCiphertext,
          'consent': true,
          'createdAt': DateTime.now().toIso8601String(),
          'updatedAt': DateTime.now().toIso8601String(),
          'isSealed': true,
          'encryptionState': 'sealed',
        }
      ];
      await secure.write(key: storageKey, value: jsonEncode(sealedDiskPayload));

      // Vault is locked
      expect(VaultCrypto.instance.isUnlocked, isFalse);

      // Hydrate from secure storage while locked
      await PasswordStore.instance.loadFromSecureStorage(testUser);

      expect(PasswordStore.instance.items.length, equals(1));
      final entry = PasswordStore.instance.items.first;

      // VERIFY: entries remain marked sealed
      expect(entry.encryptionState, equals(PasswordEncryptionState.sealed));
      expect(entry.isSealed, isTrue);
      expect(entry.isDecrypted, isFalse);
      expect(entry.password, equals(mockCiphertext)); // Raw ciphertext preserved
      expect(PasswordStore.instance.hydratedWhileLocked, isTrue);
      expect(PasswordStore.instance.hasSealedEntries, isTrue);
      expect(PasswordStore.instance.allEntriesDecrypted, isFalse);

      // VERIFY: reseal is rejected
      expect(PasswordStore.instance.canReseal, isFalse);
      final resealResult = await PasswordStore.instance.resealForNewKey();
      expect(resealResult, isFalse, reason: 'resealForNewKey must abort when entries are sealed');
    });

    test('TEST 2: Forgot passphrase while locked — operation aborts, no writes occur', () async {
      final secure = const FlutterSecureStorage();
      const initialCiphertext = 'INITIAL_SEALED_CIPHERTEXT_ABC';

      final sealedPayload = [
        {
          'id': 'entry_locked_test',
          'nickname': 'Email Vault',
          'password': initialCiphertext,
          'consent': true,
          'createdAt': DateTime.now().toIso8601String(),
          'updatedAt': DateTime.now().toIso8601String(),
          'isSealed': true,
          'encryptionState': 'sealed',
        }
      ];
      await secure.write(key: storageKey, value: jsonEncode(sealedPayload));

      // Hydrate while locked
      await PasswordStore.instance.loadFromSecureStorage(testUser);
      expect(PasswordStore.instance.canReseal, isFalse);

      // Record storage state before attempted reset
      final storageBefore = await secure.read(key: storageKey);

      // Attempt forgot-passphrase reset while locked
      final resetResult = await VaultCrypto.instance.resetPassphrase('BrandNewPassphrase123!');

      // VERIFY: operation aborts
      expect(resetResult, isFalse, reason: 'resetPassphrase must refuse when PasswordStore contains sealed ciphertext');
      expect(VaultCrypto.instance.isUnlocked, isFalse);

      final resealResult = await PasswordStore.instance.resealForNewKey();
      expect(resealResult, isFalse);

      // VERIFY: no writes occur to local storage
      final storageAfter = await secure.read(key: storageKey);
      expect(storageAfter, equals(storageBefore));
    });

    test('TEST 3: Forgot passphrase after successful unlock — reseal succeeds, plaintext survives, vault remains readable', () async {
      final secure = const FlutterSecureStorage();
      const originalPlaintext = 'SuperSecretPlaintextPassword_987!';

      // 1. Unlock vault with initial passphrase
      await VaultCrypto.instance.unlockForTest('OriginalPassphrase123!', salt);
      expect(VaultCrypto.instance.isUnlocked, isTrue);

      // Hydrate store while unlocked
      await PasswordStore.instance.loadFromSecureStorage(testUser);
      expect(PasswordStore.instance.isLoaded, isTrue);
      expect(PasswordStore.instance.hydratedWhileLocked, isFalse);

      // 2. Add an entry in decrypted plaintext state
      final originalEntry = PasswordEntry(
        id: 'entry_unlocked_test',
        nickname: 'Streaming Account',
        password: originalPlaintext,
        consent: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        encryptionState: PasswordEncryptionState.unsealed,
      );
      PasswordStore.instance.items.add(originalEntry);
      await PasswordStore.instance.persist();

      // Verify entry is unsealed & decrypted
      expect(PasswordStore.instance.canReseal, isTrue);
      expect(PasswordStore.instance.allEntriesDecrypted, isTrue);
      expect(PasswordStore.instance.hasSealedEntries, isFalse);

      // 3. User resets passphrase while unlocked
      // Derive new key for test
      await VaultCrypto.instance.unlockForTest('NewPassphrase456!', salt);

      // 4. Run resealForNewKey
      final resealResult = await PasswordStore.instance.resealForNewKey();
      expect(resealResult, isTrue, reason: 'resealForNewKey must succeed when all entries are verified plaintext');

      // 5. Plaintext survives in memory
      expect(PasswordStore.instance.items.first.password, equals(originalPlaintext));
      expect(PasswordStore.instance.items.first.isDecrypted, isTrue);

      // 6. Verify sealed payload on disk can be decrypted by new key
      final diskRaw = await secure.read(key: storageKey);
      expect(diskRaw, isNotNull);
      final diskList = jsonDecode(diskRaw!) as List<dynamic>;
      final diskItem = diskList.first as Map<String, dynamic>;
      final diskCiphertext = diskItem['password'] as String;

      // The ciphertext on disk decrypts to the original plaintext under the new key
      final decrypted = await VaultCrypto.instance.decrypt(diskCiphertext);
      expect(decrypted, equals(originalPlaintext));
    });

    test('TEST 4: Ciphertext re-encryption prevention — injected encrypted records cannot be encrypted again', () async {
      await VaultCrypto.instance.unlockForTest('TestPassphrase123!', salt);
      await PasswordStore.instance.loadFromSecureStorage(testUser);
      expect(PasswordStore.instance.isLoaded, isTrue);

      const injectedCiphertext = 'CIPHERTEXT_BLOB_NONCE_PAYLOAD_MAC';

      // Inject an encrypted record marked sealed
      final encryptedEntry = PasswordEntry(
        id: 'injected_sealed',
        nickname: 'Injected Record',
        password: injectedCiphertext,
        consent: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        encryptionState: PasswordEncryptionState.sealed,
      );

      // VERIFY: toRow refuses to upload or re-encrypt sealed entry
      expect(
        () => PasswordStore.instance.toRow(encryptedEntry),
        throwsA(isA<StateError>()),
        reason: 'toRow must throw StateError when given an entry marked sealed',
      );

      // VERIFY: persist does not re-encrypt sealed entry
      PasswordStore.instance.items.add(encryptedEntry);
      await PasswordStore.instance.persist();

      final secure = const FlutterSecureStorage();
      final diskRaw = await secure.read(key: storageKey);
      expect(diskRaw, isNotNull);
      final diskList = jsonDecode(diskRaw!) as List<dynamic>;
      final diskEntry = diskList.first as Map<String, dynamic>;

      // The password on disk must be the exact injected ciphertext, NOT encrypted again
      expect(diskEntry['password'], equals(injectedCiphertext));
      expect(diskEntry['isSealed'], isTrue);
      expect(diskEntry['encryptionState'], equals('sealed'));
    });

    test('TEST 5: Server sync safety — failed reseal writes nothing to Supabase', () async {
      // Setup locked vault with sealed entry
      final sealedEntry = PasswordEntry(
        id: 'entry_server_safety',
        nickname: 'Cloud Account',
        password: 'SEALED_CIPHER_SERVER_TEST',
        consent: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        encryptionState: PasswordEncryptionState.sealed,
      );
      PasswordStore.instance.items.add(sealedEntry);

      // Attempt reseal while locked / sealed
      final result = await PasswordStore.instance.resealForNewKey();
      expect(result, isFalse);

      // syncTable returns null when locked (guaranteeing zero sync calls)
      expect(PasswordStore.instance.syncTable, isNull);

      // toRow refuses to execute on sealed entry
      expect(
        () => PasswordStore.instance.toRow(sealedEntry),
        throwsA(isA<StateError>()),
      );
    });

    test('TEST 6: Offline cache safety — failed reseal writes nothing locally', () async {
      final secure = const FlutterSecureStorage();
      const originalCache = '[{"id":"cache_test","nickname":"Old Cache","password":"CIPHER_ORIGINAL","isSealed":true,"encryptionState":"sealed"}]';
      await secure.write(key: storageKey, value: originalCache);

      // Load while locked
      await PasswordStore.instance.loadFromSecureStorage(testUser);
      expect(PasswordStore.instance.hasSealedEntries, isTrue);

      // Failed reseal
      final result = await PasswordStore.instance.resealForNewKey();
      expect(result, isFalse);

      // VERIFY: local cache was not overwritten or corrupted
      final currentCache = await secure.read(key: storageKey);
      expect(currentCache, equals(originalCache));
    });

    test('TEST 7: Regression — normal unlock, save, sync, and password updates still work', () async {
      // 1. Normal unlock
      await VaultCrypto.instance.unlockForTest('NormalPassphrase123!', salt);
      expect(VaultCrypto.instance.isUnlocked, isTrue);
      expect(PasswordStore.instance.syncTable, equals('w_password_vault'));

      // 2. Normal save
      final newEntry = PasswordEntry(
        id: 'normal_save_1',
        nickname: 'My Bank',
        password: 'NormalPassword123!',
        consent: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        encryptionState: PasswordEncryptionState.unsealed,
      );
      PasswordStore.instance.items.add(newEntry);
      await PasswordStore.instance.persist();

      // 3. Normal sync row generation
      final row = await PasswordStore.instance.toRow(newEntry);
      expect(row['nickname'], equals('My Bank'));
      expect(row['password'], isNotNull);
      expect(row['password'], isNot(equals('NormalPassword123!')), reason: 'Row password must be sealed ciphertext');

      // 4. Normal password update
      final updatedEntry = newEntry.copyWith(
        password: 'UpdatedPassword456!',
        updatedAt: DateTime.now(),
      );
      expect(updatedEntry.password, equals('UpdatedPassword456!'));
      expect(updatedEntry.isDecrypted, isTrue);

      final updatedRow = await PasswordStore.instance.toRow(updatedEntry);
      expect(updatedRow['password'], isNotNull);
      expect(updatedRow['password'], isNot(equals('UpdatedPassword456!')));

      // Decrypt verification
      final decrypted = await VaultCrypto.instance.decrypt(updatedRow['password'] as String);
      expect(decrypted, equals('UpdatedPassword456!'));
    });
  });
}
