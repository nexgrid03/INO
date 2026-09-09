import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/config/share_config.dart';
import 'package:inoapp/models/document_share.dart';
import 'package:inoapp/models/view_once_share.dart';

void main() {
  group('Secure Link Resilience Tests', () {
    test('ShareConfig URLs never throw FormatException on invalid/empty tokens', () {
      expect(ShareConfig.publicUrl(''), equals(ShareConfig.publicBase));
      expect(ShareConfig.publicUrl('   '), equals(ShareConfig.publicBase));
      expect(ShareConfig.publicUrl('invalid/token/with/slashes'), contains('invalid/token/with/slashes'));

      expect(ShareConfig.apiUrl(''), equals(ShareConfig.apiBase));
      expect(ShareConfig.viewOncePublicUrl(''), equals(ShareConfig.viewOncePublicBase));
      expect(ShareConfig.viewOnceApiUrl(''), contains('/v'));
    });

    test('DocumentShare.fromMap parses defensively without crashing on nulls/missing keys', () {
      final rawMap = <dynamic, dynamic>{
        'id': 'test-uuid-1',
        // missing share_id, token, owner_id
        'document_ids': '{doc1,doc2}', // PostgreSQL array string format
        'status': 'active',
        'created_at': '2026-09-09T12:00:00Z',
        'expires_at': 'invalid-date',
      };

      final share = DocumentShare.fromMap(rawMap);
      expect(share.id, equals('test-uuid-1'));
      expect(share.documentIds, equals(['doc1', 'doc2']));
      expect(share.token, isNotEmpty);
      expect(share.url, isNotEmpty);
      expect(share.expiresAt, isNotNull);
    });

    test('DocumentShare.fromMap parses standard list document_ids', () {
      final rawMap = <dynamic, dynamic>{
        'id': 'test-uuid-2',
        'share_id': 'share_abc123',
        'token': 'tok123',
        'owner_id': 'owner_1',
        'document_ids': ['id_1', 'id_2'],
        'status': 'active',
        'created_at': '2026-09-09T12:00:00Z',
        'expires_at': '2026-09-10T12:00:00Z',
      };

      final share = DocumentShare.fromMap(rawMap);
      expect(share.token, equals('tok123'));
      expect(share.documentIds, equals(['id_1', 'id_2']));
      expect(share.url, equals('${ShareConfig.publicBase}/tok123'));
    });

    test('ViewOnceShare.fromMap parses defensively on missing/invalid timestamps', () {
      final rawMap = <dynamic, dynamic>{
        'id': 'vo-1',
        'token': 'vo-token-1',
        'document_id': 'doc-1',
        'owner_id': 'owner-1',
        'expiry_time': 'invalid-time',
        'created_at': 'invalid-time',
      };

      final vo = ViewOnceShare.fromMap(rawMap);
      expect(vo.id, equals('vo-1'));
      expect(vo.token, equals('vo-token-1'));
      expect(vo.url, isNotEmpty);
      expect(vo.expiryTime, isNotNull);
      expect(vo.createdAt, isNotNull);
    });
  });
}
