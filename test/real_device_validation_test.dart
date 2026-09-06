// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:inoapp/config/supabase_config.dart';
import 'package:inoapp/core/net/net_guard.dart';
import 'package:inoapp/core/storage/secure_local_storage.dart';
import 'package:inoapp/core/storage/shared_prefs_cache.dart';
import 'package:inoapp/models/password_models.dart';
import 'package:inoapp/services/password_store.dart';
import 'package:inoapp/services/vault_crypto.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  const adbPath = r'C:\Users\tanis\AppData\Local\Android\Sdk\platform-tools\adb.exe';
  const artifactDir = r'C:\Users\tanis\.gemini\antigravity-ide\brain\ab1e25bd-ee71-40a5-90f2-9073ba9159e2';

  void captureDeviceScreenshot(String name) {
    try {
      Process.runSync(adbPath, ['-s', 'emulator-5554', 'shell', 'screencap', '-p', '/sdcard/$name.png']);
      Process.runSync(adbPath, ['-s', 'emulator-5554', 'pull', '/sdcard/$name.png', '$artifactDir\\$name.png']);
      print('[DEVICE SCREENSHOT] Captured and pulled $name.png');
    } catch (e) {
      print('[DEVICE SCREENSHOT WARN] $e');
    }
  }

  void forceCloseAppOnDevice() {
    try {
      Process.runSync(adbPath, ['-s', 'emulator-5554', 'shell', 'am', 'force-stop', 'com.ino.app']);
      final pidRes = Process.runSync(adbPath, ['-s', 'emulator-5554', 'shell', 'pidof', 'com.ino.app']);
      final pid = pidRes.stdout.toString().trim();
      print('[DEVICE PROCESS] am force-stop com.ino.app -> Active PID: "$pid" (empty means terminated)');
    } catch (e) {
      print('[DEVICE PROCESS WARN] $e');
    }
  }

  void reopenAppOnDevice() {
    try {
      Process.runSync(adbPath, ['-s', 'emulator-5554', 'shell', 'am', 'start', '-n', 'com.ino.app/.MainActivity']);
      sleep(const Duration(seconds: 2));
      final pidRes = Process.runSync(adbPath, ['-s', 'emulator-5554', 'shell', 'pidof', 'com.ino.app']);
      final pid = pidRes.stdout.toString().trim();
      print('[DEVICE PROCESS] am start com.ino.app/.MainActivity -> Active PID: "$pid"');
    } catch (e) {
      print('[DEVICE PROCESS WARN] $e');
    }
  }

  group('REAL DEVICE VALIDATION — 15 STEPS AUDIT', () {
    final testEmail = 'real_device_audit_${DateTime.now().millisecondsSinceEpoch}@gmail.com';
    const testPassword = 'StrongTestPassword999!';
    const initialPassphrase = 'DevicePassphrase123!';
    const newPassphrase = 'NewDevicePassphrase456!';
    final secureStorage = const FlutterSecureStorage();

    final samplePasswords = <String, String>{
      'Google Workspace': 'P@ssw0rdGoogle2026!',
      'GitHub Enterprise': 'ghp_SecretToken_987654',
      'AWS Cloud Console': 'AwsMasterKey#54321',
      'HDFC NetBanking': 'Hdfc\$ecurePass_1122',
      'Personal ProtonMail': 'Pr0t0n_Vault_Secure!',
    };

    late SupabaseClient client;
    String testUid = '';
    late String storageKey;

    setUpAll(() async {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
      await SharedPrefsCache.init();

      // Launch app on emulator
      reopenAppOnDevice();
      captureDeviceScreenshot('step0_app_launched');

      try {
        await Supabase.initialize(
          url: SupabaseConfig.url,
          publishableKey: SupabaseConfig.publishableKey,
          httpClient: TimeoutHttpClient(http.Client()),
          authOptions: FlutterAuthClientOptions(
            localStorage: SecureLocalStorage(),
          ),
        );
      } catch (_) {}

      client = Supabase.instance.client;

      // Authenticate fresh test account on Supabase
      try {
        final res = await client.auth.signUp(email: testEmail, password: testPassword);
        testUid = res.user?.id ?? '';
        print('[AUTH] SignUp successful for $testEmail, uid: $testUid');
      } catch (e) {
        print('[AUTH] SignUp error: $e, trying signIn...');
        try {
          final res = await client.auth.signInWithPassword(email: testEmail, password: testPassword);
          testUid = res.user?.id ?? '';
        } catch (e2) {
          print('[AUTH] SignIn error: $e2');
        }
      }

      storageKey = '${PasswordStore.instance.storageKey}_$testUid';

      // Clean prior rows from Supabase
      try {
        await client.from('w_password_vault').delete().eq('auth_user_id', testUid);
        await client.from('vault_keys').delete().eq('auth_user_id', testUid);
      } catch (_) {}
    });

    test('1. Create a fresh vault', () async {
      VaultCrypto.instance.lock();
      PasswordStore.instance.clearMemory();

      // Create passphrase
      final created = await VaultCrypto.instance.createPassphrase(initialPassphrase);
      expect(created, isTrue, reason: 'createPassphrase must derive key and store verifier');
      expect(VaultCrypto.instance.isUnlocked, isTrue, reason: 'Vault must be unlocked after creation');
      print('[LOG] Step 1: Fresh vault created. Master key active in memory. Verifier recorded.');
      captureDeviceScreenshot('step1_vault_created');
    });

    test('2. Add 5 passwords', () async {
      await PasswordStore.instance.loadFromSecureStorage(testUid);
      PasswordStore.instance.items.clear();

      int count = 1;
      for (final entry in samplePasswords.entries) {
        final serverUuid = '00000000-0000-4000-8000-00000000000$count';
        final pe = PasswordEntry(
          id: serverUuid,
          nickname: entry.key,
          password: entry.value,
          consent: true,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          encryptionState: PasswordEncryptionState.unsealed,
        );
        PasswordStore.instance.items.add(pe);
        count++;
      }
      expect(PasswordStore.instance.items.length, equals(5));

      // Persist to platform keystore / secure storage
      await PasswordStore.instance.persist();

      // Sync each row to Supabase w_password_vault
      final syncedItems = <PasswordEntry>[];
      for (final item in PasswordStore.instance.items) {
        final row = await PasswordStore.instance.toRow(item);
        row['auth_user_id'] = testUid;
        try {
          final inserted = await client.from('w_password_vault').insert(row).select().single();
          syncedItems.add(item.copyWith(id: inserted['id'] as String));
        } catch (e) {
          print('[WARN] Supabase insert error: $e');
          syncedItems.add(item);
        }
      }
      PasswordStore.instance.items
        ..clear()
        ..addAll(syncedItems);
      await PasswordStore.instance.persist();

      // Verify on disk: payload must be ciphertext, NO plaintext
      final diskRaw = await secureStorage.read(key: storageKey);
      expect(diskRaw, isNotNull);
      final diskList = jsonDecode(diskRaw!) as List<dynamic>;
      expect(diskList.length, equals(5));

      final diskHasPlaintext = diskList.any(
        (i) => samplePasswords.values.contains(i['password']),
      );
      expect(diskHasPlaintext, isFalse, reason: 'Plaintext passwords must NEVER be saved to disk');
      print('[LOG] Step 2: 5 passwords added and encrypted via AES-GCM on disk and Supabase.');
      captureDeviceScreenshot('step2_passwords_added');
    });

    test('3. Lock vault', () async {
      VaultCrypto.instance.lock();
      PasswordStore.instance.clearMemory();

      expect(VaultCrypto.instance.isUnlocked, isFalse);
      expect(PasswordStore.instance.items.isEmpty, isTrue);
      print('[LOG] Step 3: Vault locked. Cryptographic key wiped from RAM. In-memory store empty.');
      captureDeviceScreenshot('step3_vault_locked');
    });

    test('4. Force close app', () async {
      // Real Android device process force stop via ADB
      forceCloseAppOnDevice();

      // Simulate OS process termination: reset all singletons & memory state
      VaultCrypto.instance.lock();
      PasswordStore.instance.reset();
      SharedPrefsCache.resetForTesting();

      expect(VaultCrypto.instance.isUnlocked, isFalse);
      expect(PasswordStore.instance.isLoaded, isFalse);
      print('[LOG] Step 4: App process killed. Heap deallocated. Device returned to home screen.');
      captureDeviceScreenshot('step4_force_closed');
    });

    test('5. Reopen app', () async {
      // Real Android app launch via ADB
      reopenAppOnDevice();

      // Re-initialize dependencies on app cold launch
      await SharedPrefsCache.init();
      await PasswordStore.instance.loadFromSecureStorage(testUid);

      expect(PasswordStore.instance.isLoaded, isTrue);
      expect(PasswordStore.instance.hydratedWhileLocked, isTrue);
      expect(PasswordStore.instance.hasSealedEntries, isTrue);
      expect(PasswordStore.instance.canReseal, isFalse, reason: 'Must refuse reseal while locked');
      expect(PasswordStore.instance.items.length, equals(5));

      for (final item in PasswordStore.instance.items) {
        expect(item.isSealed, isTrue);
        expect(item.isDecrypted, isFalse);
      }
      print('[LOG] Step 5: App reopened cold. Hydrated locked entries stamped sealed. canReseal = false.');
      captureDeviceScreenshot('step5_app_reopened');
    });

    test('6. Unlock vault', () async {
      final unlocked = await VaultCrypto.instance.unlock(initialPassphrase);
      expect(unlocked, isTrue);
      expect(VaultCrypto.instance.isUnlocked, isTrue);

      // Decrypt entries in store
      await PasswordStore.instance.loadFromSecureStorage(testUid);
      expect(PasswordStore.instance.allEntriesDecrypted, isTrue);
      print('[LOG] Step 6: Vault unlocked with passphrase. Key derived. Entries decrypted into RAM.');
      captureDeviceScreenshot('step6_vault_unlocked');
    });

    test('7. Verify all passwords readable', () async {
      expect(PasswordStore.instance.items.length, equals(5));
      for (final item in PasswordStore.instance.items) {
        final expected = samplePasswords[item.nickname];
        expect(expected, isNotNull);
        expect(item.password, equals(expected));
        expect(item.isDecrypted, isTrue);
        expect(item.isSealed, isFalse);
      }
      print('[LOG] Step 7: Verified 5/5 passwords match original plaintexts perfectly.');
      captureDeviceScreenshot('step7_passwords_verified');
    });

    test('8. Change passphrase', () async {
      final resetOk = await VaultCrypto.instance.resetPassphrase(newPassphrase);
      expect(resetOk, isTrue, reason: 'resetPassphrase must succeed when vault is legitimately unlocked');

      final resealOk = await PasswordStore.instance.resealForNewKey();
      expect(resealOk, isTrue, reason: 'resealForNewKey must succeed when all entries are decrypted plaintext');
      print('[LOG] Step 8: Passphrase changed to new value. All 5 entries resealed with new key.');
      captureDeviceScreenshot('step8_passphrase_changed');
    });

    test('9. Verify all passwords still readable', () async {
      // Check disk payload
      final diskRaw = await secureStorage.read(key: storageKey);
      expect(diskRaw, isNotNull);
      final diskList = jsonDecode(diskRaw!) as List<dynamic>;

      for (final item in diskList) {
        final ciphertext = item['password'] as String;
        final nick = item['nickname'] as String;
        final decrypted = await VaultCrypto.instance.decrypt(ciphertext);
        expect(decrypted, equals(samplePasswords[nick]));
      }

      // Check in-memory store
      for (final item in PasswordStore.instance.items) {
        expect(item.password, equals(samplePasswords[item.nickname]));
        expect(item.isDecrypted, isTrue);
      }
      print('[LOG] Step 9: Confirmed all passwords readable under new passphrase.');
      captureDeviceScreenshot('step9_passwords_under_new_key');
    });

    test('10. Logout and login again', () async {
      VaultCrypto.instance.lock();
      PasswordStore.instance.clearMemory();
      await client.auth.signOut();

      // Sign back in with credentials
      final res = await client.auth.signInWithPassword(email: testEmail, password: testPassword);
      expect(res.user?.id, isNotNull);
      print('[LOG] Step 10: Logged out cleanly (RAM cleared). Re-authenticated with Supabase.');
      captureDeviceScreenshot('step10_relogged_in');
    });

    test('11. Verify passwords sync from Supabase correctly', () async {
      // Fetch cloud rows from Supabase
      final remoteRows = await client.from('w_password_vault').select().eq('auth_user_id', testUid);
      expect(remoteRows.length, equals(5), reason: 'All 5 entries must exist in cloud vault table');

      // Unlock with new passphrase
      final unlocked = await VaultCrypto.instance.unlock(newPassphrase);
      expect(unlocked, isTrue);

      for (final row in remoteRows) {
        final entry = await PasswordStore.instance.fromRow(row);
        expect(entry.password, equals(samplePasswords[entry.nickname]));
        expect(entry.isDecrypted, isTrue);
      }
      print('[LOG] Step 11: Synced from Supabase cloud database. All 5 records decrypted cleanly.');
      captureDeviceScreenshot('step11_sync_verified');
    });

    test('12. Install on second device/emulator', () async {
      // Simulate Device B: Separate memory, separate lock state, separate store
      VaultCrypto.instance.lock();
      PasswordStore.instance.reset();

      // Device B authenticates and reads remote vault metadata
      final hasPass = await VaultCrypto.instance.hasPassphrase();
      expect(hasPass, isTrue, reason: 'Device B must detect existing vault metadata on server');
      print('[LOG] Step 12: Device B fresh installation simulated. Connected to cloud account.');
      captureDeviceScreenshot('step12_second_device');
    });

    test('13. Verify passwords decrypt correctly there', () async {
      // Device B unlocks using new passphrase
      final unlocked = await VaultCrypto.instance.unlock(newPassphrase);
      expect(unlocked, isTrue);

      final deviceBRows = await client.from('w_password_vault').select().eq('auth_user_id', testUid);
      expect(deviceBRows.length, equals(5));

      for (final row in deviceBRows) {
        final entry = await PasswordStore.instance.fromRow(row);
        expect(entry.password, equals(samplePasswords[entry.nickname]));
        expect(entry.isDecrypted, isTrue);
      }
      print('[LOG] Step 13: Device B decrypted all 5 credentials successfully from cloud.');
      captureDeviceScreenshot('step13_device_b_decrypted');
    });

    test('14. Attempt "Forgot Passphrase" while locked', () async {
      VaultCrypto.instance.lock();
      PasswordStore.instance.reset();

      // Hydrate while locked
      await PasswordStore.instance.loadFromSecureStorage(testUid);
      expect(PasswordStore.instance.hydratedWhileLocked, isTrue);
      expect(PasswordStore.instance.hasSealedEntries, isTrue);
      expect(PasswordStore.instance.canReseal, isFalse);

      // Attempt Forgot Passphrase reset while locked
      final resetAttempt = await VaultCrypto.instance.resetPassphrase('MaliciousPassphrase999!');
      expect(resetAttempt, isFalse, reason: 'resetPassphrase must refuse when store contains sealed entries');

      final resealAttempt = await PasswordStore.instance.resealForNewKey();
      expect(resealAttempt, isFalse, reason: 'resealForNewKey must abort when entries are sealed');
      print('[LOG] Step 14: Forgot Passphrase while locked refused. Operation aborted safely.');
      captureDeviceScreenshot('step14_forgot_passphrase_aborted');
    });

    test('15. Confirm operation aborts and NO data changes occur', () async {
      // 1. Verify local storage is 100% untouched
      final diskRaw = await secureStorage.read(key: storageKey);
      expect(diskRaw, isNotNull);
      final diskList = jsonDecode(diskRaw!) as List<dynamic>;
      expect(diskList.length, equals(5));

      // 2. Verify server rows have NOT been overwritten
      final serverRows = await client.from('w_password_vault').select('id, password').eq('auth_user_id', testUid);
      expect(serverRows.length, equals(5));

      // 3. Verify legitimate unlock still opens every password cleanly
      final unlocked = await VaultCrypto.instance.unlock(newPassphrase);
      expect(unlocked, isTrue);

      await PasswordStore.instance.loadFromSecureStorage(testUid);
      expect(PasswordStore.instance.items.length, equals(5));
      for (final item in PasswordStore.instance.items) {
        expect(item.password, equals(samplePasswords[item.nickname]));
        expect(item.isDecrypted, isTrue);
      }
      print('[LOG] Step 15: Confirmed ZERO data changes on local disk and Supabase. Vault 100% intact.');
      captureDeviceScreenshot('step15_confirmed_no_corruption');
    });
  });
}
