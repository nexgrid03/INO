import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/core/storage/shared_prefs_cache.dart';
import 'package:inoapp/models/password_models.dart';
import 'package:inoapp/services/password_store.dart';
import 'package:inoapp/services/vault_crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testUser = 'user_vault_recovery_test';

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

  group('Password Vault Safe OTP Passphrase Recovery Tests', () {
    test(
      'Envelope key recovery resets passphrase and preserves 100% of encrypted entries',
      () async {
        // 1. First time setup with initial passphrase
        const initialPassphrase = 'MyInitialSecretPassphrase123';
        const newPassphrase = 'MyNewRecoveredPassphrase456';

        // Simulate first-time setup
        final createSuccess = await VaultCrypto.instance.createPassphrase(
          initialPassphrase,
        );
        expect(createSuccess, isTrue);
        expect(VaultCrypto.instance.isUnlocked, isTrue);

        // 2. Initialize and load the store
        await PasswordStore.instance.loadFromSecureStorage(testUser);

        // Add an entry to the store
        const originalSecret = 'SuperSecretBankPin#9988';
        final entry = PasswordEntry(
          id: 'entry_bank',
          nickname: 'HDFC NetBanking',
          password: originalSecret,
          consent: true,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        await PasswordStore.instance.add(entry);
        await PasswordStore.instance.persist();

        expect(PasswordStore.instance.items.length, equals(1));
        expect(
          PasswordStore.instance.items.first.password,
          equals(originalSecret),
        );

        // 3. User locks the vault
        VaultCrypto.instance.lock();
        expect(VaultCrypto.instance.isUnlocked, isFalse);

        // 4. User forgot passphrase: runs recoverAndResetPassphrase
        final recoverSuccess = await VaultCrypto.instance
            .recoverAndResetPassphrase(newPassphrase);
        expect(recoverSuccess, isTrue);
        expect(VaultCrypto.instance.isUnlocked, isTrue);

        // 5. Verify the existing saved passwords are fully intact and decrypted
        await PasswordStore.instance.loadFromSecureStorage(testUser);
        expect(PasswordStore.instance.items.length, equals(1));
        final recoveredEntry = PasswordStore.instance.items.first;
        expect(recoveredEntry.nickname, equals('HDFC NetBanking'));
        expect(recoveredEntry.password, equals(originalSecret));
        expect(recoveredEntry.isDecrypted, isTrue);
      },
    );

    test(
      'a locked vault with no recovery envelope returns false and writes nothing',
      () async {
        const passphrase = 'OriginalPassphrase123';
        expect(await VaultCrypto.instance.createPassphrase(passphrase), isTrue);
        const secret = 'existing-bank-password';
        final sealed = await VaultCrypto.instance.encrypt(secret);
        expect(sealed, isNotNull);

        const storage = FlutterSecureStorage();
        await storage.delete(key: 'ino_vault_recovery_local');
        final metadataBefore = await storage.read(key: 'ino_vault_key_local');
        expect(metadataBefore, isNotNull);

        VaultCrypto.instance.lock();
        final changed = await VaultCrypto.instance.recoverAndResetPassphrase(
          'ReplacementPassphrase456',
        );

        expect(changed, isFalse);
        expect(VaultCrypto.instance.isUnlocked, isFalse);
        expect(await storage.read(key: 'ino_vault_recovery_local'), isNull);
        expect(await storage.read(key: 'ino_vault_key_local'), metadataBefore);
        expect(await VaultCrypto.instance.decrypt(sealed!), isNull);

        expect(await VaultCrypto.instance.unlock(passphrase), isTrue);
        expect(await VaultCrypto.instance.decrypt(sealed), secret);
      },
    );

    test(
      'a locked vault with a valid recovery envelope keeps the original master key',
      () async {
        const passphrase = 'OriginalPassphrase123';
        const replacement = 'ReplacementPassphrase456';
        expect(await VaultCrypto.instance.createPassphrase(passphrase), isTrue);
        const secret = 'existing-bank-password';
        final sealed = await VaultCrypto.instance.encrypt(secret);

        VaultCrypto.instance.lock();
        expect(
          await VaultCrypto.instance.recoverAndResetPassphrase(replacement),
          isTrue,
        );
        expect(await VaultCrypto.instance.decrypt(sealed!), secret);

        VaultCrypto.instance.lock();
        expect(await VaultCrypto.instance.unlock(passphrase), isFalse);
        expect(await VaultCrypto.instance.unlock(replacement), isTrue);
        expect(await VaultCrypto.instance.decrypt(sealed), secret);
      },
    );

    test(
      'an unlocked vault resets the passphrase with the in-memory master key',
      () async {
        const passphrase = 'OriginalPassphrase123';
        const replacement = 'ReplacementPassphrase456';
        expect(await VaultCrypto.instance.createPassphrase(passphrase), isTrue);
        const secret = 'existing-bank-password';
        final sealed = await VaultCrypto.instance.encrypt(secret);

        const storage = FlutterSecureStorage();
        await storage.delete(key: 'ino_vault_recovery_local');
        expect(VaultCrypto.instance.isUnlocked, isTrue);

        expect(
          await VaultCrypto.instance.recoverAndResetPassphrase(replacement),
          isTrue,
        );
        expect(await VaultCrypto.instance.decrypt(sealed!), secret);

        VaultCrypto.instance.lock();
        expect(await VaultCrypto.instance.unlock(replacement), isTrue);
        expect(await VaultCrypto.instance.decrypt(sealed), secret);
      },
    );

    test(
      'failed recovery leaves the stored vault metadata unchanged',
      () async {
        const passphrase = 'OriginalPassphrase123';
        expect(await VaultCrypto.instance.createPassphrase(passphrase), isTrue);

        const storage = FlutterSecureStorage();
        final metadataBefore = await storage.read(key: 'ino_vault_key_local');
        final envelopeBefore = await storage.read(
          key: 'ino_vault_recovery_local',
        );
        expect(metadataBefore, isNotNull);
        expect(envelopeBefore, isNotNull);
        await storage.write(
          key: 'ino_vault_recovery_local',
          value: 'not-a-valid-envelope',
        );

        VaultCrypto.instance.lock();
        expect(
          await VaultCrypto.instance.recoverAndResetPassphrase(
            'ReplacementPassphrase456',
          ),
          isFalse,
        );

        expect(await storage.read(key: 'ino_vault_key_local'), metadataBefore);
        expect(
          await storage.read(key: 'ino_vault_recovery_local'),
          'not-a-valid-envelope',
        );
        expect(VaultCrypto.instance.isUnlocked, isFalse);
        expect(await VaultCrypto.instance.unlock(passphrase), isTrue);
      },
    );
  });
}
