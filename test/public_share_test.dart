import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/models/public_share.dart';

void main() {
  group('PublicShare.fromJson', () {
    test('parses an active share with documents', () {
      final s = PublicShare.fromJson({
        'status': 'active',
        'shareId': 'share_abc',
        'count': 2,
        'expiresAt': '2026-07-05T12:00:00.000Z',
        'documents': [
          {'id': 'd1', 'name': 'Aadhaar Card', 'type': 'Identity'},
          {'id': 'd2', 'name': 'PAN Card', 'type': 'Identity'},
        ],
      });
      expect(s.status, PublicShareStatus.active);
      expect(s.isActive, isTrue);
      expect(s.count, 2);
      expect(s.documents, hasLength(2));
      expect(s.documents.first.name, 'Aadhaar Card');
      expect(s.documents.first.type, 'Identity');
      expect(s.expiresAt, DateTime.utc(2026, 7, 5, 12));
    });

    test('count falls back to the documents length when absent', () {
      final s = PublicShare.fromJson({
        'status': 'active',
        'documents': [
          {'id': 'd1', 'name': 'Doc', 'type': 'Other'},
        ],
      });
      expect(s.count, 1);
    });

    test('maps expired / revoked / not_found with their messages', () {
      final expired = PublicShare.fromJson(
          {'status': 'expired', 'message': 'This share link has expired'});
      expect(expired.status, PublicShareStatus.expired);
      expect(expired.isActive, isFalse);
      expect(expired.message, 'This share link has expired');

      final revoked = PublicShare.fromJson({'status': 'revoked'});
      expect(revoked.status, PublicShareStatus.revoked);

      final missing = PublicShare.fromJson({'status': 'not_found'});
      expect(missing.status, PublicShareStatus.notFound);
    });

    test('an unknown/absent status becomes error', () {
      expect(PublicShare.fromJson({'status': 'weird'}).status,
          PublicShareStatus.error);
      expect(PublicShare.fromJson({}).status, PublicShareStatus.error);
    });

    test('SharedDoc defaults missing name/type to "Document"', () {
      final d = SharedDoc.fromJson({'id': 'x'});
      expect(d.id, 'x');
      expect(d.name, 'Document');
      expect(d.type, 'Document');
    });
  });
}
