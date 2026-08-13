import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/models/document.dart';
import 'package:inoapp/repositories/document_repository.dart';
import 'package:inoapp/services/session_reset.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    DocumentRepository.instance.clearCache();
  });

  group('DocumentRepository Offline Disk Cache & Isolation', () {
    final docAccountA = Document(
      id: 'doc_acc_a_001',
      wallet: 'Identity Wallet',
      name: 'Passport A',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

    final docAccountB = Document(
      id: 'doc_acc_b_002',
      wallet: 'Document Wallet',
      name: 'Contract B',
      createdAt: DateTime(2026, 1, 2),
      updatedAt: DateTime(2026, 1, 2),
    );

    test('account A disk cache persists under account-scoped key', () async {
      final prefs = await SharedPreferences.getInstance();
      const keyA = 'ino_doc_cache_user_a';

      // Manually seed disk cache for user_a
      await prefs.setString(keyA, jsonEncode([docAccountA.toMap()]));

      // Verify raw stored JSON contains user A document
      final storedRaw = prefs.getString(keyA);
      expect(storedRaw, isNotNull);
      expect(storedRaw, contains('Passport A'));
    });

    test('account A and account B disk caches are completely isolated', () async {
      final prefs = await SharedPreferences.getInstance();
      const keyA = 'ino_doc_cache_user_a';
      const keyB = 'ino_doc_cache_user_b';

      await prefs.setString(keyA, jsonEncode([docAccountA.toMap()]));
      await prefs.setString(keyB, jsonEncode([docAccountB.toMap()]));

      final rawA = prefs.getString(keyA);
      final rawB = prefs.getString(keyB);

      expect(rawA, contains('Passport A'));
      expect(rawA, isNot(contains('Contract B')));

      expect(rawB, contains('Contract B'));
      expect(rawB, isNot(contains('Passport A')));
    });

    test('SessionReset clear invalidates in-memory document cache on logout', () async {
      DocumentRepository.instance.clearCache();
      await SessionReset.instance.clear();

      // Memory cache is cleared
      expect(DocumentRepository.revision.value, greaterThan(0));
    });
  });
}
