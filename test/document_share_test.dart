import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/config/share_config.dart';
import 'package:inoapp/models/document_share.dart';
import 'package:inoapp/repositories/share_repository.dart';

DocumentShare _make({
  String status = 'active',
  Duration untilExpiry = const Duration(hours: 1),
}) {
  final now = DateTime.now();
  return DocumentShare.fromMap({
    'id': '11111111-1111-1111-1111-111111111111',
    'share_id': 'share_abc123',
    'token': 'a8f9x2k40b1c',
    'owner_id': 'owner-1',
    'document_ids': ['d1', 'd2'],
    'status': status,
    'views_count': 3,
    'downloads_count': 1,
    'created_at': now.toIso8601String(),
    'expires_at': now.add(untilExpiry).toIso8601String(),
    'last_accessed_at': null,
  });
}

void main() {
  group('ShareDuration', () {
    test('maps each option to the right TTL in seconds', () {
      expect(ShareDuration.tenMinutes.seconds, 600);
      expect(ShareDuration.oneHour.seconds, 3600);
      expect(ShareDuration.twentyFourHours.seconds, 86400);
      expect(ShareDuration.sevenDays.seconds, 604800);
    });

    test('has human labels', () {
      expect(ShareDuration.tenMinutes.label, '10 Minutes');
      expect(ShareDuration.sevenDays.label, '7 Days');
    });
  });

  group('DocumentShare.fromMap', () {
    test('parses columns, token and document ids', () {
      final s = _make();
      expect(s.shareId, 'share_abc123');
      expect(s.token, 'a8f9x2k40b1c');
      expect(s.ownerId, 'owner-1');
      expect(s.documentIds, ['d1', 'd2']);
      expect(s.documentCount, 2);
      expect(s.viewsCount, 3);
      expect(s.downloadsCount, 1);
    });

    test('token falls back to share_id when absent (legacy rows)', () {
      final s = DocumentShare.fromMap({
        'id': 'x',
        'share_id': 'share_legacy',
        'owner_id': 'o',
        'document_ids': <String>[],
        'status': 'active',
        'views_count': 0,
        'downloads_count': 0,
        'created_at': DateTime.now().toIso8601String(),
        'expires_at': DateTime.now().toIso8601String(),
      });
      expect(s.token, 'share_legacy');
    });

    test('maps status strings', () {
      expect(_make(status: 'active').status, ShareStatus.active);
      expect(_make(status: 'expired').status, ShareStatus.expired);
      expect(_make(status: 'revoked').status, ShareStatus.revoked);
      // Unknown / null defaults to active.
      expect(_make(status: 'weird').status, ShareStatus.active);
    });
  });

  group('lifecycle', () {
    test('active + future expiry is live', () {
      final s = _make(untilExpiry: const Duration(hours: 1));
      expect(s.isLive, isTrue);
      expect(s.effectiveStatus, ShareStatus.active);
    });

    test('active but past expiry reads as expired (honours the wall clock)', () {
      final s = _make(untilExpiry: const Duration(seconds: -1));
      expect(s.isLive, isFalse);
      expect(s.effectiveStatus, ShareStatus.expired);
    });

    test('revoked is never live regardless of expiry', () {
      final s = _make(status: 'revoked', untilExpiry: const Duration(days: 1));
      expect(s.isLive, isFalse);
      expect(s.effectiveStatus, ShareStatus.revoked);
    });

    test('copyAsRevoked flips only the status', () {
      final s = _make();
      final r = s.copyAsRevoked();
      expect(r.status, ShareStatus.revoked);
      expect(r.shareId, s.shareId);
      expect(r.documentIds, s.documentIds);
      expect(r.expiresAt, s.expiresAt);
    });
  });

  group('share exceptions', () {
    test('ShareBackendNotConfiguredException has the clear user message', () {
      const e = ShareBackendNotConfiguredException();
      expect(e, isA<ShareException>());
      expect(e.message, 'QR Sharing Backend Not Configured');
    });

    test('ShareException carries an arbitrary message', () {
      const e = ShareException('One or more documents are not yours to share');
      expect(e.message, 'One or more documents are not yours to share');
    });
  });

  group('ShareConfig / share URL', () {
    test('derives the Supabase Functions API base from the project', () {
      expect(ShareConfig.apiBase,
          'https://ilfzppryyojoponkomrw.functions.supabase.co/share');
    });

    test('public share URL uses the token on the public (Vercel) domain', () {
      final s = _make();
      expect(s.url, 'https://ino-share-web.vercel.app/s/a8f9x2k40b1c');
      expect(s.url, ShareConfig.publicUrl('a8f9x2k40b1c'));
      expect(s.url, endsWith('/s/a8f9x2k40b1c'));
    });

    test('api URL points at the Edge Function with the token', () {
      expect(ShareConfig.apiUrl('a8f9x2k40b1c'),
          'https://ilfzppryyojoponkomrw.functions.supabase.co/share/a8f9x2k40b1c');
    });
  });
}
