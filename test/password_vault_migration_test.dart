import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/core/storage/shared_prefs_cache.dart';
import 'package:inoapp/models/password_models.dart';
import 'package:inoapp/services/password_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    SharedPrefsCache.resetForTesting();
    PasswordStore.instance.reset();
  });

  group('PRIORITY 2.E: Password Vault Migration & Account Switch Isolation', () {
    const userA = 'user_account_a_uuid';
    const userB = 'user_account_b_uuid';

    test('Migrates legacy SharedPreferences cache to FlutterSecureStorage with count validation', () async {
      final prefs = await SharedPrefsCache.instance.prefsAsync;
      final key = 'ino_passwords_$userA';

      // 1. Seed legacy SharedPreferences entries
      final legacyEntries = [
        PasswordEntry(
          id: 'p1',
          nickname: 'Google Account',
          password: 'SecretPassword123!',
          consent: true,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        PasswordEntry(
          id: 'p2',
          nickname: 'GitHub',
          password: 'TokenPassword456!',
          consent: true,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ];

      await prefs.setStringList(
        key,
        legacyEntries.map((e) => jsonEncode(e.toJson())).toList(),
      );

      // Verify legacy cache exists and secure storage is empty initially
      expect(prefs.getStringList(key)?.length, equals(2));
      final secure = const FlutterSecureStorage();
      expect(await secure.read(key: key), isNull);

      // 2. Run loadFromSecureStorage - should import, validate counts, and then remove legacy cache
      await PasswordStore.instance.loadFromSecureStorage(userA);

      // Verify items loaded into memory
      expect(PasswordStore.instance.items.length, equals(2));
      expect(PasswordStore.instance.items[0].nickname, equals('Google Account'));
      expect(PasswordStore.instance.items[1].nickname, equals('GitHub'));

      // Verify secure storage now has the records
      final secureRaw = await secure.read(key: key);
      expect(secureRaw, isNotNull);
      final secureList = jsonDecode(secureRaw!) as List<dynamic>;
      expect(secureList.length, equals(2));

      // Verify legacy SharedPreferences cache was purged ONLY after verified import
      expect(prefs.getStringList(key), isNull);
    });

    test('Account switching A -> B -> A preserves both vaults in secure storage without loss', () async {
      final secure = const FlutterSecureStorage();
      final keyA = 'ino_passwords_$userA';
      final keyB = 'ino_passwords_$userB';

      // User A loads and saves credentials
      await PasswordStore.instance.loadFromSecureStorage(userA);
      final entryA = PasswordEntry(
        id: 'vault_a_item',
        nickname: 'User A Secret',
        password: 'PassA_12345',
        consent: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      PasswordStore.instance.items.add(entryA);
      await PasswordStore.instance.persist();

      // Verify User A stored
      expect(await secure.read(key: keyA), isNotNull);

      // Switch to User B: clear in-memory state
      await PasswordStore.instance.clear();
      expect(PasswordStore.instance.items.isEmpty, isTrue);

      // User B loads and saves credentials
      await PasswordStore.instance.loadFromSecureStorage(userB);
      final entryB = PasswordEntry(
        id: 'vault_b_item',
        nickname: 'User B Secret',
        password: 'PassB_67890',
        consent: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      PasswordStore.instance.items.add(entryB);
      await PasswordStore.instance.persist();

      // Verify User B stored
      expect(await secure.read(key: keyB), isNotNull);

      // Verify User A is STILL in secure storage! (No deletion during switch)
      expect(await secure.read(key: keyA), isNotNull);

      // Switch back to User A: clear in-memory and reload User A
      await PasswordStore.instance.clear();
      await PasswordStore.instance.loadFromSecureStorage(userA);

      expect(PasswordStore.instance.items.length, equals(1));
      expect(PasswordStore.instance.items[0].id, equals('vault_a_item'));
      expect(PasswordStore.instance.items[0].nickname, equals('User A Secret'));

      // Both vaults preserved intact!
      final rawA = await secure.read(key: keyA);
      final rawB = await secure.read(key: keyB);
      expect(rawA, isNotNull);
      expect(rawB, isNotNull);
      expect((jsonDecode(rawA!) as List).length, equals(1));
      expect((jsonDecode(rawB!) as List).length, equals(1));
    });

    test('purgeSecureStorageForUser deletes only specified user on account deletion', () async {
      final secure = const FlutterSecureStorage();
      final keyA = 'ino_passwords_$userA';
      final keyB = 'ino_passwords_$userB';

      await secure.write(key: keyA, value: jsonEncode([{'id': 'a1'}]));
      await secure.write(key: keyB, value: jsonEncode([{'id': 'b1'}]));

      // Purge only User A
      await PasswordStore.instance.purgeSecureStorageForUser(userA);

      expect(await secure.read(key: keyA), isNull);
      expect(await secure.read(key: keyB), isNotNull); // User B untouched
    });
  });
}
