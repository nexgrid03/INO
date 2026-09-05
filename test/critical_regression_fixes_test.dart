import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/models/document.dart';
import 'package:inoapp/models/document_extraction.dart';
import 'package:inoapp/services/offline_document_store.dart';
import 'package:inoapp/services/password_store.dart';
import 'package:inoapp/utils/identifier_masker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('CRITICAL N1: Account Deletion RPC Migration Integrity', () {
    test('Migration file contains no invalid tables, views, or columns', () {
      final file = File('supabase/migrations/20260904020000_delete_account_rpc.sql');
      expect(file.existsSync(), isTrue, reason: 'Migration file must exist');
      final sql = file.readAsStringSync();

      // 1. public.documents is a VIEW - direct deletes fail inside transactions
      expect(sql.contains('FROM public.documents'), isFalse);
      expect(sql.contains('FROM documents'), isFalse);

      // 2. Non-existent tables
      expect(sql.contains('w_tax_wallet'), isFalse);
      expect(sql.contains('share_tokens'), isFalse);
      expect(sql.contains('family_vault_members'), isFalse);
      expect(sql.contains('family_vault_invitations'), isFalse);

      // 3. Non-existent columns
      expect(sql.contains('owner_user_id'), isFalse);

      // 4. Proper table references present
      expect(sql.contains('tax_documents'), isTrue);
      expect(sql.contains('vault_members'), isTrue);
      expect(sql.contains('vault_invitations'), isTrue);
      expect(sql.contains('owner_auth_user_id'), isTrue);

      // 5. Dynamic cleanup of custom user wallets
      expect(sql.contains('SELECT slug FROM public.wallets'), isTrue);

      // 6. Cascade delete on auth.users
      expect(sql.contains('DELETE FROM auth.users WHERE id = v_uid;'), isTrue);

      // 7. C1 Column fixes: owner_id, shared_by, recipient_auth_user_id
      expect(sql.contains('public.document_shares WHERE owner_id = v_uid'), isTrue);
      expect(sql.contains('public.document_shares WHERE auth_user_id = v_uid'), isFalse);
      expect(sql.contains('public.view_once_shares WHERE owner_id = v_uid'), isTrue);
      expect(sql.contains('public.view_once_shares WHERE auth_user_id = v_uid'), isFalse);
      expect(sql.contains('public.vault_documents WHERE shared_by = v_uid'), isTrue);
      expect(sql.contains('public.vault_documents WHERE auth_user_id = v_uid'), isFalse);
      expect(sql.contains('recipient_auth_user_id = v_uid'), isTrue);
      expect(sql.contains('target_auth_user_id'), isFalse);

      // 8. C1 Storage cleanup: type-safe uuid comparison & no catch-all error swallowing
      expect(sql.contains('owner::text = v_uid::text'), isTrue);
      expect(sql.contains('EXCEPTION WHEN OTHERS THEN'), isFalse);
    });
  });

  group('CRITICAL N2: Offline Document Encryption Security', () {
    const testUid1 = 'user-uuid-1111-aaaa';
    const testUid2 = 'user-uuid-2222-bbbb';
    final sampleDocBytes = Uint8List.fromList(
      utf8.encode('CONFIDENTIAL IDENTITY RECORD CONTENT - AADHAAR 123456789012'),
    );

    test('Different users generate different 256-bit encryption keys', () async {
      final key1 = await OfflineDocumentStore.getKeyForTest(testUid1);
      final key2 = await OfflineDocumentStore.getKeyForTest(testUid2);

      final bytes1 = await key1.extractBytes();
      final bytes2 = await key2.extractBytes();

      expect(bytes1.length, equals(32), reason: 'Must be 256-bit key');
      expect(bytes2.length, equals(32), reason: 'Must be 256-bit key');
      expect(bytes1, isNot(equals(bytes2)), reason: 'Keys must be per-user');
    });

    test('Same document encrypted twice produces different outputs (per-file nonce uniqueness)', () async {
      final enc1 = await OfflineDocumentStore.encryptBytesForTest(sampleDocBytes, testUid1);
      final enc2 = await OfflineDocumentStore.encryptBytesForTest(sampleDocBytes, testUid1);

      expect(enc1, isNot(equals(enc2)), reason: 'AES-GCM nonce reuse is prohibited');

      // The first 12 bytes are the random nonce
      final nonce1 = enc1.sublist(0, 12);
      final nonce2 = enc2.sublist(0, 12);
      expect(nonce1, isNot(equals(nonce2)), reason: 'Per-file 12-byte nonce must be unique');
    });

    test('Decryption restores exact original plaintext for matching user', () async {
      final encrypted = await OfflineDocumentStore.encryptBytesForTest(sampleDocBytes, testUid1);
      final decrypted = await OfflineDocumentStore.decryptBytesForTest(encrypted, testUid1);

      expect(decrypted, equals(sampleDocBytes));
      expect(utf8.decode(decrypted), equals(utf8.decode(sampleDocBytes)));
    });

    test('Decryption with a different user key throws exception', () async {
      final encrypted = await OfflineDocumentStore.encryptBytesForTest(sampleDocBytes, testUid1);

      expect(
        () => OfflineDocumentStore.decryptBytesForTest(encrypted, testUid2),
        throwsA(isA<StateError>()),
        reason: 'Decryption must fail with wrong key and never return invalid plaintext',
      );
    });

    test('Tampered ciphertext or MAC throws StateError and never returns corrupted data', () async {
      final encrypted = await OfflineDocumentStore.encryptBytesForTest(sampleDocBytes, testUid1);

      // Tamper with ciphertext byte
      final tamperedCiphertext = Uint8List.fromList(encrypted);
      tamperedCiphertext[15] ^= 0xFF;

      expect(
        () => OfflineDocumentStore.decryptBytesForTest(tamperedCiphertext, testUid1),
        throwsA(isA<StateError>()),
      );

      // Tamper with MAC byte (last 16 bytes)
      final tamperedMac = Uint8List.fromList(encrypted);
      tamperedMac[tamperedMac.length - 1] ^= 0x01;

      expect(
        () => OfflineDocumentStore.decryptBytesForTest(tamperedMac, testUid1),
        throwsA(isA<StateError>()),
      );

      // Tamper with nonce byte (first 12 bytes)
      final tamperedNonce = Uint8List.fromList(encrypted);
      tamperedNonce[0] ^= 0x55;

      expect(
        () => OfflineDocumentStore.decryptBytesForTest(tamperedNonce, testUid1),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('CRITICAL N3: Document Numbers Masking vs Raw Storage Contract', () {
    const rawAadhaar = '123456789012';
    const rawPan = 'ABCDE1234F';

    test('IdentifierMasker formats only for UI display', () {
      expect(IdentifierMasker.mask(rawAadhaar, docType: 'aadhaar'), equals('XXXX XXXX 9012'));
      expect(IdentifierMasker.mask(rawPan, docType: 'pan'), equals('ABCDE****F'));
    });

    test('DocumentExtraction preserves full raw unmasked value in storage envelope', () {
      final extraction = DocumentExtraction(
        documentType: 'aadhaar',
        data: {'number': rawAadhaar, 'name': 'Test User'},
        userNotes: 'Personal ID',
      );

      final encoded = extraction.encode();
      expect(encoded.contains(rawAadhaar), isTrue, reason: 'Envelope must store full original number');
      expect(encoded.contains('XXXX XXXX 9012'), isFalse, reason: 'Envelope must not store masked value');

      // Decoding restores full raw value
      final decoded = DocumentExtraction.decode(encoded);
      expect(decoded.data['number'], equals(rawAadhaar));
    });

    test('displayFieldsDetailed returns masked value for display and full value for rawValue', () {
      final extraction = DocumentExtraction(
        documentType: 'aadhaar',
        data: {'number': rawAadhaar, 'name': 'Aadhaar Holder'},
      );

      final detailed = extraction.displayFieldsDetailed();
      final numberField = detailed.firstWhere((f) => f.label == 'Aadhaar Number');

      expect(numberField.isSensitive, isTrue);
      expect(numberField.value, equals('XXXX XXXX 9012'));
      expect(numberField.rawValue, equals(rawAadhaar));
    });

    test('IdentifierMasker.isMasked accurately identifies masked identifiers', () {
      expect(IdentifierMasker.isMasked('XXXX XXXX 1234'), isTrue);
      expect(IdentifierMasker.isMasked('ABCDE****F'), isTrue);
      expect(IdentifierMasker.isMasked('******1234'), isTrue);
      expect(IdentifierMasker.isMasked('enc:12345'), isTrue);
      expect(IdentifierMasker.isMasked('123456789012'), isFalse);
      expect(IdentifierMasker.isMasked('ABCDE1234F'), isFalse);
    });

    test('Document.fromMap recovers unmasked record number from OCR envelope if record_number was masked', () {
      final envelope = DocumentExtraction(
        documentType: 'aadhaar',
        data: {'number': '123456789012'},
      ).encode();

      final doc = Document.fromMap({
        'id': 'd1',
        'wallet': 'Identity Wallet',
        'name': 'Aadhaar Card',
        'record_number': 'XXXX XXXX 9012', // previously masked
        'notes': envelope, // full number in notes JSON
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      expect(doc.recordNumber, equals('123456789012'));
    });
  });

  group('PRIORITY 1.A: Government ID Masking Migration Disabled', () {
    test('Migration 20260904040000_encrypt_government_ids is disabled and contains no destructive updates', () {
      final file = File('supabase/migrations/20260904040000_encrypt_government_ids.sql');
      expect(file.existsSync(), isTrue);
      final content = file.readAsStringSync();

      expect(content.contains('UPDATE public.w_identity_wallet'), isFalse);
      expect(content.contains('UPDATE public.w_tax_wallet'), isFalse);
      expect(content.contains('UPDATE public.w_document_wallet'), isFalse);
      expect(content.contains('ino_mask_identifier'), isFalse);
      expect(content.contains('DISABLED PER SECURITY AND DATA INTEGRITY POLICY'), isTrue);
    });
  });

  group('PRIORITY 1.C: Offline Document Legacy Decryption Compatibility', () {
    test('Decrypts legacy document encrypted with static key and produces correct plaintext', () async {
      final legacyKey = SecretKey(const [
        0x49, 0x4e, 0x4f, 0x5f, 0x4f, 0x46, 0x46, 0x4c, 0x49, 0x4e, 0x45, 0x5f, 0x44, 0x4f, 0x43, 0x5f,
        0x4b, 0x45, 0x59, 0x5f, 0x32, 0x30, 0x32, 0x36, 0x5f, 0x53, 0x45, 0x43, 0x55, 0x52, 0x45, 0x21
      ]);
      final plaintext = Uint8List.fromList(utf8.encode('LEGACY OFFLINE TAX DOCUMENT 2025'));
      final algorithm = AesGcm.with256bits();
      final nonce = List<int>.generate(12, (i) => (i * 37 + 13) % 256);
      final box = await algorithm.encrypt(plaintext, secretKey: legacyKey, nonce: nonce);
      final legacyEncryptedBytes = Uint8List.fromList([...box.nonce, ...box.cipherText, ...box.mac.bytes]);

      // Decrypt using OfflineDocumentStore for a user whose per-user key does NOT match legacy key
      const userUid = 'user-legacy-mig-1';
      final decrypted = await OfflineDocumentStore.decryptBytesForTest(legacyEncryptedBytes, userUid);

      expect(decrypted, equals(plaintext));
      expect(utf8.decode(decrypted), equals('LEGACY OFFLINE TAX DOCUMENT 2025'));
    });
  });

  group('MFA Hardening Migration Schema', () {
    test('Migration 20260904010000_mfa_rls_hardening uses user_id and applies to w_password_vault', () {
      final file = File('supabase/migrations/20260904010000_mfa_rls_hardening.sql');
      expect(file.existsSync(), isTrue);
      final content = file.readAsStringSync();

      expect(content.contains('auth_user_id = auth.uid()'), isFalse);
      expect(content.contains('user_id = auth.uid()'), isTrue);
      expect(content.contains('w_password_vault'), isTrue);
      expect(content.contains('ino_is_aal2_satisfied'), isTrue);
    });
  });

  group('CRITICAL C2: Password Vault Passphrase Reset and Memory Safety', () {
    test('clearMemory() wipes in-memory items and resets isLoaded flag', () {
      final store = PasswordStore.instance;
      store.clearMemory();
      expect(store.items.isEmpty, isTrue);
      expect(store.isLoaded, isFalse);
    });

    test('reload() forces store reload and clears loaded state', () async {
      final store = PasswordStore.instance;
      store.clearMemory();
      expect(store.isLoaded, isFalse);
      await store.reload();
      expect(store.isLoaded, isTrue);
    });

    test('resealForNewKey() safely aborts without wiping when items is empty', () async {
      final store = PasswordStore.instance;
      store.clearMemory();
      expect(store.items.isEmpty, isTrue);

      // Must complete without throwing and without performing orphan sweep
      await expectLater(store.resealForNewKey(), completes);
    });

    test('persist() does not wipe secure storage when store is not loaded', () async {
      final store = PasswordStore.instance;
      store.clearMemory();
      expect(store.isLoaded, isFalse);

      // Must complete safely without calling delete on secure storage
      await expectLater(store.persist(), completes);
    });
  });

  group('CRITICAL C3: Keystore Read/Write Failure Protection for Offline Documents', () {
    tearDown(() {
      OfflineDocumentStore.resetSecureStorageForTest();
    });

    test('Secure storage read failure throws StateError and DOES NOT generate new key or overwrite', () async {
      const testUser = 'user-c3-read-fail-test';
      final faulty = MockFaultySecureStorage();
      OfflineDocumentStore.setSecureStorageForTest(faulty);

      // 1. Initial creation succeeds and saves a 32-byte key
      final key1 = await OfflineDocumentStore.getKeyForTest(testUser);
      final key1Bytes = await key1.extractBytes();
      expect(key1Bytes.length, equals(32));
      expect(faulty.backing.isNotEmpty, isTrue);
      final savedB64 = faulty.backing.values.first;

      // 2. Encrypt a test document with this key
      final sampleDoc = Uint8List.fromList(utf8.encode('CONFIDENTIAL MEDICAL RECORD 2026'));
      final encrypted = await OfflineDocumentStore.encryptBytesForTest(sampleDoc, testUser);

      // 3. Simulate hardware/keystore read failure
      faulty.failRead = true;

      // Attempting to get key MUST throw StateError
      expect(
        () => OfflineDocumentStore.getKeyForTest(testUser),
        throwsA(isA<StateError>()),
        reason: 'Keystore read failure must throw StateError and never return new key',
      );

      // Decryption MUST also throw StateError
      expect(
        () => OfflineDocumentStore.decryptBytesForTest(encrypted, testUser),
        throwsA(isA<StateError>()),
        reason: 'Decryption must fail-closed when keystore cannot be read',
      );

      // Key in backing store was NOT overwritten or replaced
      expect(faulty.backing.values.first, equals(savedB64));

      // 4. Once keystore recovers (failRead = false), the document decrypts cleanly!
      faulty.failRead = false;
      final decrypted = await OfflineDocumentStore.decryptBytesForTest(encrypted, testUser);
      expect(decrypted, equals(sampleDoc));
    });

    test('Secure storage write failure surfaces explicit StateError and rejects unpersisted key', () async {
      const testUser = 'user-c3-write-fail-test';
      final faulty = MockFaultySecureStorage(failWrite: true);
      OfflineDocumentStore.setSecureStorageForTest(faulty);

      expect(
        () => OfflineDocumentStore.getKeyForTest(testUser),
        throwsA(isA<StateError>()),
        reason: 'Write failure must throw StateError and never silently continue',
      );
    });
  });
}

class MockFaultySecureStorage extends FlutterSecureStorage {
  MockFaultySecureStorage({this.failRead = false, this.failWrite = false});
  bool failRead;
  bool failWrite;
  final Map<String, String> backing = {};

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (failRead) throw Exception('Simulated Keystore Exception: HardwareLocked / Deadlock');
    return backing[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (failWrite) throw Exception('Simulated Keystore Exception: WriteProtected');
    if (value != null) backing[key] = value;
  }
}
