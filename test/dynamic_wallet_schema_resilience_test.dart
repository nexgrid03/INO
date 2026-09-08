import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/models/document.dart';
import 'package:inoapp/repositories/wallet_tables.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Dynamic Wallet Schema Resilience Test Suite', () {
    setUp(() {
      WalletTables.invalidate();
    });

    test('TEST 1: Core columns are defined and guaranteed for every wallet table', () {
      expect(WalletTables.coreColumns.length, equals(13));
      expect(WalletTables.coreColumns.contains('id'), isTrue);
      expect(WalletTables.coreColumns.contains('auth_user_id'), isTrue);
      expect(WalletTables.coreColumns.contains('name'), isTrue);
      expect(WalletTables.coreColumns.contains('category'), isTrue);
      expect(WalletTables.coreColumns.contains('record_number'), isTrue);
      expect(WalletTables.coreColumns.contains('status'), isTrue);
      expect(WalletTables.coreColumns.contains('tags'), isTrue);
      expect(WalletTables.coreColumns.contains('notes'), isTrue);
      expect(WalletTables.coreColumns.contains('is_favorite'), isTrue);
      expect(WalletTables.coreColumns.contains('expires_at'), isTrue);
      expect(WalletTables.coreColumns.contains('file_path'), isTrue);
      expect(WalletTables.coreColumns.contains('created_at'), isTrue);
      expect(WalletTables.coreColumns.contains('updated_at'), isTrue);
      // 'consent' must NOT be in the coreColumns because post-round7 custom tables do not have it
      expect(WalletTables.coreColumns.contains('consent'), isFalse);
    });

    test('TEST 2: Built-in wallets schema preserves all wallet-specific columns', () async {
      // Health Wallet must preserve doctor_name and consent
      final healthCols = await WalletTables.getColumnsForTable('w_health_wallet');
      expect(healthCols.contains('doctor_name'), isTrue);
      expect(healthCols.contains('consent'), isTrue);
      expect(healthCols.contains('name'), isTrue);

      // Identity Wallet must preserve holder_name, id_type, issuing_authority, consent
      final identityCols = await WalletTables.getColumnsForTable('w_identity_wallet');
      expect(identityCols.contains('holder_name'), isTrue);
      expect(identityCols.contains('id_type'), isTrue);
      expect(identityCols.contains('issuing_authority'), isTrue);
      expect(identityCols.contains('consent'), isTrue);

      // Document Wallet must preserve doc_type, issued_by, consent
      final docCols = await WalletTables.getColumnsForTable('w_document_wallet');
      expect(docCols.contains('doc_type'), isTrue);
      expect(docCols.contains('issued_by'), isTrue);
      expect(docCols.contains('consent'), isTrue);
    });

    test('TEST 3: filterPayloadForTable filters out missing "consent" for custom tables', () async {
      final customPayload = <String, dynamic>{
        'auth_user_id': '00000000-0000-0000-0000-000000000001',
        'name': 'Tuition Receipt',
        'category': 'Fee',
        'record_number': 'REC-1234',
        'status': 'active',
        'tags': ['tuition', 'receipt'],
        'notes': 'Paid in full',
        'is_favorite': true,
        'expires_at': '2027-01-01',
        'file_path': 'school/receipt.pdf',
        'consent': true, // Missing from custom table schema!
      };

      // Custom table without consent in schema:
      final filtered = await WalletTables.filterPayloadForTable('w_school', customPayload);

      // All 10 core fields must be preserved
      expect(filtered['auth_user_id'], equals('00000000-0000-0000-0000-000000000001'));
      expect(filtered['name'], equals('Tuition Receipt'));
      expect(filtered['category'], equals('Fee'));
      expect(filtered['record_number'], equals('REC-1234'));
      expect(filtered['status'], equals('active'));
      expect(filtered['tags'], equals(['tuition', 'receipt']));
      expect(filtered['notes'], equals('Paid in full'));
      expect(filtered['is_favorite'], isTrue);
      expect(filtered['expires_at'], equals('2027-01-01'));
      expect(filtered['file_path'], equals('school/receipt.pdf'));

      // 'consent' must be filtered out, preventing PGRST204 exception!
      expect(filtered.containsKey('consent'), isFalse);
    });

    test('TEST 4: Injected unknown fields are safely ignored without crashing', () async {
      final injectedPayload = <String, dynamic>{
        'name': 'Degree Certificate',
        'category': 'Academics',
        'hacked_column': 'malicious_input',
        'random_field_123': 999,
        'doctor_name': 'Dr. House', // doctor_name is not in custom table
      };

      final filtered = await WalletTables.filterPayloadForTable('w_college', injectedPayload);

      expect(filtered['name'], equals('Degree Certificate'));
      expect(filtered['category'], equals('Academics'));
      expect(filtered.containsKey('hacked_column'), isFalse);
      expect(filtered.containsKey('random_field_123'), isFalse);
      expect(filtered.containsKey('doctor_name'), isFalse);
    });

    test('TEST 5: Existing custom wallets that possess consent preserve it', () async {
      // Built-in and existing wallets possessing consent retain it:
      final payloadWithConsent = <String, dynamic>{
        'name': 'Business Contract',
        'category': 'Agreements',
        'consent': true,
      };

      final filtered = await WalletTables.filterPayloadForTable('w_document_wallet', payloadWithConsent);
      expect(filtered['name'], equals('Business Contract'));
      expect(filtered['category'], equals('Agreements'));
      expect(filtered['consent'], isTrue);
    });

    test('TEST 6: Built-in wallets preserve specialized columns (e.g. Health Wallet doctor_name)', () async {
      final healthPayload = <String, dynamic>{
        'auth_user_id': '00000000-0000-0000-0000-000000000001',
        'name': 'Blood Test',
        'category': 'Lab',
        'doctor_name': 'Dr. Sharma',
        'consent': true,
      };

      final filtered = await WalletTables.filterPayloadForTable('w_health_wallet', healthPayload);
      expect(filtered['doctor_name'], equals('Dr. Sharma'));
      expect(filtered['consent'], isTrue);
      expect(filtered['name'], equals('Blood Test'));
    });

    test('TEST 7: Offline sync and disk caching format remains intact', () {
      final doc = Document(
        id: '11111111-1111-1111-1111-111111111111',
        wallet: 'School',
        name: 'Report Card',
        category: 'Grades',
        recordNumber: 'RC-2026',
        status: 'active',
        tags: const ['academics'],
        notes: 'A+',
        isFavorite: false,
        expiresAt: null,
        filePath: 'school/rc.pdf',
        createdAt: DateTime(2026, 9, 8),
        updatedAt: DateTime(2026, 9, 8),
      );

      final map = doc.toMap();
      expect(map['name'], equals('Report Card'));
      expect(map['wallet'], equals('School'));
      expect(map['category'], equals('Grades'));
      expect(map['record_number'], equals('RC-2026'));

      final reconstructed = Document.fromMap(map, wallet: 'School');
      expect(reconstructed.id, equals(doc.id));
      expect(reconstructed.name, equals(doc.name));
      expect(reconstructed.wallet, equals('School'));
    });

    test('TEST 8: Search indexing fields are completely preserved', () {
      final doc = Document(
        id: '22222222-2222-2222-2222-222222222222',
        wallet: 'Business',
        name: 'NDA Agreement',
        category: 'Legal',
        recordNumber: 'NDA-887',
        status: 'active',
        tags: const ['confidential', 'legal'],
        notes: 'Signed with partner',
        isFavorite: true,
        expiresAt: DateTime(2028, 1, 1),
        filePath: 'business/nda.pdf',
        createdAt: DateTime(2026, 9, 8),
        updatedAt: DateTime(2026, 9, 8),
      );

      final searchableList = [
        doc.name,
        doc.category ?? 'Other',
        doc.wallet,
        doc.recordNumber ?? '',
        ...doc.tags,
      ].join(' ').toLowerCase();

      expect(searchableList.contains('nda agreement'), isTrue);
      expect(searchableList.contains('legal'), isTrue);
      expect(searchableList.contains('business'), isTrue);
      expect(searchableList.contains('confidential'), isTrue);
    });

    test('TEST 9: In-memory schema cache is updated and reusable across multiple calls', () async {
      // First call discovers and caches
      final cols1 = await WalletTables.getColumnsForTable('w_certificates');
      expect(cols1.contains('name'), isTrue);

      // Second call should return identical cached set instantly
      final cols2 = await WalletTables.getColumnsForTable('w_certificates');
      expect(identical(cols1, cols2), isTrue);

      // Invalidate should clear
      WalletTables.invalidateColumnsCache('w_certificates');
      final cols3 = await WalletTables.getColumnsForTable('w_certificates');
      expect(cols3.contains('name'), isTrue);
    });

    test('TEST 10: Slug formatting behaves consistently for all wallet names', () {
      expect(WalletTables.slugFor('School'), equals('w_school'));
      expect(WalletTables.slugFor('College'), equals('w_college'));
      expect(WalletTables.slugFor('Business'), equals('w_business'));
      expect(WalletTables.slugFor('Certificates'), equals('w_certificates'));
      expect(WalletTables.slugFor('Personal Documents'), equals('w_personal_documents'));
      expect(WalletTables.slugFor('My Custom Wallet 123!'), equals('w_my_custom_wallet_123'));
    });

    test('TEST 11: Empty payload after filtering returns empty map gracefully without crashing', () async {
      final invalidOnlyPayload = <String, dynamic>{
        'non_existent_col_1': 'val1',
        'ghost_column': 12345,
      };

      final filtered = await WalletTables.filterPayloadForTable('w_school', invalidOnlyPayload);
      expect(filtered.isEmpty, isTrue);
    });

    test('TEST 12: Built-in tables existence check returns true instantly via pre-seeded cache', () async {
      final tables = [
        'w_identity_wallet',
        'w_document_wallet',
        'w_health_wallet',
        'w_property_wallet',
        'w_insurance_wallet',
        'w_investment_wallet',
        'w_banking_wallet',
        'w_cards_wallet',
        'w_password_vault',
        'w_ino_share_cache',
      ];

      for (final table in tables) {
        final exists = await WalletTables.tableExists(table);
        expect(exists, isTrue);
      }
    });

    test('TEST 13: Schema filtering maintains idempotent results across multiple passes', () async {
      final payload = <String, dynamic>{
        'name': 'Degree Certificate',
        'category': 'Academics',
        'consent': true,
        'random_key': 'drop_me',
      };

      final pass1 = await WalletTables.filterPayloadForTable('w_college', payload);
      final pass2 = await WalletTables.filterPayloadForTable('w_college', pass1);

      expect(pass1.length, equals(pass2.length));
      expect(pass1['name'], equals(pass2['name']));
      expect(pass1['category'], equals(pass2['category']));
      expect(pass2.containsKey('consent'), isFalse);
      expect(pass2.containsKey('random_key'), isFalse);
    });
  });
}
